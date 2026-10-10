package loupe

import std.collection.*
import std.deriving.*
import cjo.DeclInfo
import ginkgo.{Direction, SyntaxElement, SyntaxNodePtr, TokenSet}
// the API's ranges, for whoever asks for a part of a file
public import ginkgo.TextRange
import cjsyntax.{CjSyntaxNode, CjSyntaxToken, SyntaxKind}
import cjsyntax.ast.{Annotation, Decl}
import loupe.vfs.FileId
import loupe.db.{AnalysisDatabase, Package, SourceFile}
import loupe.hir.*
import loupe.syntax.parse

/**
 * What a token is: by the tree, and a name at its use by what it means (D72). In a file of no
 * package, which names do not resolve in, a name inside a type is taken for one.
 */
@Derive[Equatable]
public enum HighlightTag <: ToString {
    | Keyword
    | Comment
    | StringLiteral
    | NumberLiteral
    | Operator
    // `@Deprecated` and the other annotations the compiler knows: the `@` and the name
    | BuiltinAnnotation
    // the `@` and the name of a macro call
    | MacroCall
    // `Int64`, `Bool`, `VArray`: keywords naming types
    | BuiltinType
    // a name inside a type, in a file of no package
    | TypeName
    | TypeParameter
    | Parameter
    // a name of what a declaration declares, as the outline calls it: at the declaration, or at a use
    | Symbol(StructureKind)
    // a package, in a path
    | Namespace
    // a name that means nothing
    | UnresolvedReference

    public func toString(): String {
        match (this) {
            case Keyword => "Keyword"
            case Comment => "Comment"
            case StringLiteral => "StringLiteral"
            case NumberLiteral => "NumberLiteral"
            case Operator => "Operator"
            case BuiltinAnnotation => "BuiltinAnnotation"
            case MacroCall => "MacroCall"
            case BuiltinType => "BuiltinType"
            case TypeName => "TypeName"
            case TypeParameter => "TypeParameter"
            case Parameter => "Parameter"
            case Symbol(kind) => kind.toString()
            case Namespace => "Namespace"
            case UnresolvedReference => "UnresolvedReference"
        }
    }
}

@Derive[Equatable]
public enum HighlightModifier <: ToString {
    // the name being declared
    | Declaration
    // a comment documenting the declaration it is attached to
    | Documentation
    // declared with `let` or `const`
    | Readonly
    | Static
    // declared with `@Deprecated`
    | Deprecated
    // of `std`, or a type of the language itself
    | DefaultLibrary
    // declared with `var`, or a `mut` property
    | Mutable

    func bit(): UInt8 {
        match (this) {
            case Declaration => 1
            case Documentation => 2
            case Readonly => 4
            case Static => 8
            case Deprecated => 16
            case DefaultLibrary => 32
            case Mutable => 64
        }
    }

    public func toString(): String {
        match (this) {
            case Declaration => "Declaration"
            case Documentation => "Documentation"
            case Readonly => "Readonly"
            case Static => "Static"
            case Deprecated => "Deprecated"
            case DefaultLibrary => "DefaultLibrary"
            case Mutable => "Mutable"
        }
    }
}

let HIGHLIGHT_MODIFIERS = [HighlightModifier.Declaration, HighlightModifier.Documentation, HighlightModifier.Readonly,
    HighlightModifier.Static, HighlightModifier.Deprecated, HighlightModifier.DefaultLibrary,
    HighlightModifier.Mutable]

/**
 * A set of `HighlightModifier`s.
 */
@Derive[Equatable]
public struct HighlightModifiers <: ToString {
    private HighlightModifiers(let bits: UInt8) {}

    public static let NONE = HighlightModifiers(0)

    public func plus(modifier: HighlightModifier): HighlightModifiers {
        HighlightModifiers(bits | modifier.bit())
    }

    public func contains(modifier: HighlightModifier): Bool {
        (bits & modifier.bit()) != 0
    }

    public func isEmpty(): Bool {
        bits == 0
    }

    public func toString(): String {
        let bits = this.bits
        String.join(HIGHLIGHT_MODIFIERS.filter {m => (bits & m.bit()) != 0}.map {m => m.toString()}, delimiter: ", ")
    }
}

