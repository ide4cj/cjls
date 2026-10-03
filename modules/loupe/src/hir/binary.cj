package loupe.hir

import std.collection.*
import std.deriving.*
import calca.*
import calca.macros.*
import cjo.{AccessLevel, AccessModifier, Attribute, CjoException, DeclInfo, DeclKind, FbVector, ImportSpec, PackageKind,
    openCjo}
import cjo.Decl as CjoDecl
import cjo.Package as CjoPackage
import loupe.db.{AnalysisDatabase, BinaryPackageFile, SourceFile}

/**
 * An item of a binary package: the index of its file among the package's `allFiles`, and its id in
 * that file's tree.
 */
@Derive[Equatable, Hashable]
public struct BinaryItemRef <: ToString {
    public BinaryItemRef(public let file: Int64, public let id: ItemId) {}

    public func toString(): String {
        "${file}:${id}"
    }
}

/**
 * The items of a binary package by their export ids (`_CNat6StringE`): what a `FullId` of another
 * package names.
 */
public class BinaryExports <: Equatable<BinaryExports> {
    BinaryExports(private let byExportId: HashMap<String, BinaryItemRef>) {}

    public prop size: Int64 {
        get() {
            byExportId.size
        }
    }

    /**
     * The item `exportId` names, `None` if none of the package's does.
     */
    public func get(exportId: String): ?BinaryItemRef {
        byExportId.get(exportId)
    }

    public operator func ==(other: BinaryExports): Bool {
        sameEntries(byExportId, other.byExportId)
    }

    public operator func !=(other: BinaryExports): Bool {
        !(this == other)
    }
}

/**
 * Where a definition is: a source file, or a file of a binary package by its index. Resolution
 * reads its tree, and never knows where the package came from.
 */
public enum ItemFile <: Equatable<ItemFile> & Hashable {
    | Source(SourceFile)
    | Binary(BinaryPackageFile, Int64)

    public operator func ==(other: ItemFile): Bool {
        match ((this, other)) {
            case (Source(a), Source(b)) => a == b
            case (Binary(a, i), Binary(b, j)) => a == b && i == j
            case _ => false
        }
    }

    public operator func !=(other: ItemFile): Bool {
        !(this == other)
    }

    public func hashCode(): Int64 {
        var hasher = DefaultHasher()
        match (this) {
            case Source(file) =>
                hasher.write(0)
                hasher.write(file.hashCode())
            case Binary(pkg, index) =>
                hasher.write(1)
                hasher.write(pkg.hashCode())
                hasher.write(index)
        }
        hasher.finish()
    }
}

/**
 * The tree of `file`: a source file's, or that of a file of a binary package, empty for an index
 * the package has no file at.
 */
public func itemTreeOf(db: AnalysisDatabase, file: ItemFile): ItemTree {
    match (file) {
        case ItemFile.Source(source) => itemTree(db, source)
        case ItemFile.Binary(pkg, index) =>
            let trees = binaryItemTrees(db, pkg)
            if (index >= 0 && index < trees.size) {
                trees[index]
            } else {
                ItemTree(None, [], [])
            }
    }
}

/**
 * A tree per file of the package, in the order of its `allFiles`: its declarations grouped by the
 * file they begin in, a declaration of no file of the package with the first. Its imports are the
 * file's re-exports alone, what an importer sees of them. What cjc added is left out, but for a
 * primary constructor and the fields it declares. None for a package that cannot be read: its names
 * do not resolve.
 */
@CalcaTracked
public func binaryItemTrees(db: AnalysisDatabase, pkg: BinaryPackageFile): Array<ItemTree> {
    binaryItems(db, pkg).trees
}

/**
 * The items of the package by their export ids.
 */
@CalcaTracked
public func binaryExports(db: AnalysisDatabase, pkg: BinaryPackageFile): BinaryExports {
    binaryItems(db, pkg).exports
}

/**
 * The declaration of the item `ref`, read from the package's bytes, `None` if the package has no
 * such item.
 */
