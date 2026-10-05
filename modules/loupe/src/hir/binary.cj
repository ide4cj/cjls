package loupe.hir

import std.collection.*
import std.deriving.*
import calca.*
import calca.macros.*
import cjo.{AccessLevel, AccessModifier, Attribute, Attributes, DeclInfo, DeclKind, FbVector, openCjo, PackageKind, Position}
import cjo.Decl as CjoDecl
import cjo.Package as CjoPackage
import loupe.db.{AnalysisDatabase, BinaryPackageFile, SourceFile}

/**
 * Where an item is declared: a source file, or a file of a package compiled already, by its index
 * among the package's files. Name resolution takes either alike.
 */
@Derive[Equatable, Hashable]
public enum ItemFile {
    | Source(SourceFile)
    | Binary(BinaryPackageFile, Int64)
}

/**
 * The item tree of `file`; an empty one for a file a package compiled already does not have.
 */
public func itemTreeOf(db: AnalysisDatabase, file: ItemFile): ItemTree {
    match (file) {
        case Source(source) => itemTree(db, source)
        case Binary(pkg, index) =>
            let trees = binaryItemTrees(db, pkg)
            if (index >= 0 && index < trees.size) {
                trees[index]
            } else {
                ItemTree(None, [], [])
            }
    }
}

/**
 * The item trees of a package compiled already, one per file of its `.cjo` (`allFiles`), in their
 * order: each declaration in the file it began in, with ids made as a source file's are (D34). None
 * for a package that cannot be read: its names do not resolve, and nothing fails.
 */
@CalcaTracked
public func binaryItemTrees(db: AnalysisDatabase, pkg: BinaryPackageFile): Array<ItemTree> {
    binaryLowering(db, pkg).trees
}

/**
 * Where each item of a package compiled already is, and how to find it from another package.
 */
@CalcaTracked
public func binaryExports(db: AnalysisDatabase, pkg: BinaryPackageFile): BinaryExports {
    binaryLowering(db, pkg).exports
}

/**
 * The package `pkg` holds in the item model, lowered once for both halves: each is a query of its
 * own, so that what reads one is not run again when only the other changed. It holds what they
 * hold, nothing more.
 */
@CalcaTracked
func binaryLowering(db: AnalysisDatabase, pkg: BinaryPackageFile): BinaryLowering {
    lowerBinary(pkg.bytes(db))
}

/**
 * The declaration of `item` in the `.cjo` of `pkg`, read when it is asked for; `None` if the package
 * has no such item, or cannot be read.
 */
public func binaryDecl(db: AnalysisDatabase, pkg: BinaryPackageFile, item: BinaryItem): ?CjoDecl {
    let index = binaryExports(db, pkg).declIndex(item) ?? return None
    let bytes = pkg.bytes(db)
    try {
        openCjo(bytes).allDecls[index]
    } catch (_: Exception) {
        None
    }
}

/**
 * An item of a package compiled already: the index of its file, and its id there.
 */
@Derive[Equatable, Hashable]
public struct BinaryItem <: ToString {
    public BinaryItem(public let file: Int64, public let id: ItemId) {}

    public func toString(): String {
        "${file}:${id}"
    }
}

/**
 * The items of a package compiled already: an `exportId` (`_CNat6StringE`), which names a
 * declaration in the types of another package, to its item; an item to the index of its
 * declaration in `allDecls`, so that it leads back to it. An `exportId` is unique in its package:
 * it is the symbol the declaration is linked by (a test holds std to it).
 */
public class BinaryExports <: Equatable<BinaryExports> {
    private let byExport = HashMap<String, BinaryItem>()
    private let byItem = HashMap<BinaryItem, Int64>()

    /**
     * Each item, the index of its declaration and its `exportId` (empty for none), in the order
     * they were lowered in.
     */
    BinaryExports(private let items: Array<BinaryItem>, private let decls: Array<Int64>,
        private let exportIds: Array<String>) {
        for (i in 0..items.size) {
            byItem.add(items[i], decls[i])
            if (!exportIds[i].isEmpty()) {
                byExport.add(exportIds[i], items[i])
            }
        }
    }

    /**
     * The item `exportId` names, `None` if the package has none so named.
     */
    public func itemOf(exportId: String): ?BinaryItem {
        byExport.get(exportId)
    }

