package loupe.hir

import std.collection.*
import std.deriving.*
import calca.*
import calca.macros.*
import index_map.IndexMap
import loupe.db.{AnalysisDatabase, BinaryPackageFile, Package}

/**
 * A package of either kind, as name resolution takes it: one of the project's sources, or one
 * compiled already (D38). What resolves in it does not ask which.
 */
@Derive[Equatable, Hashable, ToString]
public enum PackageRef {
    | Source(Package)
    | Binary(BinaryPackageFile)
}

/**
 * The files of `pkg`, in its order: a source package's that have a text, each file of a `.cjo`.
 */
public func filesOf(db: AnalysisDatabase, pkg: PackageRef): Array<ItemFile> {
    match (pkg) {
        case Source(source) => source.files(db) |> filterMap {fileId => db.sourceFile(fileId)} |>
            map {file => ItemFile.Source(file)} |> collectArray
        case Binary(binary) => Array(binaryItemTrees(db, binary).size) {index => ItemFile.Binary(binary, index)}
    }
}

/**
 * An item across files: its file and its id there, interned, so that what is keyed by a
 * definition (its signature, its body) is keyed by one number.
 */
@CalcaInterned
public struct DefId {
    public let file: ItemFile
    public let item: ItemId
}

/**
 * Who sees a declaration (N1–N4): `private` its file, `internal` its package and those under it
 * by name, `protected` the packages of its first segment, `public` anyone.
 */
@Derive[Equatable]
public enum Visibility <: ToString {
    | Private
    | Internal
    | Protected
    | Public

    public func toString(): String {
        match (this) {
            case Private => "private"
            case Internal => "internal"
            case Protected => "protected"
            case Public => "public"
        }
    }
}

/**
 * The visibility `item` is written with; `internal` when none is, `public` for `sealed` (N87).
 */
public func visibilityOf(item: Item): Visibility {
    if (item.has(Modifier.Private)) {
        Visibility.Private
    } else if (item.has(Modifier.Protected)) {
        Visibility.Protected
    } else if (item.has(Modifier.Public) || item.has(Modifier.Sealed)) {
        Visibility.Public
    } else {
        Visibility.Internal
    }
}

/**
 * A declaration a name of a package's scope stands for, and who sees it.
 */
@Derive[Equatable]
public struct Def <: ToString {
    public Def(public let id: DefId, public let visibility: Visibility) {}

    public func toString(): String {
        "${visibility} ${id}"
    }
}

/**
 * A declaration whose name another of its package took first: anything but a function sharing a
 * name with any other declaration (N19, N20, N22).
 */
@Derive[Equatable]
public struct Redefinition <: ToString {
    public Redefinition(public let def: DefId, public let name: String) {}

    public func toString(): String {
        "redefinition of ${name} by ${def}"
    }
}

/**
 * What a package declares, all its files together (D44), and nothing it imports: the names of its
 * declarations, each a set (overloads, N21); under them those of its enums' constructors (N24); and
 * the redefinitions among them.
 */
@Derive[Equatable]
public struct DefMap {
    public DefMap(
        public let names: IndexMap<String, Array<Def>>,
        public let ctors: IndexMap<String, Array<Def>>,
        public let errors: Array<Redefinition>
    ) {}

    /**
     * What `name` stands for in the file `from` of this package, among the package's own
     * declarations: those it sees (N1, N23), else the constructors (N25), all of them for the use to
     * tell apart (N26). Empty if neither has it.
     */
    public func lookUp(db: AnalysisDatabase, name: String, from!: ItemFile): Array<DefId> {
        let seen = (names.get(name) ?? []).filter {def => def.visibility != Visibility.Private || def.id.file(db) == from}
        if (seen.isEmpty()) {
            (ctors.get(name) ?? []).map {def => def.id}
        } else {
            seen.map {def => def.id}
        }
    }
}

/**
 * The `DefMap` of the files of a package, each with its item tree, in the package's order. A name
 * gathers every declaration of it; one that is not a function, or that comes after one that is
 * not, redefines it.
 */
