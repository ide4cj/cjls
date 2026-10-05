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
public enum PackageRef <: Equatable<PackageRef> & Hashable & ToString {
    | Source(Package)
    | Binary(BinaryPackageFile)

    public operator func ==(other: PackageRef): Bool {
        match ((this, other)) {
            case (Source(a), Source(b)) => a == b
            case (Binary(a), Binary(b)) => a == b
            case _ => false
        }
    }

    public operator func !=(other: PackageRef): Bool {
        !(this == other)
    }

    public func hashCode(): Int64 {
        var hasher = DefaultHasher()
        match (this) {
            case Source(pkg) =>
                hasher.write(0)
                hasher.write(pkg.hashCode())
            case Binary(pkg) =>
                hasher.write(1)
                hasher.write(pkg.hashCode())
        }
        hasher.finish()
    }

    public func toString(): String {
        match (this) {
            case Source(pkg) => "Source(${pkg})"
            case Binary(pkg) => "Binary(${pkg})"
        }
    }
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
 * The visibility `item` is written with; `internal` when none is.
 */
public func visibilityOf(item: Item): Visibility {
    if (item.has(Modifier.Private)) {
        Visibility.Private
    } else if (item.has(Modifier.Protected)) {
        Visibility.Protected
    } else if (item.has(Modifier.Public)) {
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
public struct DefMap <: Equatable<DefMap> {
    public DefMap(
        public let names: IndexMap<String, Array<Def>>,
        public let ctors: IndexMap<String, Array<Def>>,
        public let errors: Array<Redefinition>
    ) {}

    public static func empty(): DefMap {
        DefMap(IndexMap(), IndexMap(), [])
    }

    /**
     * What `name` stands for in the file `from` of this package, among the package's own
     * declarations: those it sees (N1, N23), else the constructors (N25). Empty if neither has it.
     */
    public func lookUp(db: AnalysisDatabase, name: String, from!: ItemFile): Array<DefId> {
        []
    }

    public operator func ==(other: DefMap): Bool {
        names == other.names && ctors == other.ctors && errors == other.errors
    }

    public operator func !=(other: DefMap): Bool {
        !(this == other)
    }
}

/**
 * The `DefMap` of the files of a package, each with its item tree, in the package's order.
 */
public func collectDefMap(db: AnalysisDatabase, files: Array<(ItemFile, ItemTree)>): DefMap {
    DefMap.empty()
}

/**
 * The `DefMap` of `pkg`. An edit inside a body, or one that only moves declarations, leaves the
 * item trees and so this alone.
 */
@CalcaTracked
public func defMap(db: AnalysisDatabase, pkg: PackageRef): DefMap {
    collectDefMap(db, filesOf(db, pkg).map {file => (file, itemTreeOf(db, file))})
}
