package loupe

import std.collection.*
import std.deriving.*
import cjo.{openCjo, Position as CjoPosition}
import ginkgo.{SyntaxNodePtr, TextRange, TokenAtOffset}
import rope.{Encoding, LineColumn, Rope}
import cjsyntax.{CjSyntaxNode, CjSyntaxToken, SyntaxKind}
import cjsyntax.ast.{AnyHasName, AnyHasTypeParams, BinExpr, IndexExpr, NameRef, PathSegment, PathType, UnaryExpr,
    isIdent}
import cjsyntax.ast.SourceFile as SourceFileNode
import loupe.db.{AnalysisDatabase, BinaryPackageFile, BinarySourceFile, SourceFile}
import loupe.hir.*
import loupe.syntax.parse
import loupe.vfs.FileId

/**
 * A declaration a request goes to: its file, its whole node, and its name, what an editor selects;
 * rust-analyzer's `NavigationTarget`. One a macro wrote, which a request in an expansion goes to
 * (`definitionInExpansion`), is in the text of that expansion: `expansion` is its call, the ranges are
 * of `expandedMacro`'s text, `fileId` the call's file.
 */
@Derive[Equatable]
public struct NavigationTarget {
    public NavigationTarget(
        public let fileId: FileId,
        public let fullRange: TextRange,
        public let focusRange: TextRange,
        public let expansion!: ?MacroCallId = None
    ) {}
}

/**
 * Where the name at `offset` of the file is declared: where what `classifyName` says it means is (rust-analyzer's
 * `goto_definition`); the operator function an operator calls (8e); a member `@Derive` adds, at the interface the
 * call names (#175); after a `specific` declaration, the `common` ones it completes (#318); a package in the headers
 * of its files, a name of an `import` what it imports. Nothing for a package compiled already, nor for a declaration
 * of one whose binary's sources are not there (D65).
 */
public func definitionAt(db: AnalysisDatabase, fileId: FileId, offset: Int64): Array<NavigationTarget> {
    let file = db.sourceFile(fileId) ?? return []
    definitionIn(db, ItemFile.Source(file), offset)
}

/**
 * Where the name at `offset` of the text of the expansion of `call` (`expandedMacro`) is declared, as `definitionAt`
 * finds it in a file, the names of the expansion in the scope of the call's file: a declaration whose name the macro
 * copied from the source, there; one the macro or the analysis wrote, in its expansion (`NavigationTarget.expansion`).
 * Nothing in a body of an expansion: the analysis lowers none (`bodyWithSourceMap`).
 */
public func definitionInExpansion(db: AnalysisDatabase, call: MacroCallId, offset: Int64): Array<NavigationTarget> {
    definitionIn(db, ItemFile.Expansion(call), offset)
}

/**
 * Where the name at `offset` of `file`, a source file or an expansion, is declared; into expansions from an expansion
 * only, a request from a source file going where the call writes what it adds.
 */
func definitionIn(db: AnalysisDatabase, file: ItemFile, offset: Int64): Array<NavigationTarget> {
    let scope = scopeFileOf(db, file) ?? return []
    let (root, _) = syntaxOf(db, file) ?? return []
    let token = tokenAt(root, offset) ?? return []
    let defs = classifyName(db, scope, itemAround(db, file, token.parent), token) ?? return []
    let intoExpansions = match (file) {
        case Expansion(_) => true
        case _ => false
    }
    let targets = ArrayList<NavigationTarget>()
    for (one in defs) {
        targets.add(all: targetsOfDefinition(db, one, intoExpansions: intoExpansions))
        // a `specific` declaration, then the `common` ones it completes, as Kotlin's actual and expect (#318)
        if (let DeclDef(id) <- one) {
            targets.add(all: commonsOf(db, id) |> filterMap {common: DefId => declTarget(db, common)} |> collectArray)
        }
    }
    targets.toArray()
}

/**
 * The innermost item `node`, of the tree of `file`, is in, or is.
 */
func itemAround(db: AnalysisDatabase, file: ItemFile, node: CjSyntaxNode): ?DefId {
    let (_, ids) = syntaxOf(db, file) ?? return None
    let item = node.ancestors() |> filterMap {one: CjSyntaxNode => ids.idAround(one)} |> first
    DefId(db, file, item ?? return None)
}

