package loupe.hir

import calca.*
import calca.macros.*
import loupe.db.AnalysisDatabase
import py_interop.*
import py_interop.internal_macros.DerivePython

/**
 * A declaration of std the language itself means, whatever a file's scope names: what the syntax is
 * sugar for or is of. cjc's `GetCoreDecl`, R1's lang items (8f). Not the compiler's own types
 * (`CPointer`, `CString`): a file names those, through its scope.
 */
@DerivePython
public enum LangItem <: Equatable<LangItem> & Hashable {
    /**
     * `Option`: `?T`, `??`, `as`, a value boxed.
     */
    | OptionEnum
    /**
     * `Option`'s `Some` and `None`: what an optional chain `a?.b` is desugared to (8g).
     */
    | OptionSome
    | OptionNone
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
    /**
     * `Exception`: what `@AssertThrows` of no `[…]` gives (N136).
     */
    | ExceptionClass
    /**
     * `std.ast`'s `Tokens`: `quote(…)` (N136).
     */
    | TokensClass
    /**
     * `Any`: what every type implements.
     */
    | AnyInterface

    public func name(): String {
        match (this) {
            case OptionEnum => "Option"
            case OptionSome => "Some"
            case OptionNone => "None"
            case CompositionFunc => "composition"
            case ObjectClass => "Object"
            case StringStruct => "String"
            case FutureClass => "Future"
            case IterableInterface => "Iterable"
            case RangeStruct => "Range"
            case ArrayStruct => "Array"
            case ExceptionClass => "Exception"
            case TokensClass => "Tokens"
            case AnyInterface => "Any"
        }
    }

    public func kind(): ItemKind {
        match (this) {
            case OptionEnum => ItemKind.Enum
            case OptionSome | OptionNone => ItemKind.EnumCtor
            case CompositionFunc => ItemKind.Func
            case ObjectClass | FutureClass | ExceptionClass | TokensClass => ItemKind.Class
            case StringStruct | RangeStruct | ArrayStruct => ItemKind.Struct
            case IterableInterface | AnyInterface => ItemKind.Interface
        }
    }

    /**
     * The package of std it is declared in.
     */
    public func pkg(): String {
        match (this) {
            case TokensClass => "std.ast"
            case _ => "std.core"
        }
    }

    /**
     * The lang item it is a member of: an enum's of a constructor.
     */
    public func owner(): ?LangItem {
        match (this) {
            case OptionSome | OptionNone => OptionEnum
            case _ => None
        }
    }

    public operator func ==(other: LangItem): Bool {
        match ((this, other)) {
            case (LangItem.OptionEnum, LangItem.OptionEnum) => true
            case (LangItem.OptionSome, LangItem.OptionSome) => true
            case (LangItem.OptionNone, LangItem.OptionNone) => true
            case (LangItem.CompositionFunc, LangItem.CompositionFunc) => true
            case (LangItem.ObjectClass, LangItem.ObjectClass) => true
            case (LangItem.StringStruct, LangItem.StringStruct) => true
            case (LangItem.FutureClass, LangItem.FutureClass) => true
            case (LangItem.IterableInterface, LangItem.IterableInterface) => true
            case (LangItem.RangeStruct, LangItem.RangeStruct) => true
            case (LangItem.ArrayStruct, LangItem.ArrayStruct) => true
            case (LangItem.ExceptionClass, LangItem.ExceptionClass) => true
            case (LangItem.TokensClass, LangItem.TokensClass) => true
            case (LangItem.AnyInterface, LangItem.AnyInterface) => true
            case _ => false
        }
    }

    public operator func !=(other: LangItem): Bool {
        !(this == other)
    }

    public func hashCode(): Int64 {
        var hasher = DefaultHasher()
        match (this) {
            case LangItem.OptionEnum => hasher.write(0)
            case LangItem.OptionSome => hasher.write(1)
            case LangItem.OptionNone => hasher.write(2)
            case LangItem.CompositionFunc => hasher.write(3)
            case LangItem.ObjectClass => hasher.write(4)
            case LangItem.StringStruct => hasher.write(5)
            case LangItem.FutureClass => hasher.write(6)
            case LangItem.IterableInterface => hasher.write(7)
            case LangItem.RangeStruct => hasher.write(8)
            case LangItem.ArrayStruct => hasher.write(9)
            case LangItem.ExceptionClass => hasher.write(10)
            case LangItem.TokensClass => hasher.write(11)
            case LangItem.AnyInterface => hasher.write(12)
        }
        hasher.finish()
    }
}

/**
 * The declaration `item` of the std the package `from` may import, its visibility aside; none
 * without an SDK.
 */
@CalcaTracked
public func langItem(db: AnalysisDatabase, from: PackageRef, item: LangItem): ?DefId {
    if (let Some(owner) <- item.owner()) {
        let parent = langItem(db, from, owner) ?? return None
        let members = declItemOf(db, parent)?.members ?? return None
        let file = parent.file(db)
        return members
            .iterator()
            .map { member => DefId(db, file, member.id) }
            .filter { one => one.item(db).kind == item.kind() && isNamed(db, one, item.name()) }
            .next()
    }
    let core = packageIndex(db).find(item.pkg(), from: from) ?? return None
    let defs = packageExports(db, core).names.get(item.name()) ?? return None
    defs
        .iterator()
        .filter { one => one.id.item(db).kind == item.kind() }
        .next()
        .map { one => one.id }
}
