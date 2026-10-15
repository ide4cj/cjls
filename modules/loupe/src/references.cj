package loupe

import std.collection.*
import std.deriving.*
import rope.Rope
import cjsyntax.{CjSyntaxNode, CjSyntaxToken}
import cjsyntax.ast.{ImportAlias, Name, identText, isIdent}
import loupe.db.{AnalysisDatabase, Package, SourceFile}
import loupe.hir.{DefId, Item, ItemFile, ItemKind, PackageRef, Visibility, itemTreeOf, packageIndex, packageOfFile, parentOf, relationOf,
    scopeFileOf, visibilityOf}
import loupe.syntax.parse
import loupe.vfs.FileId

/**
 * A name of the workspace meaning what the one asked about does: where it is, how it reaches it, as
 * `RelatedHighlight` has it, and whether it is the name a declaration gives.
 */
@Derive[Equatable]
public struct Reference {
    public Reference(public let fileId: FileId, public let range: TextRange, public let access: ?ReferenceAccess,
        public let isDeclaration: Bool) {}
}

/**
 * Every name of the workspace meaning what the name at `offset` does, the declarations among them, by file as
 * `searchScope` has them and in each in the file's order: `highlightRelated` in the files a use may be in
 * (`searchScope`) whose text names it, rust-analyzer's `FindUsages`, no index of uses kept. Nothing for a name
 * meaning nothing, nor for a name a macro declares (#175).
 */
public func findReferences(db: AnalysisDatabase, fileId: FileId, offset: Int64): Array<Reference> {
    let file = db.sourceFile(fileId) ?? return []
    let token = tokenAt(parse(db, file).syntaxNode(), offset) ?? return []
    if (!isIdent(token)) {
        return []
    }
    let meant = meaningsAt(db, file, token)
    if (meant.isEmpty()) {
        return []
    }
    let names = searchedNames(db, identText(token), meant)
    searchScope(db, meant, file) |> filter {
        one: SourceFile => let text = one.text(db)
        names.iterator().any {name => mentions(text, name)}
    } |> flatMap {
        one: SourceFile =>
        let id = one.fileId(db)
        let root = parse(db, one).syntaxNode()
        namesMeaning(db, one, root, names.concat(aliasesIn(db, one, root, names, meant)), meant).map {
            found: CjSyntaxToken => Reference(id, found.textRange, accessOf(found), declares(found))
        }
    } |> collectArray
}

/**
 * Whether the name `token` is the one a declaration gives, a local's included; an import's alias is a use.
 */
func declares(token: CjSyntaxToken): Bool {
    Name.canCast(token.parent.kind) && !(token.parent.parent.map {node => ImportAlias.canCast(node.kind)} ?? false)
}

/**
 * The names a name meaning `meant` is spelled as, `spelled` the one asked about: that, and the name of each
 * declaration meant, asked about through an import's alias. Not those of a declaration of several names, a `let` of
 * a pattern, as each of them would mean it.
 */
func searchedNames(db: AnalysisDatabase, spelled: String, meant: Array<Definition>): Array<String> {
    let names = ArrayList<String>([spelled])
    for (definition in meant) {
        if (let DeclDef(id) <- definition && let Some(item) <- itemIn(db, id) && item.names.size == 1 &&
            !names.contains(item.names[0])) {
            names.add(item.names[0])
        }
    }
    names.toArray()
}

/**
 * The aliases the imports of `file`, whose tree is `root`, give a declaration of `meant` other than `names`: `bar`
 * of `import a.foo as bar`, which its uses in the file are spelled as.
 */
func aliasesIn(db: AnalysisDatabase, file: SourceFile, root: CjSyntaxNode, names: Array<String>,
    meant: Array<Definition>): Array<String> {
    root.descendants() |> filterMap {
        node: CjSyntaxNode => ImportAlias.cast(node).flatMap {alias => alias.name()}.flatMap {name => name.identToken()}
    } |> filter {
        alias: CjSyntaxToken => !names.contains(identText(alias)) &&
            meaningsAt(db, file, alias).any {definition: Definition => meant.contains(definition)}
    } |> map {alias: CjSyntaxToken => identText(alias)} |> collectArray
}

/**
 * The files a name meaning any of `meant`, asked about in `from`, may be in, rust-analyzer's
 * `Definition::search_scope` in Cangjie's terms: a local's file, a type parameter's, but every file for a parameter of
 * a primary constructor, which may be a member; a `private` declaration's file,
 * a member's as a top-level one's (cjc sees neither in another file); a member of any other visibility, every file of
 * the project, as a value of its type goes anywhere; any other declaration, the files of the packages that see it
 * (`isSeen`) in the modules that may import its (`PackageIndex.scopes`). `from` among them in any case, then the
 * project's order.
 */