/**
 * Where `definition` is declared: a package in the header of each of its files. A declaration of an expansion there if
 * `intoExpansions` (`declTarget`).
 */
func targetsOfDefinition(db: AnalysisDatabase, definition: Definition, intoExpansions!: Bool = false): Array<NavigationTarget> {
    let one = match (definition) {
        case DeclDef(id) => declTarget(db, id, intoExpansions: intoExpansions)
        case LocalDef(def, local) => localTarget(db, def, local)
        case MemberParamDef(ctor, local) => localTarget(db, ctor, local)
        case TypeParamDef(target) => targetOf(db, target, intoExpansions)
        case PackageDef(pkg) => return packageTargets(db, pkg)
    }
    match (one) {
        case Some(target) => [target]
        case None => []
    }
}

/**
 * The `package` headers of the files of `pkg`, at the path they name: a package has no node of its own. None for a
 * package compiled already, nor for a file that writes none.
 */
func packageTargets(db: AnalysisDatabase, pkg: PackageRef): Array<NavigationTarget> {
    let source = match (pkg) {
        case Source(one) => one
        case Binary(_) => return []
    }
    source.files(db) |> filterMap {fileId: FileId => db.sourceFile(fileId)} |> filterMap {
        file: SourceFile =>
        let header = SourceFileNode.cast(parse(db, file).syntaxNode()).flatMap {node => node.packageHeader()} ??
            return None<NavigationTarget>
        let names = header.nameRefs() |> map {name: NameRef => name.syntax.textRange} |> collectArray
        let first = names.get(0) ?? return None<NavigationTarget>
        NavigationTarget(file.fileId(db), header.syntax.textRange, TextRange(first.start, names[names.size - 1].end))
    } |> collectArray
}

/**
 * The local `local` of the body of `def`: its name, in the node declaring it.
 */
func localTarget(db: AnalysisDatabase, def: DefId, local: LocalId): ?NavigationTarget {
    let (file, name) = localName(db, def, local) ?? return None
    NavigationTarget(file.fileId(db), name.parent?.textRange ?? name.textRange, name.textRange)
}

/**
 * The name of the local `local` of the body of `def`, and its file.
 */
func localName(db: AnalysisDatabase, def: DefId, local: LocalId): ?(SourceFile, CjSyntaxNode) {
    let file = match (def.file(db)) {
        case Source(file) => file
        case _ => return None
    }
    let ptr = bodyWithSourceMap(db, def).sourceMap.locals.get(local.index) ?? return None
    let name = (ptr ?? return None).tryToNode(parse(db, file).syntaxNode()) ?? return None
    (file, name)
}

/**
 * The identifier or `This` at `offset`, the one after it if it is between two.
 */
func tokenAt(root: CjSyntaxNode, offset: Int64): ?CjSyntaxToken {
    let isName = {token: CjSyntaxToken => isIdent(token) || token.kind == SyntaxKind.ThisTypeKw}
    // a name before an operator it touches (`a|+b`)
    match (root.tokenAtOffset(offset)) {
        case Single(token) where isName(token) || isOperator(token) => token
        case Between(left, right) => if (isName(right)) {
            right
        } else if (isName(left)) {
            left
        } else if (isOperator(right)) {
            right
        } else if (isOperator(left)) {
            left
        } else {
            None
        }
        case _ => None
    }
}

/**
 * Whether `token` is an operator: the operator of a binary or unary expression, or a bracket of an index.
 */
func isOperator(token: CjSyntaxToken): Bool {
    let parent = token.parent
    if (IndexExpr.canCast(parent.kind)) {
        return token.kind == SyntaxKind.LBracket || token.kind == SyntaxKind.RBracket
    }
    let op = BinExpr.cast(parent).flatMap {expr => expr.op()} ?? UnaryExpr.cast(parent).flatMap {expr => expr.op()} ??
        return false
    op.textRange == token.textRange
}

/**
 * The type `token` is a name in, and the index of its segment: a `PathType`'s, or a `ThisType`.
 */