/**
 * A token of a file and what it is. `range` is in UTF-8 bytes (A6).
 */
@Derive[Equatable]
public struct HighlightedRange <: ToString {
    public HighlightedRange(
        public let range: TextRange,
        public let tag: HighlightTag,
        public let modifiers!: HighlightModifiers = HighlightModifiers.NONE
    ) {}

    /**
     * `tag[modifiers]@start..end`.
     */
    public func toString(): String {
        let modifiers = if (this.modifiers.isEmpty()) {
            ""
        } else {
            "[${this.modifiers}]"
        }
        "${tag}${modifiers}@${range.start}..${range.end}"
    }
}

/**
 * The tokens of a file and what each is, in the order of the text, none overlapping: only those
 * `range` intersects if given. A name at its use is told by what `classifyName` says it means, the
 * first of several (D72); one that means nothing is an `UnresolvedReference`. A token nothing is
 * known of is left out: punctuation, a name at a use resolution does not tell yet, and any name at
 * its use in a file of no package. Whatever sits in an `ErrorNode` is told by its kind alone. Empty
 * for a file the database does not know.
 *
 * Not a query: a range in its key would be a position (A2, A3). What it reads, `parse` and
 * resolution, are; a range infers only the bodies of the items it holds.
 */
public func highlight(db: AnalysisDatabase, fileId: FileId, range!: ?TextRange = None): Array<HighlightedRange> {
    let file = db.sourceFile(fileId) ?? return []
    let highlighter = Highlighter(db, file, range)
    highlighter.walk(parse(db, file).syntaxNode(), false, None)
    highlighter.result.toArray()
}

/**
 * How many tokens are highlighted between two checks for a write waiting: a large file does not
 * hold one up.
 */
let TOKENS_BETWEEN_CHECKS = 1024

/**
 * Where a name used is resolved: in an expression, after a `.`, in a type or a pattern, of a macro
 * call.
 */
let RESOLVED_IN = TokenSet<SyntaxKind>([SyntaxKind.RefExpr, SyntaxKind.MemberAccessExpr, SyntaxKind.PathSegment,
    SyntaxKind.MacroExpandDecl, SyntaxKind.MacroExpandExpr])

let PATTERNS = TokenSet<SyntaxKind>([SyntaxKind.WildcardPat, SyntaxKind.LiteralPat, SyntaxKind.BindPat,
    SyntaxKind.TypePat, SyntaxKind.TuplePat, SyntaxKind.EnumPat])

class Highlighter {
    Highlighter(private let db: AnalysisDatabase, private let file: SourceFile, private let range: ?TextRange) {
        ids = match (packageOfFile(db, file)) {
            case Some(_) => itemIdMap(db, file)
            case None => None
        }
    }

    let result = ArrayList<HighlightedRange>()
    private var tokens = 0
    // the items of the file, if it is in a package: names resolve only there
    private let ids: ?ItemIdMap
    // what a name meaning each declaration is, once a request
    private let declarations = HashMap<DefId, ?Highlight>()
    // what a name meaning each local is, by the body and the local, once a request
    private let locals = HashMap<DefId, HashMap<Int64, ?Highlight>>()

    /**
     * The tokens of `node`, `item` the innermost item around it.
     */
    func walk(node: CjSyntaxNode, inError: Bool, item: ?DefId): Unit {
        let inErrorNode = inError || node.kind == SyntaxKind.ErrorNode
        let here = match (ids) {
            case Some(ids) where Decl.canCast(node.kind) || node.kind == SyntaxKind.ImportDecl =>
                match (ids.idOf(SyntaxNodePtr(node))) {
                    case Some(id) => DefId(db, ItemFile.Source(file), id)
                    case None => item
                }
            case _ => item
        }
        for (child in node.childrenWithTokens()) {
            if (!wanted(child.textRange)) {
                continue
            }
            match (child) {
                case SyntaxElement.Node(inner) => walk(inner, inErrorNode, here)
                case SyntaxElement.Token(token) => add(token, inErrorNode, here)
            }
        }
    }