    /**
     * The index of the declaration of `item` in `allDecls`, `None` if the package has no such item.
     */
    public func declIndex(item: BinaryItem): ?Int64 {
        byItem.get(item)
    }

    public operator func ==(other: BinaryExports): Bool {
        items == other.items && decls == other.decls && exportIds == other.exportIds
    }

    public operator func !=(other: BinaryExports): Bool {
        !(this == other)
    }
}

/**
 * A package compiled already in the item model.
 */
@Derive[Equatable]
struct BinaryLowering {
    BinaryLowering(let trees: Array<ItemTree>, let exports: BinaryExports) {}
}

/**
 * The package `bytes` hold in the item model; nothing for bytes that are no `.cjo` this reader
 * knows, or that break where they are read (D37).
 */
func lowerBinary(bytes: Array<Byte>): BinaryLowering {
    try {
        BinaryLowerer(openCjo(bytes)).lower()
    } catch (_: Exception) {
        BinaryLowering([], BinaryExports([], [], []))
    }
}

/**
 * One package being lowered: its items so far, per file, and an id counter per file.
 */
class BinaryLowerer {
    private let decls: FbVector<CjoDecl>
    private let fileCount: Int64
    /**
     * The `pkgId` of a position that names this package through its imports, `None` if none does.
     */
    private let selfId: ?UInt32
    private let counters: Array<ItemIdCounter>
    private let items: Array<ArrayList<Item>>
    /**
     * Whether the declaration at each index was lowered already: a `body` names each once, and
     * never a parent of its own, but in a broken file.
     */
    private let seen: Array<Bool>
    private let lowered = ArrayList<BinaryItem>()
    private let declIndices = ArrayList<Int64>()
    private let exportIds = ArrayList<String>()

    BinaryLowerer(private let pkg: CjoPackage) {
        decls = pkg.allDecls
        seen = Array(decls.size, repeat: false)
        // a package of no file still has its declarations somewhere
        fileCount = max(pkg.allFiles.size, 1)
        let name = pkg.fullPkgName ?? ""
        let imports = pkg.imports.toArray()
        selfId = imports.iterator().enumerate().filter {it => it[1] == name}.next().map {it => UInt32(it[0] + 1)}
        counters = Array(fileCount) {_ => ItemIdCounter()}
        items = Array(fileCount) {_ => ArrayList<Item>()}
    }

    func lower(): BinaryLowering {
        let header = PackageItem(pkg.fullPkgName ?? "", pkg.kind == PackageKind.Macro, [accessOf(pkg.access)])
        // imports first, as a source file's are
        let imports = Array(fileCount) {file => importsOf(file)}
        for (i in 0..decls.size) {
            let decl = decls[i]
            if (decl.isTopLevel) {
                let file = fileOf(decl.begin)
                if (let Some(item) <- lowerDecl(None, "", i, file)) {
                    items[file].add(item)
                }
            }
        }
        let trees = Array(fileCount) {file => ItemTree(header, imports[file], items[file].toArray())}
        BinaryLowering(trees, BinaryExports(lowered.toArray(), declIndices.toArray(), exportIds.toArray()))
    }

