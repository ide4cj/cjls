package loupe.hir

import std.deriving.*
import calca.*
import calca.macros.*
import loupe.db.AnalysisDatabase

/**
 * A declaration of `std.core` the language itself means, whatever a file's scope names: what `?T`
 * and an operator are sugar for. cjc's `GetCoreDecl`, R1's lang items (8f).
 */
@Derive[Equatable, Hashable]
public enum LangItem {
    /**
     * `Option`: `?T`, `??`.
     */
    | OptionEnum
    /**
     * `composition`: `f ~> g`; not `public`, a file cannot name it.
     */
    | CompositionFunc

    public func name(): String {
        match (this) {
            case OptionEnum => "Option"
            case CompositionFunc => "composition"
        }
    }

    public func kind(): ItemKind {
        match (this) {
            case OptionEnum => ItemKind.Enum
            case CompositionFunc => ItemKind.Func
        }
    }
}

/**
 * The declaration `item` of the `std.core` the package `from` may import, its visibility aside; none
 * without an SDK.
 */
@CalcaTracked
public func langItem(db: AnalysisDatabase, from: PackageRef, item: LangItem): ?DefId {
    coreDecl(db, from, item.name(), item.kind())
}