    private func wanted(element: TextRange): Bool {
        let range = this.range
        !element.isEmpty() && match (range) {
            case Some(it) => element.start < it.end && it.start < element.end
            case None => true
        }
    }

    private func add(token: CjSyntaxToken, inError: Bool, item: ?DefId): Unit {
        tokens++
        if (tokens % TOKENS_BETWEEN_CHECKS == 0) {
            db.unwindIfCancelled()
        }
        let syntactic = classify(token, inError)
        let found = if (inError || ids.isNone() || token.kind != SyntaxKind.Ident) {
            syntactic
        } else {
            match (resolved(token, item, syntactic)) {
                case Some(one) => one
                case None => syntactic
            }
        }
        match (found) {
            case Some((tag, modifiers)) => result.add(HighlightedRange(token.textRange, tag, modifiers: modifiers))
            case None => ()
        }
    }

    /**
     * What the name `token` is by what it means, if resolution tells: a name used, and a lone name a
     * pattern binds, a constructor or a variable.
     */
    private func resolved(token: CjSyntaxToken, item: ?DefId, syntactic: ?Highlight): ?Highlight {
        let name = token.parent
        let owner = name.parent ?? return None
        let declares = name.kind == SyntaxKind.Name
        if (declares && (syntactic.isSome() || owner.kind != SyntaxKind.BindPat)) {
            return None
        }
        if (!declares && !RESOLVED_IN.contains(owner.kind)) {
            return None
        }
        let defs = classifyName(db, file, item, token) ?? return None
        match (defs.get(0)) {
            case Some(LocalDef(def, local)) where declares => localHighlight(def, local).map {
                found => (found[0], found[1].plus(HighlightModifier.Declaration))
            }
            case Some(one) => definitionHighlight(one)
            // a macro is known by its call, if not by its name
            case None where owner.kind == SyntaxKind.MacroExpandDecl || owner.kind == SyntaxKind.MacroExpandExpr => None
            // a member a macro called on its type may add, as `@Derive` does
            case None where owner.kind == SyntaxKind.MemberAccessExpr => None
            case None where macrosMayDeclare() => None
            case None => tagged(HighlightTag.UnresolvedReference)
        }
    }

    private var workspaceMacros: ?Bool = None

    /**
     * Whether a macro of the package may have declared what a name means: one of the workspace, or
     * of no package found, called on a declaration of the package, which is not run yet (#176).
     */
    private func macrosMayDeclare(): Bool {
        if (let Some(known) <- workspaceMacros) {
            return known
        }
        let found = match (packageOfFile(db, file)) {
            case Some(pkg) => callsMacrosOfItsOwn(db, pkg)
            case None => false
        }
        workspaceMacros = found
        found
    }

    private func definitionHighlight(definition: Definition): ?Highlight {
        match (definition) {
            case DeclDef(id) => match (declarations.get(id)) {
                case Some(known) => known
                case None =>
                    let found = declarationHighlight(db, id)
                    declarations.add(id, found)
                    found
            }
            case LocalDef(def, local) =>
                let known = match (locals.get(def)) {
                    case Some(one) => one
                    case None =>
                        let one = HashMap<Int64, ?Highlight>()
                        locals.add(def, one)
                        one
                }
                match (known.get(local.index)) {
                    case Some(found) => found
                    case None =>
                        let found = localHighlight(def, local)
                        known.add(local.index, found)
                        found
                }
            case MemberParamDef(ctor, local) =>
                let field = HighlightTag.Symbol(StructureKind.Field)
                let (_, name) = localName(db, ctor, local) ?? return tagged(field)
                (field, mutability(name.parent ?? name, HighlightModifiers.NONE))
            case TypeParamDef(_) => tagged(HighlightTag.TypeParameter)
            case PackageDef(_) => tagged(HighlightTag.Namespace)
        }
    }