public func binaryDecl(db: AnalysisDatabase, pkg: BinaryPackageFile, ref: BinaryItemRef): ?CjoDecl {
    let index = binaryItems(db, pkg).decls.get(ref) ?? return None
    try {
        openCjo(pkg.bytes(db)).allDecls[index]
    } catch (_: CjoException) {
        None
    }
}

/**
 * The trees of a binary package, its exports, and the index in `allDecls` of each item.
 */
class BinaryItems <: Equatable<BinaryItems> {
    BinaryItems(
        let trees: Array<ItemTree>,
        let exports: BinaryExports,
        let decls: HashMap<BinaryItemRef, Int64>
    ) {}

    public operator func ==(other: BinaryItems): Bool {
        trees == other.trees && exports == other.exports && sameEntries(decls, other.decls)
    }

    public operator func !=(other: BinaryItems): Bool {
        !(this == other)
    }
}

@CalcaTracked
func binaryItems(db: AnalysisDatabase, pkg: BinaryPackageFile): BinaryItems {
    lowerBinary(pkg.bytes(db))
}

/**
 * The items `bytes` hold, none if they are no `.cjo` this reads, or a broken one.
 */
func lowerBinary(bytes: Array<Byte>): BinaryItems {
    try {
        BinaryLowering(openCjo(bytes)).lower()
    } catch (_: CjoException) {
        BinaryItems([], BinaryExports(HashMap()), HashMap())
    } catch (_: IndexOutOfBoundsException) {
        BinaryItems([], BinaryExports(HashMap()), HashMap())
    }
}

/**
 * One package lowered into trees: the ids given so far in each file, as `ItemIdBuilder` gives them
 * in a source file (D34).
 */
class BinaryLowering {
    private let decls: FbVector<CjoDecl>
    private let fileCount: Int64
    private let seen: Array<HashMap<ItemId, Int64>>
    private let exports = HashMap<String, BinaryItemRef>()
    private let indices = HashMap<BinaryItemRef, Int64>()

    BinaryLowering(private let pkg: CjoPackage) {
        decls = pkg.allDecls
        fileCount = max(pkg.allFiles.size, 1)
        seen = Array<HashMap<ItemId, Int64>>(fileCount) {_ => HashMap<ItemId, Int64>()}
    }

    func lower(): BinaryItems {
        let header = PackageItem(pkg.fullPkgName ?? "", pkg.kind == PackageKind.Macro, [accessModifier(pkg.access)])
        let fileImports = pkg.allFileImports
        let imports = Array<Array<ImportItem>>(fileCount) {
            file => if (file < fileImports.size) {
                reExports(file, fileImports[file].importSpecs)
            } else {
                []
            }
        }
        let items = Array<ArrayList<Item>>(fileCount) {_ => ArrayList<Item>()}
        for (index in 0..decls.size) {
            let decl = decls[index]
            if (decl.isTopLevel) {
                let file = fileOf(decl)
                if (let Some(item) <- lowerDecl(decl, index, file, None, "")) {
                    items[file].add(item)
                }
            }
        }
        let trees = Array<ItemTree>(fileCount) {file => ItemTree(header, imports[file], items[file].toArray())}
        BinaryItems(trees, BinaryExports(exports), indices)
    }

    /**
     * The file a top-level declaration begins in: the first for one of no file of the package.
     */
    private func fileOf(decl: CjoDecl): Int64 {
        match (decl.begin) {
            case Some(begin) where begin.pkgId == 0 && begin.file >= 1 && Int64(begin.file) <= fileCount =>
                Int64(begin.file) - 1
            case _ => 0
        }
    }

