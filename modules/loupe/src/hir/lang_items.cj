package loupe.hir

import std.deriving.*
import calca.*
import calca.macros.*
import loupe.db.AnalysisDatabase

/**
 * A declaration of `std.core` the language itself means, whatever a file's scope names: what the
 * syntax is sugar for or is of. cjc's `GetCoreDecl`, R1's lang items (8f). Not the compiler's own
 * types (`CPointer`, `CString`): a file names those, through its scope.
 */
@Derive[Equatable, Hashable]
public enum LangItem {
    /**
     * `Option`: `?T`, `??`, `as`, a value boxed.
     */
    | OptionEnum
    /**
     * `composition`: `f ~> g`; not `public`, a file cannot name it.
     */
    | CompositionFunc
    /**
     * `Object`: the superclass of a class of none.
     */
    | ObjectClass
    /**
     * `String`: a string literal.
     */
    | StringStruct
    /**
     * `Future`: `spawn`.
     */
    | FutureClass
    /**
     * `Iterable`: what `for-in` iterates over.
     */
    | IterableInterface
    /**
     * `Range`: `a..b`.
     */
    | RangeStruct
    /**
     * `Array`: `[a, b]`.
     */
    | ArrayStruct

    public func name(): String {
        match (this) {
            case OptionEnum => "Option"
            case CompositionFunc => "composition"
            case ObjectClass => "Object"
            case StringStruct => "String"
            case FutureClass => "Future"
            case IterableInterface => "Iterable"
            case RangeStruct => "Range"
            case ArrayStruct => "Array"
        }
    }

    public func kind(): ItemKind {
        match (this) {
            case OptionEnum => ItemKind.Enum
            case CompositionFunc => ItemKind.Func
            case ObjectClass | FutureClass => ItemKind.Class
            case StringStruct | RangeStruct | ArrayStruct => ItemKind.Struct
            case IterableInterface => ItemKind.Interface
        }
    }
}

/**
 * The declaration `item` of the `std.core` the package `from` may import, its visibility aside; none
 * without an SDK.
 */
@CalcaTracked
public func langItem(db: AnalysisDatabase, from: PackageRef, item: LangItem): ?DefId {
    let core = packageIndex(db).find("std.core", from: from) ?? return None
    let defs = packageExports(db, core).names.get(item.name()) ?? return None
    defs.iterator().filter {one => one.id.item(db).kind == item.kind()}.next().map {one => one.id}
}