    /**
     * A local of the body of `def`: a parameter, a function, or a variable, `let` or `var`.
     */
    private func localHighlight(def: DefId, local: LocalId): ?Highlight {
        let variable = HighlightTag.Symbol(StructureKind.Variable)
        match (bodyWithSourceMap(db, def).body[local].kind) {
            case ParamLocal | LambdaParamLocal => tagged(HighlightTag.Parameter)
            case FuncLocal => tagged(HighlightTag.Symbol(StructureKind.Function))
            case VarLocal =>
                let (_, name) = localName(db, def, local) ?? return tagged(variable)
                let decl = (name.ancestors() |> filter {
                    node: CjSyntaxNode => node != name && !PATTERNS.contains(node.kind)
                } |> first<CjSyntaxNode>) ?? name
                (variable, mutability(decl, HighlightModifiers.NONE))
            case _ => tagged(variable)
        }
    }
}

/**
 * Whether a declaration of `pkg` is under a call of a macro not of a package compiled already: the
 * workspace's, or one nothing declares.
 */
func callsMacrosOfItsOwn(db: AnalysisDatabase, pkg: Package): Bool {
    for (one in filesOf(db, PackageRef.Source(pkg))) {
        let file = match (one) {
            case Source(file) => file
            case _ => continue
        }
        for (item in itemTree(db, file).items) {
            for (name in item.macros where !isCompiledMacro(db, pkg, file, name)) {
                return true
            }
        }
    }
    false
}

/**
 * Whether the macro `name` names in `file` is of a package compiled already.
 */
func isCompiledMacro(db: AnalysisDatabase, pkg: Package, file: SourceFile, name: String): Bool {
    let resolved = resolveMacroPath(db, pkg, file, name.split("."))
    match (resolved.get(resolved.size - 1)) {
        case Some(Found(ids)) => ids.size > 0 && (ids |> all {
            id: DefId => match (id.file(db)) {
                case Binary(_, _) => true
                case _ => false
            }
        })
        case _ => false
    }
}

/**
 * What a name meaning the declaration `id` is: what the outline calls it, with what its modifiers
 * tell; `defaultLibrary` for one of `std`.
 */
func declarationHighlight(db: AnalysisDatabase, id: DefId): ?Highlight {
    let file = id.file(db)
    let item = declItemOf(db, id) ?? return None
    var modifiers = HighlightModifiers.NONE
    let source = match (file) {
        case Source(_) => nodeOf(db, id).flatMap {found => Decl.cast(found[1])}
        case Binary(pkg, _) =>
            if (pkg.binary(db) == "std") {
                modifiers = modifiers.plus(HighlightModifier.DefaultLibrary)
            }
            Option<Decl>.None
        // what `@Derive` adds: no modifier its call writes (#175)
        case Expansion(_) => Option<Decl>.None
    }
    if (item.has(Modifier.Static)) {
        modifiers = modifiers.plus(HighlightModifier.Static)
    }
    if (let Some(decl) <- source && isDeprecated(decl)) {
        modifiers = modifiers.plus(HighlightModifier.Deprecated)
    }
    let member = parentOf(db, id).isSome()
    let kind = match (item.kind) {
        case ItemKind.Func => if (member) {
            StructureKind.Method
        } else {
            StructureKind.Function
        }
        case ItemKind.Main => StructureKind.Main
        case ItemKind.Macro => StructureKind.Macro
        case ItemKind.Class => StructureKind.Class
        case ItemKind.Interface => StructureKind.Interface
        case ItemKind.Struct => StructureKind.Struct
        case ItemKind.Enum => StructureKind.Enum
        case ItemKind.Extend => StructureKind.Extension
        case ItemKind.TypeAlias => StructureKind.TypeAlias
        case ItemKind.Var where item.has(Modifier.Const) =>
            modifiers = modifiers.plus(HighlightModifier.Readonly)
            StructureKind.Constant
        case ItemKind.Var =>
            modifiers = modifiers.plus(if (isMutable(db, id, source)) {
                HighlightModifier.Mutable
            } else {
                HighlightModifier.Readonly
            })
            if (member) {
                StructureKind.Field
            } else {
                StructureKind.Variable
            }
        case ItemKind.Prop =>
            if (item.has(Modifier.Mut)) {
                modifiers = modifiers.plus(HighlightModifier.Mutable)
            }
            StructureKind.Property
        case ItemKind.Init | ItemKind.PrimaryInit => StructureKind.Constructor
        case ItemKind.Finalizer => StructureKind.Finalizer
        case ItemKind.EnumCtor => StructureKind.EnumConstructor
        case ItemKind.BuiltIn => return (HighlightTag.BuiltinType, modifiers.plus(HighlightModifier.DefaultLibrary))
        case ItemKind.Import | ItemKind.MacroCall => return None
    }
    (HighlightTag.Symbol(kind), modifiers)
}