    private func reExports(file: Int64, specs: FbVector<ImportSpec>): Array<ImportItem> {
        let imports = ArrayList<ImportItem>()
        for (spec in specs where spec.reExport != AccessModifier.Private) {
            let segments = ArrayList<String>(spec.prefixPaths.toArray())
            if (spec.hasDoubleColon && segments.size >= 2) {
                // `org::a.b`: the organization is one segment with the package's first name
                let org = segments[0]
                segments.remove(at: 0)
                segments[0] = "${org}::${segments[0]}"
            }
            let identifier = spec.identifier ?? ""
            let isGlob = identifier == "*"
            if (!isGlob) {
                segments.add(identifier)
            }
            let alias = spec.asIdentifier.flatMap {it => if (it.isEmpty()) {
                None
            } else {
                it
            }}
            let written = String.join(segments.toArray(), delimiter: ".") + if (isGlob) {
                ".*"
            } else {
                ""
            } + (alias.map {it => "as${it}"} ?? "")
            let id = add(file, None, ItemKind.Import, written)
            imports.add(ImportItem(id, [reExportModifier(spec.reExport)],
                [ImportPath(segments.toArray(), alias: alias, isGlob: isGlob)]))
        }
        imports.toArray()
    }

    /**
     * The item of `decl`, at `index` in `allDecls`, `None` for what no item is: a parameter, a
     * generic parameter, what cjc added.
     */
    private func lowerDecl(decl: CjoDecl, index: Int64, file: Int64, parent: ?ItemId, parentName: String): ?Item {
        let kind = binaryKindOf(decl) ?? return None
        let attributes = decl.attributes
        if (attributes.has(Attribute.CompilerAdd) && kind != ItemKind.PrimaryInit && (parent.isNone() ||
            kind != ItemKind.Var)) {
            return None
        }
        let identifier = decl.identifier ?? ""
        let (names, idName) = match (kind) {
            case ItemKind.Extend => (Array<String>(), decl.exportId ?? "")
            // named after its type, as in a source file
            case ItemKind.PrimaryInit => ([parentName], parentName)
            case _ where identifier.isEmpty() => (Array<String>(), "")
            case _ => ([identifier], identifier)
        }
        let id = add(file, parent, kind, idName)
        let ref = BinaryItemRef(file, id)
        indices.add(ref, index)
        if (let Some(exportId) <- decl.exportId) {
            if (!exportId.isEmpty()) {
                exports.add(exportId, ref)
            }
        }
        let members = ArrayList<Item>()
        for (member in bodyOf(decl)) {
            let at = Int64(member) - 1
            if (at >= 0 && at < decls.size) {
                if (let Some(item) <- lowerDecl(decls[at], at, file, id, identifier)) {
                    members.add(item)
                }
            }
        }
        Some(Item(id, names, modifiersOfBinary(decl), [], members.toArray()))
    }

    private func add(file: Int64, parent: ?ItemId, kind: ItemKind, name: String): ItemId {
        let first = ItemId(kind, pathHash(parent, name), 0)
        let index = seen[file].get(first) ?? 0
        seen[file].add(first, index + 1)
        ItemId(kind, first.hash, index)
    }
}

/**
 * What the declaration is as an item, `None` for what is none: a parameter, a generic parameter, a
 * kind this reader does not know.
 */
func binaryKindOf(decl: CjoDecl): ?ItemKind {
    let attributes = decl.attributes
    match (decl.kind) {
        case DeclKind.ClassDecl => ItemKind.Class
        case DeclKind.InterfaceDecl => ItemKind.Interface
        case DeclKind.StructDecl => ItemKind.Struct
        case DeclKind.EnumDecl => ItemKind.Enum
        case DeclKind.ExtendDecl => ItemKind.Extend
        case DeclKind.TypeAliasDecl => ItemKind.TypeAlias
        case DeclKind.PropDecl => ItemKind.Prop
        case DeclKind.BuiltInDecl => ItemKind.BuiltIn
        case DeclKind.VarDecl | DeclKind.VarWithPatternDecl => if (attributes.has(Attribute.EnumConstructor)) {
            ItemKind.EnumCtor
        } else {
            ItemKind.Var
        }
        case DeclKind.FuncDecl => if (attributes.has(Attribute.EnumConstructor)) {
            ItemKind.EnumCtor
        } else if (attributes.has(Attribute.PrimaryConstructor)) {
            ItemKind.PrimaryInit
        } else if (attributes.has(Attribute.Constructor)) {
            ItemKind.Init
        } else if (attributes.has(Attribute.Finalizer)) {
            ItemKind.Finalizer
        } else if (attributes.has(Attribute.MacroFunc)) {
            ItemKind.Macro
        } else if (attributes.has(Attribute.MainEntry)) {
            ItemKind.Main
        } else {
            ItemKind.Func
        }
        case _ => None
    }
}

