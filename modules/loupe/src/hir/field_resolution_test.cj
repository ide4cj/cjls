package loupe.hir

import std.unittest.*
import std.unittest.testmacro.*
import std.collection.*
import loupe.db.AnalysisDatabase
import loupe.fixture.*

@Test
class FieldResolutionTest {
    @TestCase
    func superOfAClassOfNoSuperclassIsObject() {
        // N79: cjc's "'hashCode' is not a member of class 'Object'"
        // arrange
        let (db, _, c) = declOf(#"
            package m
            class C {
                func g(): Unit { super.hashCode() }
            }
            "#, "C", binaries: [stdCjoRead("std.core", stdCjo("std.core"))])
        let g = DefId(db, c.file(db), named(itemOf(db, c).getOrThrow().members, "g").id)
        let lowered = body(db, g)
        let superExpr = (0..lowered.exprs.size).iterator().filter {i => lowered.exprs[i] == Expr.SuperExpr}.next().getOrThrow()
        // act
        let receiver = receiverOf(db, g, ExprId(superExpr))
        // assert
        let names = match (receiver) {
            case TypesReceiver(types) => types.map {
                ty => match (ty) {
                    case DeclType(id) => itemOf(db, id).flatMap {item => item.names.get(0)} ?? ""
                    case PrimType(name) => name
                }
            }
            case _ => Array<String>()
        }
        @Expect(names, ["Object"])
    }

    @TestCase
    func aStaticOfATypeOfTheLanguageIsStdCoresExtends() {
        // N84
        // arrange
        let (db, _, f) = declOf(#"
            package m
            func f(): Int64 { Int64.Max }
            "#, "f", binaries: [stdCjoRead("std.core", stdCjo("std.core"))])
        // act
        let resolution = resolveField(db, f, fieldNamed(db, f, "Max"))
        // assert
        @Expect(describe(db, resolution), ["std.core extend Max"])
    }

    @TestCase
    func anExtendOfNoInterfaceOfStdCoreIsSeenEverywhere() {
        // N84: `std.core`'s `extend Float64 { fromBits, toBits }`, the type's package's (N81)
        // arrange
        let (db, _, f) = declOf(#"
            package m
            func f(): Float64 { Float64.fromBits(0) }
            "#, "f", binaries: [stdCjoRead("std.core", stdCjo("std.core"))])
        // act
        let resolution = resolveField(db, f, fieldNamed(db, f, "fromBits"))
        // assert
        @Expect(describe(db, resolution), ["std.core extend fromBits"])
    }

    @TestCase
    func anExtendOfAnInterfacesCjoIsNotSeenWithoutTheInterface() {
        // N84, N82: cjc's "undeclared identifier 'parse'"
        // arrange
        let (db, _, f) = declOf(#"
            package m
            func f(): Int64 { Int64.parse("1") }
            "#, "f", binaries: [stdCjoRead("std.core", stdCjo("std.core")), stdCjoRead("std.convert", stdCjo("std.convert"))])
        // act
        let resolution = resolveField(db, f, fieldNamed(db, f, "parse"))
        // assert
        @Expect(resolution, FieldResolution.NoField)
    }

    @TestCase
    func anExtendOfAnInterfacesCjoIsSeenThroughTheInterfaceImported() {
        // N84, N82: `Parsable`'s and `RadixConvertible`'s, an implementation and what it implements
        // both (step 8)
        // arrange
        let (db, _, f) = declOf(#"
            package m
            import std.convert.*
            func f(): Int64 { Int64.parse("1") }
            "#, "f", binaries: [stdCjoRead("std.core", stdCjo("std.core")), stdCjoRead("std.convert", stdCjo("std.convert"))])
        // act
        let resolution = resolveField(db, f, fieldNamed(db, f, "parse"))
        // assert
        @Expect(describe(db, resolution),
            ["std.convert extend parse", "std.convert extend parse", "std.convert interface parse", "std.convert interface parse"])
    }

    @TestCase
    func anExtendOfACjoIsByTheTypeItsBytesName() {
        // a type of the language by its keyword, `Array` as `std.core`'s struct, `CPointer` as its builtin
        // arrange
        let db = declOf(#"
            package m
            func f(): Unit {}
            "#, "f", binaries: [stdCjoRead("std.core", stdCjo("std.core"))])[0]
        let core = packageIndex(db).packages.get("std.core").getOrThrow()[0].pkg
        // act
        let extended = packageExtends(db, core).keys().toArray().map {ty => describe(db, ty)}
        // assert
        @Expect(extended.contains("Int64"), true)
        @Expect(extended.contains("Struct Array"), true)
        @Expect(extended.contains("BuiltIn CPointer"), true)
    }
}

/**
 * The `FieldExpr` of `name` in the body of `def`.
 */
func fieldNamed(db: AnalysisDatabase, def: DefId, name: String): ExprId {
    let lowered = body(db, def)
    let index = (0..lowered.exprs.size).iterator().filter {
        i => match (lowered.exprs[i]) {
            case FieldExpr(_, each, _) => each == name
            case _ => false
        }
    }.next().getOrThrow()
    ExprId(index)
}

/**
 * The members `resolution` found, each as its package, the kind of the item it is in and its name.
 */
func describe(db: AnalysisDatabase, resolution: FieldResolution): Array<String> {
    let targets = match (resolution) {
        case TypeMembers(targets) => targets
        case _ => return []
    }
    targets |> filterMap {
        target: MemberTarget => match (target) {
            case MemberDecl(id) =>
                let pkg = packageRefOf(db, id).map {pkg => nameOf(db, pkg)} ?? ""
                let parent = parentOf(db, id).map {one => one.item(db).kind.toString().toAsciiLower()} ?? ""
                let name = parentOf(db, id).flatMap {one => itemOf(db, one)}.flatMap {
                    item => item.members.iterator().filter {member => member.id == id.item(db)}.next()
                }.flatMap {member => member.names.get(0)} ?? ""
                "${pkg} ${parent} ${name}"
            case MemberParam(_, _) => None
        }
    } |> collectArray
}

/**
 * `ty`, a type of the language by its keyword, a declaration by its kind and name.
 */
func describe(db: AnalysisDatabase, ty: ExtendedType): String {
    match (ty) {
        case DeclType(id) => "${id.item(db).kind} ${itemOf(db, id).flatMap {item => item.names.get(0)} ?? ""}"
        case PrimType(name) => name
    }
}