func searchScope(db: AnalysisDatabase, meant: Array<Definition>, from: SourceFile): Array<SourceFile> {
    let packages = ArrayList<(Package, String)>()
    if (let Some(project) <- db.project()) {
        for (module in project.modules(db)) {
            for (pkg in module.packages(db)) {
                packages.add((pkg, module.name(db)))
            }
        }
    }
    let scope = FileScope(db)
    scope.add(from)
    for (definition in meant) {
        match (definition) {
            // a parameter of a primary constructor may be a member, named through a value anywhere
            case LocalDef(def, _) where def.item(db).kind == ItemKind.PrimaryInit => for ((pkg, _) in packages) {
                scope.addPackage(pkg)
            }
            case LocalDef(def, _) => scope.add(scopeFileOf(db, def.file(db)))
            case DeclDef(id) => declScope(db, id, packages, scope)
            // `meaningsAt` has a member parameter as the local it is
            case MemberParamDef(_, _) | TypeParamDef(_) | PackageDef(_) => ()
        }
    }
    scope.files.toArray()
}

/**
 * Adds to `scope` the files a use of the declaration `id` may be in (`searchScope`), `packages` those of the project
 * with the names of their modules.
 */
func declScope(db: AnalysisDatabase, id: DefId, packages: ArrayList<(Package, String)>, scope: FileScope): Unit {
    let item = itemIn(db, id) ?? return ()
    let visibility = visibilityOf(item)
    let file = scopeFileOf(db, id.file(db))
    if (visibility == Visibility.Private) {
        scope.add(file)
        return
    }
    if (parentOf(db, id).isSome()) {
        for ((pkg, _) in packages) {
            scope.addPackage(pkg)
        }
        return
    }
    let (ref, declaring) = match (id.file(db)) {
        case ItemFile.Binary(pkg, _) => (PackageRef.Binary(pkg), pkg.name(db))
        case _ =>
            // a file of no package: its own names only
            let pkg = file.flatMap {one => packageOfFile(db, one)} ?? return scope.add(file)
            (PackageRef.Source(pkg), pkg.name(db))
    }
    let index = packageIndex(db)
    let owner = index.owners.get(ref) ?? return ()
    for ((pkg, module) in packages where (index.scopes.get(module)?.contains(owner) ?? false) &&
        visibility.isSeen(by: relationOf(pkg.name(db), declaring))) {
        scope.addPackage(pkg)
    }
}

/**
 * The item `id` stands for, a member as well, which `itemOf` does not look for.
 */
func itemIn(db: AnalysisDatabase, id: DefId): ?Item {
    findItem(itemTreeOf(db, id.file(db)).items, id.item(db))
}

/**
 * Files, each once, in the order they are added.
 */
class FileScope {
    let files = ArrayList<SourceFile>()
    private let seen = HashSet<FileId>()

    FileScope(private let db: AnalysisDatabase) {}

    func add(file: ?SourceFile): Unit {
        if (let Some(one) <- file && seen.add(one.fileId(db))) {
            files.add(one)
        }
    }

    func addPackage(pkg: Package): Unit {
        for (fileId in pkg.files(db)) {
            add(db.sourceFile(fileId))
        }
    }
}

/**
 * Whether `text` has `name` anywhere, a name across two of its chunks too: the files worth parsing for it, a
 * superset of those naming it (`size` is in `sizeOf`).
 */
func mentions(text: Rope, name: String): Bool {
    // the end of the chunk before, as much as a match across the two can start in
    var carry = ""
    for (chunk in text.chunks()) {
        if (chunk.contains(name)) {
            return true
        }
        if (!carry.isEmpty() && (carry + chunk[..boundaryAfter(chunk, name.size - 1)]).contains(name)) {
            return true
        }
        // a chunk but a lone one is longer than a name (the rope's `MIN_CHUNK`, 256 bytes)
        carry = chunk[boundaryAfter(chunk, chunk.size - name.size + 1)..]
    }
    false
}

/**
 * The first character boundary of `text` at `offset` or after it, `offset` kept within it.
 */
func boundaryAfter(text: String, offset: Int64): Int64 {
    var at = min(max(offset, 0), text.size)
    // a byte 0b10xxxxxx continues a character
    while (at < text.size && (text[at] & 0xC0) == 0x80) {
        at++
    }
    at
}
