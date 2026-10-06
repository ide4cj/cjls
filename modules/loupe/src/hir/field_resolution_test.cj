package loupe.hir

import std.unittest.*
import std.unittest.testmacro.*
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
    func aMemberOfAPrimitiveTypeIsNotFoundWithoutItsExtends() {
        // the extends of `std.core` are not read from its `.cjo` yet: `Int64.Max` resolves to nothing
        // arrange
        let (db, _, f) = declOf(#"
            package m
            func f(): Int64 { Int64.Max }
            "#, "f", binaries: [stdCjoRead("std.core", stdCjo("std.core"))])
        let lowered = body(db, f)
        let field = (0..lowered.exprs.size).iterator().filter {
            i => match (lowered.exprs[i]) {
                case FieldExpr(_, "Max", _) => true
                case _ => false
            }
        }.next().getOrThrow()
        // act
        let resolution = resolveField(db, f, ExprId(field))
        // assert
        @Expect(resolution, FieldResolution.NoField)
    }
}
