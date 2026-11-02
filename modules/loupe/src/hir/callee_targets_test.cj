package loupe.hir

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import loupe.fixture.*

@Test
class CalleeTargetsTest {
    @TestCase
    func nestedUnambiguousCallsKeepTheirDeclarationsAfterOverloadSelection() {
        // arrange
        let fixture =
            Fixture
                .parse(
                    #"
            package m
            func getA(): Int8 { 1 }
            func getB(): Int16 { 2 }
            func answer(a: Int8, b: Int16): Int16 { b }
            func answer(a: Bool, b: Bool): Bool { a }
            main() { println(answer(getA(), getB())) }
            "#
                )
        let db = fixture.database(binaries: [stdCjoRead("std.core", stdCjo("std.core"))])
        let file = db.sourceFile(fixture.files[0].fileId).getOrThrow()
        let item = itemTree(db, file).items.filter { it => it.kind == ItemKind.Main }[0]
        let def = DefId(db, ItemFile.Source(file), item.id)
        let hir = body(db, def)

        // act
        let inferred = inferBody(db, def)
        let names =
            hir
                .exprs
                .flatMap {
                    expr =>
                    match (expr) {
                        case CallExpr(callee, _) =>
                            inferred
                                .calleesOf(callee)
                                .map { target => itemOf(db, target).getOrThrow().names[0] }
                        case _ => Array<String>()
                    }
                }

        // assert
        @Expect(names, ["getA", "getB", "answer", "println"])
        @Expect(inferred.diagnostics.isEmpty())
    }

    @TestCase
    func unambiguousBinaryCallsAreAvailableWithoutSourceAttachments() {
        // arrange
        let fixture = Fixture.parse("package m\nmain() { println(readln()) }")
        let db = fixture.database(binaries: [stdCjoRead("std.core", stdCjo("std.core"))])
        let file = db.sourceFile(fixture.files[0].fileId).getOrThrow()
        let item = itemTree(db, file).items[0]
        let def = DefId(db, ItemFile.Source(file), item.id)
        let hir = body(db, def)

        // act
        let inferred = inferBody(db, def)
        let targets: Array<DefId> =
            hir
                .exprs
                .flatMap {
                    expr =>
                    match (expr) {
                        case CallExpr(callee, _) => inferred.calleesOf(callee)
                        case _ => Array<DefId>()
                    }
                }

        // assert
        @Expect(targets.map { target => itemOf(db, target).getOrThrow().names[0] }, ["readln", "println"])
        @Expect(targets.iterator().all {
            target =>
            match (target.file(db)) {
                case Binary(_, _) => true
                case _ => false
            }
        })
        @Expect(inferred.diagnostics.isEmpty())
    }
}