    /**
     * The item of the declaration at `index`, under `parent` (named `parentName`) in `file`;
     * `None` for one that is no item (a parameter, a generic parameter, one of a kind this reader
     * does not know) and for one cjc added, but those a primary init desugars to: cjc keeps no
     * `PrimaryCtorDecl`, only the `init` it makes of it (`PrimaryConstructor`) and a field per member
     * parameter (`isMemberParam`), both `CompilerAdd` (`DesugarPrimaryCtor`).
     */
    private func lowerDecl(parent: ?ItemId, parentName: String, index: Int64, file: Int64): ?Item {
        // a member out of `allDecls`, or one lowered already, is a broken file's: that one alone is left out
        if (index < 0 || index >= decls.size || seen[index]) {
            return None
        }
        seen[index] = true
        let decl = decls[index]
        let attributes = decl.attributes
        let info = decl.info
        let memberParam = match (info) {
            case Some(DeclInfo.AsVarInfo(var_)) => var_.isMemberParam
            case _ => false
        }
        if (attributes.has(Attribute.CompilerAdd) && !attributes.has(Attribute.PrimaryConstructor) && !memberParam) {
            return None
        }
        let kind = kindOf(decl.kind, attributes) ?? return None
        let identifier = decl.identifier ?? ""
        let names: Array<String> = match (kind) {
            case ItemKind.Extend => []
            case ItemKind.Main => ["main"]
            case ItemKind.Init => ["init"]
            case ItemKind.Finalizer => ["~init"]
            // cjc names it `init`, its `identifierForLsp` as its type, as a source names it
            case ItemKind.PrimaryInit => [parentName]
            case _ where identifier.isEmpty() => []
            case _ => [identifier]
        }
        let exportId = decl.exportId ?? ""
        // an extend, or a `let` of a pattern, keeps no name as text: its exportId tells it apart
        let id = counters[file].next(parent, kind, names.get(0) ?? exportId)
        lowered.add(BinaryItem(file, id))
        declIndices.add(index)
        exportIds.add(exportId)
        let members = ArrayList<Item>()
        for (member in bodyOf(info)) {
            if (let Some(item) <- lowerDecl(id, identifier, Int64(member) - 1, file)) {
                members.add(item)
            }
        }
        Item(id, names, modifiersOf(attributes, info), [], members.toArray())
    }

    /**
     * The index of the file `begin` is in: one of this package's, counted from 1 when it says
     * none (`pkgId` 0), from 0 when it names this package through its imports; 0 for any other.
     */
    private func fileOf(begin: ?Position): Int64 {
        let position = begin ?? return 0
        let file = Int64(position.file)
        let index = if (position.pkgId == 0) {
            file - 1
        } else if (Some(position.pkgId) == selfId) {
            file
        } else {
            0
        }
        if (index >= 0 && index < fileCount) {
            index
        } else {
            0
        }
    }

    /**
     * What `file` re-exports (`public import`), each name an import of its own: what a package
     * compiled already only imports is resolved in its types already.
     */
    private func importsOf(file: Int64): Array<ImportItem> {
        let all = pkg.allFileImports
        if (file >= all.size) {
            return []
        }
        let imports = ArrayList<ImportItem>()
        for (spec in all[file].importSpecs) {
            let modifier = match (spec.reExport) {
                case AccessModifier.Public => Modifier.Public
                case AccessModifier.Protected => Modifier.Protected
                case AccessModifier.Internal => Modifier.Internal
                case AccessModifier.Private => continue
            }
            let identifier = spec.identifier ?? ""
            // cjc writes one for every import it keeps
            if (identifier.isEmpty()) {
                continue
            }
            let isGlob = identifier == "*"
            let segments = importSegments(spec.prefixPaths.toArray(), identifier, spec.hasDoubleColon)
            let alias = spec.asIdentifier.flatMap {it => if (it.isEmpty()) {
                None<String>
            } else {
                it
            }}
            let text = String.join(segments, delimiter: ".") + (if (isGlob) {
                ".*"
            } else {
                ""
            }) + (alias.map {it => " as ${it}"} ?? "")
            let id = counters[file].next(None, ItemKind.Import, text)
            imports.add(ImportItem(id, [modifier], [ImportPath(segments, alias: alias, isGlob: isGlob)]))
        }
        imports.toArray()
    }
}

/**
 * The segments of an import as a source's `ImportPath` has them, from what cjc keeps of it: the
 * names before the last (`prefixPaths`), the last (`identifier`, `*` for a glob, no segment), and
 * whether the first is an organization (`hasDoubleColon`), one segment with the name after it:
 * `org::a`, `org::a.B` and `org::a.*` all begin with `org::a`.
 */
func importSegments(prefix: Array<String>, identifier: String, hasDoubleColon: Bool): Array<String> {
    let written = if (identifier == "*") {
        prefix
    } else {
        prefix.concat([identifier])
    }
    if (hasDoubleColon && written.size >= 2) {
        ["${written[0]}::${written[1]}"].concat(written[2..])
    } else {
        written
    }
}

/**
 * What a declaration of `kind` with `attributes` is as an item, `None` if it is none.
 */