public func collectDefMap(db: AnalysisDatabase, files: Array<(ItemFile, ItemTree)>): DefMap {
    let names = IndexMap<String, ArrayList<(Def, ItemKind)>>()
    let ctors = IndexMap<String, ArrayList<Def>>()
    let errors = ArrayList<Redefinition>()
    for ((file, tree) in files) {
        for (item in tree.items) {
            let def = Def(DefId(db, file, item.id), visibilityOf(item))
            for (name in item.names) {
                let taken = entryOf(names, name)
                if (!taken.isEmpty() && (item.kind != ItemKind.Func || taken.iterator().any {t => t[1] != ItemKind.Func})) {
                    errors.add(Redefinition(def.id, name))
                }
                taken.add((def, item.kind))
            }
            // an enum's constructors are seen as the enum is: they take no modifiers of their own
            for (ctor in item.members where ctor.kind == ItemKind.EnumCtor) {
                for (name in ctor.names) {
                    entryOf(ctors, name).add(Def(DefId(db, file, ctor.id), def.visibility))
                }
            }
        }
    }
    DefMap(frozen(names) {taken => taken.toArray().map {t => t[0]}}, frozen(ctors) {defs => defs.toArray()}, errors.toArray())
}

/**
 * The list of `key` in `map`, added empty the first time.
 */
func entryOf<V>(map: IndexMap<String, ArrayList<V>>, key: String): ArrayList<V> {
    if (let Some(list) <- map.get(key)) {
        return list
    }
    let list = ArrayList<V>()
    map[key] = list
    list
}

/**
 * `map` with each list made an array by `toArray`, in the same order.
 */
func frozen<V, R>(map: IndexMap<String, ArrayList<V>>, toArray: (ArrayList<V>) -> Array<R>): IndexMap<String, Array<R>> {
    IndexMap<String, Array<R>>(map.toArray().map {entry => (entry[0], toArray(entry[1]))})
}

/**
 * What a package's scope is read at (#175): what its files write, or that and what the macro calls
 * in them add. A macro's name is looked up in the first, since no macro is ever generated and what
 * is expanded depends on it: the second is a function of the first, and never a cycle of queries.
 */
@Derive[Equatable, Hashable]
public enum ScopeStage {
    | Written
    | Expanded
}

/**
 * The `DefMap` of `pkg`, what the macros called in it add included: `defMapAt` `Expanded`.
 */
public func defMap(db: AnalysisDatabase, pkg: PackageRef): DefMap {
    defMapAt(db, pkg, ScopeStage.Expanded)
}

/**
 * The `DefMap` of `pkg` at `stage`: its files', then, `Expanded`, their expansions' after each,
 * the items an expansion replaces left out (`@Strategy`'s function). An edit inside a body, or one
 * that only moves declarations, leaves the item trees and so this alone. A package compiled
 * already has its macros expanded: one `DefMap` at both.
 */
@CalcaTracked
public func defMapAt(db: AnalysisDatabase, pkg: PackageRef, stage: ScopeStage): DefMap {
    if (let Binary(_) <- pkg && stage == ScopeStage.Written) {
        return defMapAt(db, pkg, ScopeStage.Expanded)
    }
    let files = filesOf(db, pkg)
    if (stage == ScopeStage.Written) {
        return collectDefMap(db, files.map {file => (file, itemTreeOf(db, file))})
    }
    let trees = ArrayList<(ItemFile, ItemTree)>()
    for (file in files) {
        let tree = itemTreeOf(db, file)
        let expansions = expansionsOf(db, file)
        let replaced = replacedItemsOf(db, expansions)
        if (replaced.isEmpty()) {
            trees.add((file, tree))
        } else {
            trees.add((file, ItemTree(packageHeader: tree.packageHeader, imports: tree.imports,
                items: tree.items.filter {item => !replaced.contains(item.id)})))
        }
        trees.add(all: expansions.map {one => (one, itemTreeOf(db, one))})
    }
    collectDefMap(db, trees.toArray())
}
