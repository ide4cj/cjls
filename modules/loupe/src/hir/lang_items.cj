package loupe.hir

import std.deriving.*
import calca.*
import calca.macros.*
import loupe.db.AnalysisDatabase

/**
 * A declaration of std the language itself means, whatever a file's scope names: what the syntax is
 * sugar for or is of. cjc's `GetCoreDecl`, R1's lang items (8f). Not the compiler's own types
 * (`CPointer`, `CString`): a file names those, through its scope.
 */
@Derive[Equatable, Hashable]
public enum LangItem {
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
        }
    }

    public func kind(): ItemKind {
        match (this) {
            case OptionEnum => ItemKind.Enum
            case OptionSome | OptionNone => ItemKind.EnumCtor
            case CompositionFunc => ItemKind.Func
            case ObjectClass | FutureClass | ExceptionClass | TokensClass => ItemKind.Class
            case StringStruct | RangeStruct | ArrayStruct => ItemKind.Struct
            case IterableInterface => ItemKind.Interface
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
        return members.iterator().map {member => DefId(db, file, member.id)}.filter {
            one => one.item(db).kind == item.kind() && isNamed(db, one, item.name())
        }.next()
    }
    let core = packageIndex(db).find(item.pkg(), from: from) ?? return None
    let defs = packageExports(db, core).names.get(item.name()) ?? return None
    defs.iterator().filter {one => one.id.item(db).kind == item.kind()}.next().map {one => one.id}
}