/**
 * Whether the variable `id` is a `var`: as its source writes it, or as its binary stored it.
 */
func isMutable(db: AnalysisDatabase, id: DefId, source: ?Decl): Bool {
    match (id.file(db)) {
        case Source(_) | Expansion(_) => match (source) {
            case Some(decl) => hasToken(decl.syntax, SyntaxKind.VarKw)
            case None => false
        }
        case Binary(pkg, index) => match (binaryDecl(db, pkg, BinaryItem(index, id.item(db))).flatMap {decl => decl.info}) {
            case Some(DeclInfo.AsVarInfo(info)) => info.isVar
            case Some(DeclInfo.AsVarWithPatternInfo(info)) => info.isVar
            case _ => false
        }
    }
}

/**
 * `modifiers`, and `readonly` for what `decl` declares with `let`, `mutable` with `var`.
 */
func mutability(decl: CjSyntaxNode, modifiers: HighlightModifiers): HighlightModifiers {
    if (hasToken(decl, SyntaxKind.LetKw)) {
        modifiers.plus(HighlightModifier.Readonly)
    } else if (hasToken(decl, SyntaxKind.VarKw)) {
        modifiers.plus(HighlightModifier.Mutable)
    } else {
        modifiers
    }
}

let NUMBERS = TokenSet<SyntaxKind>([SyntaxKind.IntLit, SyntaxKind.FloatLit])

let STRINGS = TokenSet<SyntaxKind>([SyntaxKind.RuneLit, SyntaxKind.ByteLit, SyntaxKind.RawStringLit,
    SyntaxKind.StringStart, SyntaxKind.StringContent, SyntaxKind.StringEnd])

let BUILTIN_TYPES = TokenSet<SyntaxKind>([SyntaxKind.Int8Kw, SyntaxKind.Int16Kw, SyntaxKind.Int32Kw,
    SyntaxKind.Int64Kw, SyntaxKind.IntNativeKw, SyntaxKind.UInt8Kw, SyntaxKind.UInt16Kw, SyntaxKind.UInt32Kw,
    SyntaxKind.UInt64Kw, SyntaxKind.UIntNativeKw, SyntaxKind.Float16Kw, SyntaxKind.Float32Kw, SyntaxKind.Float64Kw,
    SyntaxKind.RuneKw, SyntaxKind.BoolKw, SyntaxKind.NothingKw, SyntaxKind.UnitKw, SyntaxKind.VArrayKw])

/**
 * Punctuation that is no operator wherever it is.
 */
let NOT_OPERATORS = TokenSet<SyntaxKind>([SyntaxKind.Dot, SyntaxKind.Comma, SyntaxKind.LParen, SyntaxKind.RParen,
    SyntaxKind.LBracket, SyntaxKind.RBracket, SyntaxKind.LBrace, SyntaxKind.RBrace, SyntaxKind.Colon,
    SyntaxKind.ColonColon, SyntaxKind.Semicolon, SyntaxKind.DotDotDot, SyntaxKind.Hash, SyntaxKind.At,
    SyntaxKind.AtBang, SyntaxKind.Dollar, SyntaxKind.Backslash])

/**
 * Nodes whose punctuation is brackets, separators or a path, not operators: the `<` `>` of type
 * arguments, the `|` between enum constructors, the `*` of an import.
 */
let NO_OPERATORS_IN = TokenSet<SyntaxKind>([SyntaxKind.TypeArgList, SyntaxKind.TypeParamList,
    SyntaxKind.VArrayType, SyntaxKind.EnumBody, SyntaxKind.ImportTree])

/**
 * What only holds declarations: those inside are where it is.
 */
let DECLARATION_HOLDERS = TokenSet<SyntaxKind>([SyntaxKind.MacroExpandDecl, SyntaxKind.ForeignBlock])

type Highlight = (HighlightTag, HighlightModifiers)