private func kindOf(kind: DeclKind, attributes: Attributes): ?ItemKind {
    match (kind) {
        case DeclKind.ClassDecl => ItemKind.Class
        case DeclKind.InterfaceDecl => ItemKind.Interface
        case DeclKind.StructDecl => ItemKind.Struct
        case DeclKind.EnumDecl => ItemKind.Enum
        case DeclKind.ExtendDecl => ItemKind.Extend
        case DeclKind.TypeAliasDecl => ItemKind.TypeAlias
        case DeclKind.BuiltInDecl => ItemKind.BuiltIn
        case DeclKind.PropDecl => ItemKind.Prop
        case DeclKind.VarWithPatternDecl => ItemKind.Var
        case DeclKind.VarDecl where attributes.has(Attribute.EnumConstructor) => ItemKind.EnumCtor
        case DeclKind.VarDecl => ItemKind.Var
        case DeclKind.FuncDecl where attributes.has(Attribute.EnumConstructor) => ItemKind.EnumCtor
        case DeclKind.FuncDecl where attributes.has(Attribute.PrimaryConstructor) => ItemKind.PrimaryInit
        case DeclKind.FuncDecl where attributes.has(Attribute.Finalizer) => ItemKind.Finalizer
        case DeclKind.FuncDecl where attributes.has(Attribute.Constructor) => ItemKind.Init
        case DeclKind.FuncDecl where attributes.has(Attribute.MacroFunc) => ItemKind.Macro
        case DeclKind.FuncDecl where attributes.has(Attribute.MainEntry) => ItemKind.Main
        case DeclKind.FuncDecl => ItemKind.Func
        // a parameter, a generic parameter, an invalid one, one a newer format added
        case _ => None
    }
}

/**
 * The members of a type: its body's declarations, by their index in `allDecls` counted from 1.
 */
private func bodyOf(info: ?DeclInfo): Array<UInt32> {
    match (info) {
        case Some(DeclInfo.AsClassInfo(it)) => it.body.toArray()
        case Some(DeclInfo.AsInterfaceInfo(it)) => it.body.toArray()
        case Some(DeclInfo.AsStructInfo(it)) => it.body.toArray()
        case Some(DeclInfo.AsEnumInfo(it)) => it.body.toArray()
        case Some(DeclInfo.AsExtendInfo(it)) => it.body.toArray()
        case _ => []
    }
}

/**
 * The modifiers of a declaration, as cjc stored them, defaults included (a member of an
 * interface is `public`), in the order of `MODIFIERS`.
 */
private func modifiersOf(attributes: Attributes, info: ?DeclInfo): Array<Modifier> {
    let isConst = match (info) {
        case Some(DeclInfo.AsVarInfo(it)) => it.isConst
        case Some(DeclInfo.AsVarWithPatternInfo(it)) => it.isConst
        case Some(DeclInfo.AsFuncInfo(it)) => it.isConst
        case Some(DeclInfo.AsPropInfo(it)) => it.isConst
        case _ => false
    }
    MODIFIERS.map {it => it[1]}.filter {
        modifier => match (modifier) {
            case Modifier.Static => attributes.has(Attribute.Static)
            case Modifier.Public => attributes.has(Attribute.Public)
            case Modifier.Private => attributes.has(Attribute.Private)
            case Modifier.Internal => attributes.has(Attribute.Internal)
            case Modifier.Protected => attributes.has(Attribute.Protected)
            case Modifier.Override => attributes.has(Attribute.Override)
            case Modifier.Redef => attributes.has(Attribute.Redef)
            case Modifier.Abstract => attributes.has(Attribute.Abstract)
            case Modifier.Sealed => attributes.has(Attribute.Sealed)
            case Modifier.Open => attributes.has(Attribute.Open)
            case Modifier.Foreign => attributes.has(Attribute.Foreign)
            case Modifier.Mut => attributes.has(Attribute.Mut)
            case Modifier.Unsafe => attributes.has(Attribute.Unsafe)
            case Modifier.Operator => attributes.has(Attribute.Operator)
            case Modifier.Const => isConst
            case Modifier.Common => attributes.has(Attribute.Common)
            case Modifier.Specific => attributes.has(Attribute.Specific)
        }
    }
}

/**
 * The modifier of a package's access level.
 */
private func accessOf(access: AccessLevel): Modifier {
    match (access) {
        case AccessLevel.Public => Modifier.Public
        case AccessLevel.Protected => Modifier.Protected
        case AccessLevel.Internal => Modifier.Internal
    }
}