func typeAt(token: CjSyntaxToken): ?(CjSyntaxNode, Int64) {
    let parent = token.parent
    if (parent.kind == SyntaxKind.ThisType) {
        return (parent, 0)
    }
    let segment = parent.parent.flatMap {node => PathSegment.cast(node)} ?? return None
    let path = segment.syntax.parent.flatMap {node => PathType.cast(node)} ?? return None
    let index = path.pathSegments() |> enumerate |> filter {pair: (Int64, PathSegment) => pair[1] == segment} |>
        map {pair: (Int64, PathSegment) => pair[0]} |> first
    (path.syntax, index ?? return None)
}

/**
 * Where `target` is declared; `None` for a package, or a declaration with no source.
 */
func targetOf(db: AnalysisDatabase, target: TypeTarget, intoExpansions: Bool): ?NavigationTarget {
    match (target) {
        case TypeOf(id) => declTarget(db, id, intoExpansions: intoExpansions)
        case GenericOf(owner, index) =>
            if (let Expansion(call) <- owner.file(db)) {
                let (full, focus) = genericRanges(itemNodeOf(db, owner) ?? return None, index) ?? return None
                return expansionTarget(db, call, full, focus)
            }
            let (file, node) = nodeOf(db, owner) ?? return None
            genericTarget(db, file, node, index)
        case LocalGenericOf(owner, localFunc, index) =>
            let file = match (owner.file(db)) {
                case Source(file) => file
                case _ => return None
            }
            let lowered = bodyWithSourceMap(db, owner)
            let local = lowered.body.funcs.get(localFunc)?.local ?? return None
            let ptr = lowered.sourceMap.locals.get(local.index) ?? return None
            let name = (ptr ?? return None).tryToNode(parse(db, file).syntaxNode()) ?? return None
            genericTarget(db, file, name.parent ?? return None, index)
        case QualifierOf(_) => None
    }
}

/**
 * The type parameter at `index` of the declaration `node`.
 */
func genericTarget(db: AnalysisDatabase, file: SourceFile, node: CjSyntaxNode, index: Int64): ?NavigationTarget {
    let (full, focus) = genericRanges(node, index) ?? return None
    NavigationTarget(file.fileId(db), full, focus)
}

/**
 * The type parameter at `index` of the declaration `node`, and its name.
 */
func genericRanges(node: CjSyntaxNode, index: Int64): ?(TextRange, TextRange) {
    let params = AnyHasTypeParams.cast(node).flatMap {it => it.typeParamList()} ?? return None
    let param = (params.typeParams() |> skip(index) |> first) ?? return None
    (param.syntax.textRange, param.name()?.syntax.textRange ?? param.syntax.textRange)
}

/**
 * `full` and `focus`, ranges of the text of the expansion of `call`: in the call's file if the macro copied `focus`
 * from there (`sourceRangeOf`), `full` too if it copied it whole; in the expansion if it wrote it.
 */
func expansionTarget(db: AnalysisDatabase, call: MacroCallId, full: TextRange, focus: TextRange): NavigationTarget {
    let fileId = call.file(db).fileId(db)
    match (sourceRangeOf(db, call, focus)) {
        case Some(source) =>
            let around = sourceRangeOf(db, call, full).flatMap {
                one: TextRange => if (one.containsRange(source)) {
                    Some(one)
                } else {
                    None<TextRange>
                }
            }
            NavigationTarget(fileId, around ?? source, source)
        case None => NavigationTarget(fileId, full, focus, expansion: call)
    }
}

/**
 * Where the declaration `id` is: its node and its name; for one of a package compiled already, where
 * its `.cjo` says it is in the sources of its binary; for one a macro call adds, what in the call
 * adds it, the interface of `@Derive[...]`; but if `intoExpansions` where its expansion declares
 * it, unless the macro copied its name from the source.
 */
func declTarget(db: AnalysisDatabase, id: DefId, intoExpansions!: Bool = false): ?NavigationTarget {
    match (id.file(db)) {
        case Binary(pkg, file) => return binaryTarget(db, pkg, file, id.item(db))
        // what a macro call adds: where the call writes it (#175)
        case Expansion(call) =>
            if (intoExpansions && let Some(node) <- itemNodeOf(db, id)) {
                let name = AnyHasName.cast(node).flatMap {it => it.name()}?.syntax.textRange ?? node.textRange
                if (sourceRangeOf(db, call, name).isNone()) {
                    return NavigationTarget(call.file(db).fileId(db), node.textRange, name, expansion: call)
                }
            }
            let (focus, full) = expansionOrigin(db, call, id.item(db)) ?? return None
            return NavigationTarget(call.file(db).fileId(db), full, focus)
        case Source(_) => ()
    }
    let (file, node) = nodeOf(db, id) ?? return None
    let name = AnyHasName.cast(node).flatMap {it => it.name()}
    NavigationTarget(file.fileId(db), node.textRange, name?.syntax.textRange ?? node.textRange)
}