func tagged(tag: HighlightTag): ?Highlight {
    (tag, HighlightModifiers.NONE)
}

func declaration(tag: HighlightTag): ?Highlight {
    (tag, HighlightModifiers.NONE.plus(HighlightModifier.Declaration))
}

/**
 * By where the token is, then by its kind; in an `ErrorNode` by its kind alone.
 */
func classify(token: CjSyntaxToken, inError: Bool): ?Highlight {
    let kind = token.kind
    let parent = token.parent
    if (kind == SyntaxKind.LineComment || kind == SyntaxKind.BlockComment) {
        if (isDocumentation(token)) {
            (HighlightTag.Comment, HighlightModifiers.NONE.plus(HighlightModifier.Documentation))
        } else {
            tagged(HighlightTag.Comment)
        }
    } else if (NUMBERS.contains(kind)) {
        tagged(HighlightTag.NumberLiteral)
    } else if (STRINGS.contains(kind)) {
        tagged(HighlightTag.StringLiteral)
    } else if (BUILTIN_TYPES.contains(kind)) {
        (HighlightTag.BuiltinType, HighlightModifiers.NONE.plus(HighlightModifier.DefaultLibrary))
    } else if (!inError && parent.kind == SyntaxKind.Name) {
        declaredName(parent)
    } else if (!inError && parent.kind == SyntaxKind.NameRef) {
        usedName(parent)
    } else if (!inError && (kind == SyntaxKind.At || kind == SyntaxKind.AtBang)) {
        callOrAnnotation(parent)
    } else if (!inError && (kind == SyntaxKind.Ident && parent.kind == SyntaxKind.PropAccessor ||
        kind == SyntaxKind.Tilde && parent.kind == SyntaxKind.FinalizerDecl)) {
        // `get` and `set`, and the `~` of `~init`
        tagged(HighlightTag.Keyword)
    } else if (kind.isKeyword()) {
        tagged(HighlightTag.Keyword)
    } else if (kind.isPunctuation() && !NOT_OPERATORS.contains(kind) && (inError ||
        !NO_OPERATORS_IN.contains(parent.kind))) {
        tagged(HighlightTag.Operator)
    } else {
        None
    }
}

/**
 * A comment is documentation when the parser gave it to a declaration, before all of it.
 */
func isDocumentation(comment: CjSyntaxToken): Bool {
    let owner = comment.parent.kind
    (Decl.canCast(owner) || owner == SyntaxKind.PackageHeader) &&
        (comment.siblingsWithTokens(Direction.Prev) |> all {element: SyntaxElement<SyntaxKind> => element.kind.isTrivia()})
}

/**
 * The name `name` declares, by what declares it.
 */
func declaredName(name: CjSyntaxNode): ?Highlight {
    let owner = name.parent ?? return None
    match (owner.kind) {
        case SyntaxKind.TypeParam => declaration(HighlightTag.TypeParameter)
        case SyntaxKind.LambdaParam | SyntaxKind.NamedType => declaration(HighlightTag.Parameter)
        case SyntaxKind.Param => parameter(owner)
        case SyntaxKind.BindPat | SyntaxKind.TypePat => binding(owner)
        case SyntaxKind.CatchPat | SyntaxKind.ResourceDecl => declaration(HighlightTag.Symbol(StructureKind.Variable))
        case _ => declared(Decl.cast(owner) ?? return None)
    }
}

/**
 * A parameter of a primary constructor declared `let` or `var` is a member variable as well.
 */
func parameter(param: CjSyntaxNode): ?Highlight {
    let modifiers = HighlightModifiers.NONE.plus(HighlightModifier.Declaration)
    if (hasToken(param, SyntaxKind.LetKw)) {
        (HighlightTag.Symbol(StructureKind.Field), modifiers.plus(HighlightModifier.Readonly))
    } else if (hasToken(param, SyntaxKind.VarKw)) {
        (HighlightTag.Symbol(StructureKind.Field), modifiers.plus(HighlightModifier.Mutable))
    } else {
        (HighlightTag.Parameter, modifiers)
    }
}

/**
 * A name a pattern binds. In a `case` or a `let` condition a lone name may as well be an enum
 * constructor, which only names resolved tell.
 */