/**
 * The members of a type, by their indices in `allDecls`, counted from 1.
 */
func bodyOf(decl: CjoDecl): Array<UInt32> {
    match (decl.info) {
        case Some(DeclInfo.AsClassInfo(info)) => info.body.toArray()
        case Some(DeclInfo.AsInterfaceInfo(info)) => info.body.toArray()
        case Some(DeclInfo.AsStructInfo(info)) => info.body.toArray()
        case Some(DeclInfo.AsEnumInfo(info)) => info.body.toArray()
        case Some(DeclInfo.AsExtendInfo(info)) => info.body.toArray()
        case _ => []
    }
}

/**
 * The modifiers the declaration's attributes say, in the order of `MODIFIERS`; `const` from its
 * info.
 */
func modifiersOfBinary(decl: CjoDecl): Array<Modifier> {
    let attributes = decl.attributes
    let isConst = match (decl.info) {
        case Some(DeclInfo.AsVarInfo(info)) => info.isConst
        case Some(DeclInfo.AsVarWithPatternInfo(info)) => info.isConst
        case Some(DeclInfo.AsFuncInfo(info)) => info.isConst
        case Some(DeclInfo.AsPropInfo(info)) => info.isConst
        case _ => false
    }
    MODIFIERS.map {modifier => modifier[1]}.filter {
        modifier => match (attributeOf(modifier)) {
            case Some(attribute) => attributes.has(attribute)
            case None => modifier == Modifier.Const && isConst
        }
    }
}

/**
 * The attribute cjc marks a declaration with for `modifier`, `None` for `const`, which it keeps in
 * the info.
 */
func attributeOf(modifier: Modifier): ?Attribute {
    match (modifier) {
        case Modifier.Static => Attribute.Static
        case Modifier.Public => Attribute.Public
        case Modifier.Private => Attribute.Private
        case Modifier.Internal => Attribute.Internal
        case Modifier.Protected => Attribute.Protected
        case Modifier.Override => Attribute.Override
        case Modifier.Redef => Attribute.Redef
        case Modifier.Abstract => Attribute.Abstract
        case Modifier.Sealed => Attribute.Sealed
        case Modifier.Open => Attribute.Open
        case Modifier.Foreign => Attribute.Foreign
        case Modifier.Mut => Attribute.Mut
        case Modifier.Unsafe => Attribute.Unsafe
        case Modifier.Operator => Attribute.Operator
        case Modifier.Common => Attribute.Common
        case Modifier.Specific => Attribute.Specific
        case Modifier.Const => None
    }
}

func accessModifier(access: AccessLevel): Modifier {
    match (access) {
        case AccessLevel.Public => Modifier.Public
        case AccessLevel.Protected => Modifier.Protected
        case AccessLevel.Internal => Modifier.Internal
    }
}

func reExportModifier(access: AccessModifier): Modifier {
    match (access) {
        case AccessModifier.Public => Modifier.Public
        case AccessModifier.Protected => Modifier.Protected
        case AccessModifier.Internal => Modifier.Internal
        case AccessModifier.Private => Modifier.Private
    }
}

/**
 * Whether the two maps hold the same entries.
 */
func sameEntries<K, V>(a: HashMap<K, V>, b: HashMap<K, V>): Bool where K <: Hashable & Equatable<K>, V <: Equatable<V> {
    a.size == b.size && a.iterator().all {entry => b.get(entry[0]) == Some(entry[1])}
}