/**
 * Where the item `id` of the file `file` of `pkg` is in the sources of its binary: from the start of
 * its declaration to the end, and its name, at the positions its `.cjo` gives, which are of the
 * sources it was compiled from (D65). `None` without the sources, and wherever its name is not
 * written at its position: sources of another version, or a declaration cjc made (a `BuiltInDecl`'s
 * position is none, a `let` of a pattern has no name).
 */
func binaryTarget(db: AnalysisDatabase, pkg: BinaryPackageFile, file: Int64, id: ItemId): ?NavigationTarget {
    let index = binaryExports(db, pkg).declIndex(BinaryItem(file, id)) ?? return None
    let name = (findItem(itemTreeOf(db, ItemFile.Binary(pkg, file)).items, id)?.names ?? []).get(0) ?? return None
    // the positions of cjc: lines and columns from 1, columns in bytes, the end past the declaration
    let (fileName, begin, end, at) = try {
        let cjo = openCjo(pkg.bytes(db))
        let decl = cjo.allDecls[index]
        let lineColumn = {position: ?CjoPosition => position.map {it => (Int64(it.line) - 1, Int64(it.column) - 1)}}
        (cjo.allFiles[file], lineColumn(decl.begin), lineColumn(decl.end), lineColumn(decl.identifierPos))
    } catch (_: Exception) {
        return None
    }
    let binary = pkg.binary(db)
    let sources = db.project()?.binarySources(db) ?? return None
    let fileId = (sources |> filter {source: BinarySourceFile => source.binary == binary && source.name == fileName} |>
        map {source: BinarySourceFile => source.fileId} |> first) ?? return None
    let text = (db.sourceFile(fileId) ?? return None).text(db)
    let offsetOf = {
        position: ?(Int64, Int64) => match (position) {
            case Some((line, column)) where line >= 0 && column >= 0 && line < text.lineCount =>
                Some(text.offsetOf(LineColumn(line, column), Encoding.Utf8))
            case _ => Option<Int64>.None
        }
    }
    // a name in backquotes is at the name, inside them
    let start = offsetOf(at) ?? return None
    if (!writes(text, start, name)) {
        return None
    }
    let focus = TextRange(start, start + name.size)
    let full = match ((offsetOf(begin), offsetOf(end))) {
        case (Some(from), Some(to)) where from <= focus.start && focus.end <= to => TextRange(from, to)
        case _ => focus
    }
    NavigationTarget(fileId, full, focus)
}

/**
 * The item `id` among `items` and their members.
 */
func findItem(items: Array<Item>, id: ItemId): ?Item {
    for (item in items) {
        if (item.id == id) {
            return item
        }
        if (let Some(member) <- findItem(item.members, id)) {
            return member
        }
    }
    None
}

/**
 * Whether `text` has `written` at `offset`.
 */
func writes(text: Rope, offset: Int64, written: String): Bool {
    offset + written.size <= text.size && text.slice(offset..offset + written.size).toString() == written
}

/**
 * The node of `id`, in a source file or an expansion, if it is there still.
 */
func itemNodeOf(db: AnalysisDatabase, id: DefId): ?CjSyntaxNode {
    let (root, ids) = syntaxOf(db, id.file(db)) ?? return None
    ids.node(id.item(db), root)
}

/**
 * The file and the node of `id`, if it is in a source file still.
 */
func nodeOf(db: AnalysisDatabase, id: DefId): ?(SourceFile, CjSyntaxNode) {
    let file = match (id.file(db)) {
        case Source(file) => file
        case _ => return None
    }
    let node = itemIdMap(db, file).node(id.item(db), parse(db, file).syntaxNode()) ?? return None
    (file, node)
}