func binding(pattern: CjSyntaxNode): ?Highlight {
    let site = (pattern.ancestors() |> filter {node: CjSyntaxNode => !PATTERNS.contains(node.kind)} |>
        first<CjSyntaxNode>) ?? return None
    match (Decl.cast(site)) {
        case Some(decl) => declared(decl)
        case None where site.kind == SyntaxKind.ForInExpr || pattern.kind == SyntaxKind.TypePat =>
            declaration(HighlightTag.Symbol(StructureKind.Variable))
        case None => None
    }
}

/**
 * The name of `decl`, as the outline has it, with what its modifiers and annotations tell.
 */
func declared(decl: Decl): ?Highlight {
    let node = decl.syntax
    let kind = declarationKind(decl, isMember(node)) ?? return None
    var modifiers = HighlightModifiers.NONE.plus(HighlightModifier.Declaration)
    if (decl.modifiers()?.isStatic() ?? false) {
        modifiers = modifiers.plus(HighlightModifier.Static)
    }
    if (kind == StructureKind.Constant || hasToken(node, SyntaxKind.LetKw)) {
        modifiers = modifiers.plus(HighlightModifier.Readonly)
    } else if (hasToken(node, SyntaxKind.VarKw) ||
        (decl.modifiers().map {it => hasToken(it.syntax, SyntaxKind.MutKw)} ?? false)) {
        modifiers = modifiers.plus(HighlightModifier.Mutable)
    }
    if (isDeprecated(decl)) {
        modifiers = modifiers.plus(HighlightModifier.Deprecated)
    }
    (HighlightTag.Symbol(kind), modifiers)
}

/**
 * Whether `decl` is a type's member, as the outline has it: inside its body, maybe through a macro
 * call or a `foreign` block.
 */
func isMember(decl: CjSyntaxNode): Bool {
    let container = decl.ancestors() |>
        filter {node: CjSyntaxNode => node != decl && !DECLARATION_HOLDERS.contains(node.kind)} |> first<CjSyntaxNode>
    match (container) {
        case Some(it) => it.kind == SyntaxKind.DeclBody || it.kind == SyntaxKind.EnumBody
        case None => false
    }
}

func hasToken(node: CjSyntaxNode, kind: SyntaxKind): Bool {
    node.childrenWithTokens() |> any {element: SyntaxElement<SyntaxKind> => element.kind == kind}
}

func isDeprecated(decl: Decl): Bool {
    decl.annotations() |> any {annotation: Annotation => annotation.nameRef()?.text() == Some("Deprecated")}
}

/**
 * A name used: known only in an annotation, a macro call, or a type, which it is taken to name.
 */
func usedName(nameRef: CjSyntaxNode): ?Highlight {
    let owner = nameRef.parent ?? return None
    match (owner.kind) {
        case SyntaxKind.PathSegment where (owner.parent?.kind == Some(SyntaxKind.PathType)) => tagged(
            HighlightTag.TypeName)
        case SyntaxKind.PackageHeader => tagged(HighlightTag.Namespace)
        // a segment of an import another follows: a package
        case SyntaxKind.ImportTree where isQualifier(nameRef) => tagged(HighlightTag.Namespace)
        case _ => callOrAnnotation(owner)
    }
}

/**
 * Whether a `.` or a `::` follows `nameRef`.
 */
func isQualifier(nameRef: CjSyntaxNode): Bool {
    let next = nameRef.siblingsWithTokens(Direction.Next) |> filter {
        element: SyntaxElement<SyntaxKind> => element.textRange != nameRef.textRange && !element.kind.isTrivia()
    } |> map {element: SyntaxElement<SyntaxKind> => element.kind} |> first
    next == Some(SyntaxKind.Dot) || next == Some(SyntaxKind.ColonColon)
}

func callOrAnnotation(node: CjSyntaxNode): ?Highlight {
    match (node.kind) {
        case SyntaxKind.Annotation => tagged(HighlightTag.BuiltinAnnotation)
        case SyntaxKind.MacroExpandDecl | SyntaxKind.MacroExpandExpr => tagged(HighlightTag.MacroCall)
        case _ => None
    }
}
