package loupe

import std.unittest.*
import std.unittest.testmacro.*
import loupe.db.{MappedSpan, SpanOrigin}
import loupe.fixture.*
import loupe.hir.*
import rope.Rope

@Test
class DirectCallsTest {
    @TestCase
    func resolvesCallsButDoesNotExecuteNestedDeclarations() {
        // arrange
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

        // act
        let calls = directCalls(db, DefId(db, ItemFile.Source(file), def.id))

        // assert
        @Expect(calls.edges.map { edge => itemOf(db, edge.target).getOrThrow().names[0] }, ["target"])
        @Expect(calls.edges[0].isConservative, false)
        @Expect(calls.gaps.isEmpty())
    }

    @TestCase
    func aliasOwnershipAndBodyAndTargetEditsInvalidate() {
        // arrange
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

        // act
        let first = directCalls(db, def)
        let firstDeclaration = callDeclaration(db, first.edges[0].target)

        // assert
        @Expect(first.edges.size, 1)
        @Expect(firstDeclaration.packageName, "m.a")
        @Expect(firstDeclaration.name, "target")

        // act: edit the caller body
        db.setFileText(
            fixture.files[1].fileId,
            Rope(fixture.files[1].text.replace("alias()", "alias(); alias()"))
        )
        let editedCaller = directCalls(db, def)

        // assert
        @Expect(editedCaller.edges.size, 2)

        // act: retarget the import alias
        db.setFileText(
            fixture.files[1].fileId,
            Rope(fixture.files[1].text.replace("m.a.target", "m.a.other"))
        )
        let retargeted = directCalls(db, def)
        let target = retargeted.edges[0].target
        let declaration = callDeclaration(db, target)
        let beforeTargetEdit = directCalls(db, target)

        // assert
        @Expect(declaration.name, "other")
        @Expect(beforeTargetEdit.edges.isEmpty())

        // act: edit the target body
        db.setFileText(
            fixture.files[0].fileId,
            Rope(fixture.files[0].text.replace("other(): Unit {}", "other(): Unit { target() }"))
        )
        let editedTarget = directCalls(db, target)

        // assert
        @Expect(editedTarget.edges.size, 1)
    }

    @TestCase
    func reportsUnsupportedExecutionAndDispatch() {
        // arrange
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

        // act
        let calls = directCalls(db, DefId(db, ItemFile.Source(file), item.id))

        // assert
        let reasons = calls.gaps.map { gap => gap.reason }
        @Expect(reasons.contains("functional-value"))
        @Expect(reasons.contains("unresolved-call"))
        @Expect(reasons.contains("virtual-dispatch"))
        @Expect(reasons.contains("implicit-initialization"))
        @Expect(calls.edges.any { edge => edge.isConservative })
        @Expect(!calls.edges.any { edge => itemOf(db, edge.target).getOrThrow().names == ["target"] })
    }

    @TestCase
    func overloadsOperatorsPropertiesAndReturnedFunctionsKeepEvidenceAndGaps() {
        // arrange
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

        // act
        let calls = directCalls(db, DefId(db, ItemFile.Source(file), item.id))

        // assert
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
        // arrange
        let fixture = Fixture.parse("package m\nfunc caller(): Unit { println(readln()) }")
        let db = fixture.database(binaries: [stdCjoRead("std.core", stdCjo("std.core"))])
        let file = db.sourceFile(fixture.files[0].fileId).getOrThrow()
        let item = itemTree(db, file).items[0]

        // act
        let calls = directCalls(db, DefId(db, ItemFile.Source(file), item.id))

        // assert
        @Expect(calls.edges.size, 2)
        for (edge in calls.edges) {
            // act
            let declaration = callDeclaration(db, edge.target)
            let targetCalls = directCalls(db, edge.target)

            // assert
            @Expect(declaration.packageName, "std.core")
            @Expect(targetCalls.gaps[0].reason, "unavailable-body")
        }
    }

    @TestCase
    func calcaExpansionTargetsUseOriginalBodyWithoutInfrastructureCalls() {
        // arrange
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
        const OUTPUT = "func query(): Unit { infrastructure() }"
        let start =
            match (requestFor(db, file, "CalcaTracked").input.spans[0].origin) {
                case FromSource(range) => range.start + 5
                case _ => throw FixtureException("expected copied macro input")
            }

        // act: supply the macro expansion
        answer(
            db,
            file,
            "CalcaTracked",
            OUTPUT,
            [
                MappedSpan(TextRange(0, 5), SpanOrigin.FromCall),
                MappedSpan(TextRange(5, 10), SpanOrigin.FromSource(TextRange(start, start + 5))),
                MappedSpan(TextRange(10, OUTPUT.size), SpanOrigin.FromCall)
            ]
        )
        let roots = trackedCallRoots(db, file.fileId(db))
        let sourceQuery = DefId(
            db,
            ItemFile.Source(file),
            itemTree(db, file).items.filter { item => item.names == ["query"] }[0].id
        )
        let expanded = expandedDeclOf(db, sourceQuery)

        // assert
        @Expect(roots.size, 1)
        @Expect(expanded.isSome())

        // act: resolve the caller against the expanded declaration
        let item = itemTree(db, file).items.filter { item => item.names == ["caller"] }[0]
        let calls = directCalls(db, DefId(db, ItemFile.Source(file), item.id))

        // assert
        @Assert(calls.edges.size, 1)
        let query = calls.edges[0].target
        @Expect(query.file(db), ItemFile.Source(file))

        // act: inspect the original body through the resolved target
        let nested = directCalls(db, query)
        let names = nested.edges.map { edge => callDeclaration(db, edge.target).name }

        // assert
        @Expect(names, ["target"])
    }
}
