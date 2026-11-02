package loupe

import std.unittest.*
import std.unittest.testmacro.*
import loupe.fixture.*
import loupe.hir.*
import loupe.db.{MappedSpan, SpanOrigin}
import rope.Rope

@Test
class DirectCallsTest {
    @TestCase
    func resolvesCallsButDoesNotExecuteNestedDeclarations() {
        let fixture = Fixture.parse(
            #"
            package m
            func target(): Unit {}
            func unused(): Unit {}
            func $0caller(): Unit {
                func local(): Unit { unused() }
                let lambda = { => unused() }
                target()
            }
            "#
        )
        let db = fixture.database()
        let file = db.sourceFile(fixture.files[0].fileId).getOrThrow()
        let def = itemTree(db, file).items.filter { item => item.names == ["caller"] }[0]
        let calls = directCalls(db, DefId(db, ItemFile.Source(file), def.id))
        @Expect(calls.edges.map { edge => itemOf(db, edge.target).getOrThrow().names[0] }, ["target"])
        @Expect(calls.edges[0].conservative, false)
        @Expect(calls.gaps.isEmpty())
    }

    @TestCase
    func aliasOwnershipAndBodyAndTargetEditsInvalidate() {
        let fixture = Fixture.parse(
            #"
            //- /a.cj module=m package=m.a
            package m.a
            public func target(): Unit {}
            public func other(): Unit {}
            //- /b.cj module=m package=m
            package m
            import m.a.target as alias
            func caller(): Unit { alias() }
            "#
        )
        let db = fixture.database()
        let file = db.sourceFile(fixture.files[1].fileId).getOrThrow()
        let item = itemTree(db, file).items.filter { item => item.names == ["caller"] }[0]
        let def = DefId(db, ItemFile.Source(file), item.id)
        let first = directCalls(db, def)
        @Expect(first.edges.size, 1)
        @Expect(callDeclaration(db, first.edges[0].target).packageName, "m.a")
        @Expect(callDeclaration(db, first.edges[0].target).name, "target")
        db.setFileText(
            fixture.files[1].fileId,
            Rope(fixture.files[1].text.replace("alias()", "alias(); alias()"))
        )
        @Expect(directCalls(db, def).edges.size, 2)
        db.setFileText(
            fixture.files[1].fileId,
            Rope(fixture.files[1].text.replace("m.a.target", "m.a.other"))
        )
        @Expect(callDeclaration(db, directCalls(db, def).edges[0].target).name, "other")
        let target = directCalls(db, def).edges[0].target
        @Expect(directCalls(db, target).edges.isEmpty())
        db.setFileText(
            fixture.files[0].fileId,
            Rope(fixture.files[0].text.replace("other(): Unit {}", "other(): Unit { target() }"))
        )
        @Expect(directCalls(db, target).edges.size, 1)
    }

    @TestCase
    func reportsUnsupportedExecutionAndDispatch() {
        let fixture = Fixture.parse(
            #"
            package m
            interface I { func run(): Unit }
            class C { init() {} }
            func target(): Unit {}
            func caller(i: I, callback: () -> Unit): Unit {
                func local(): Unit { target() }
                local()
                callback()
                let lambda = { => target() }
                lambda()
                i.run()
                C()
                missing()
            }
            "#
        )
        let db = fixture.database()
        let file = db.sourceFile(fixture.files[0].fileId).getOrThrow()
        let item = itemTree(db, file).items.filter { item => item.names == ["caller"] }[0]
        let calls = directCalls(db, DefId(db, ItemFile.Source(file), item.id))
        let reasons = calls.gaps.map { gap => gap.reason }
        @Expect(reasons.contains("functional-value"))
        @Expect(reasons.contains("unresolved-call"))
        @Expect(reasons.contains("virtual-dispatch"))
        @Expect(reasons.contains("implicit-initialization"))
        @Expect(calls.edges.any { edge => edge.conservative })
        @Expect(!calls.edges.any { edge => itemOf(db, edge.target).getOrThrow().names == ["target"] })
    }
    @TestCase
    func overloadsOperatorsPropertiesAndReturnedFunctionsKeepEvidenceAndGaps() {
        let fixture = Fixture.parse(
            #"
            package m
            func f(x: Int64): Unit {}
            func f(x: Bool): Unit {}
            class C {
                init(x: Int64) {}
                operator func +(rhs: C): C { this }
                prop value: Int64 { get() { 1 } set(x) {} }
            }
            func factory(): () -> Unit { { => f(1) } }
            func caller(c: C): Unit {
                f(1)
                let other = C(1)
                let sum = c + other
                let x = c.value
                c.value = x
                factory()()
                @Unknown(f(2))
            }
            "#
        )
        let db = fixture.database()
        let file = db.sourceFile(fixture.files[0].fileId).getOrThrow()
        let item = itemTree(db, file).items.filter { item => item.names == ["caller"] }[0]
        let calls = directCalls(db, DefId(db, ItemFile.Source(file), item.id))
        let targets = calls.edges.map { edge => itemOf(db, edge.target).getOrThrow() }
        @Expect(targets.filter { target => target.names == ["f"] }.size, 1)
        @Expect(targets.any { target => target.kind == ItemKind.Init })
        @Expect(calls.edges.any { edge => edge.resolution == "inferred-operator" })
        let reasons = calls.gaps.map { gap => gap.reason }
        @Expect(reasons.contains("implicit-operator"))
        @Expect(reasons.contains("property-or-initialization"))
        @Expect(reasons.contains("functional-value"))
        @Expect(reasons.contains("body-macro"))
        @Expect(!reasons.contains("declaration-macro"))
    }

    @TestCase
    func binaryTargetsRetainPackageAndUnavailableBodyGap() {
        let fixture = Fixture.parse("package m\nfunc caller(): Unit { println(readln()) }")
        let db = fixture.database(binaries: [stdCjoRead("std.core", stdCjo("std.core"))])
        let file = db.sourceFile(fixture.files[0].fileId).getOrThrow()
        let item = itemTree(db, file).items[0]
        let calls = directCalls(db, DefId(db, ItemFile.Source(file), item.id))
        @Expect(calls.edges.size, 2)
        for (edge in calls.edges) {
            @Expect(callDeclaration(db, edge.target).packageName, "std.core")
            @Expect(directCalls(db, edge.target).gaps[0].reason, "unavailable-body")
        }
    }

    @TestCase
    func calcaExpansionTargetsUseOriginalBodyWithoutInfrastructureCalls() {
        let fixture = Fixture.parse(
            #"
            //- /main.cj module=m package=m
            package m
            import calca.macros.CalcaTracked as Track
            func target(): Unit {}
            func infrastructure(): Unit {}
            @Track
            func query(): Unit { target() }
            func caller(): Unit { query() }
            //- /ms.cj module=m package=calca.macros
            macro package calca.macros
            public macro CalcaTracked(input: Tokens): Tokens { input }
            public macro CalcaTracked(attrs: Tokens, input: Tokens): Tokens { input }
            "#
        )
        let db = fixture.database()
        let file = db.sourceFile(fixture.files[0].fileId).getOrThrow()
        let output = "func query(): Unit { infrastructure() }"
        let start =
            match (requestFor(db, file, "CalcaTracked").input.spans[0].origin) {
                case FromSource(range) => range.start + 5
                case _ => throw FixtureException("expected copied macro input")
            }
        answer(
            db,
            file,
            "CalcaTracked",
            output,
            [
                MappedSpan(TextRange(0, 5), SpanOrigin.FromCall),
                MappedSpan(TextRange(5, 10), SpanOrigin.FromSource(TextRange(start, start + 5))),
                MappedSpan(TextRange(10, output.size), SpanOrigin.FromCall)
            ]
        )
        @Expect(trackedCallRoots(db, file.fileId(db)).size, 1)
        let sourceQuery = DefId(
            db,
            ItemFile.Source(file),
            itemTree(db, file).items.filter { item => item.names == ["query"] }[0].id
        )
        @Expect(expandedDeclOf(db, sourceQuery).isSome())
        let item = itemTree(db, file).items.filter { item => item.names == ["caller"] }[0]
        let calls = directCalls(db, DefId(db, ItemFile.Source(file), item.id))
        @Assert(calls.edges.size, 1)
        let query = calls.edges[0].target
        @Expect(query.file(db), ItemFile.Source(file))
        let nested = directCalls(db, query)
        @Expect(nested.edges.map { edge => callDeclaration(db, edge.target).name }, ["target"])
    }
}
