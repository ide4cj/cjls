package loupe

import std.unittest.*
import std.unittest.testmacro.*
import loupe.fixture.*
import rope.Rope

@Test
class CallHierarchyTest {
    @TestCase
    func groupsCrossFileCallsAndExcludesFunctionValues() {
        // arrange
        let fixture =
            Fixture
                .parse(
                    #"
            //- /a.cj module=m package=m
            package m
            func $0target(): Unit {}
            //- /b.cj module=m package=m
            package m
            func caller(): Unit { target(); target() }
            func value(): Unit { let f = target }
            "#
                )
        let db = fixture.database()
        let cursor = fixture.cursor.getOrThrow()
        let entry = prepareCallHierarchy(db, cursor.fileId, cursor.offset)[0]

        // act
        let incoming = incomingCalls(db, entry)
        let outgoing = outgoingCalls(db, incoming[0].item)

        // assert
        @Expect(incoming.size, 1)
        @Expect(incoming[0].item.name, "caller")
        @Expect(incoming[0].ranges.size, 2)
        @Expect(outgoing.size, 1)
        @Expect(outgoing[0].item, entry)
        @Expect(outgoing[0].ranges, incoming[0].ranges)
        @Expect(outgoingCalls(db, entry).isEmpty())
    }

    @TestCase
    func resolvesOverloadsMethodsAndRecursion() {
        // arrange
        let fixture =
            Fixture
                .parse(
                    #"
            package m
            func f(x: Int64): Unit {}
            func f(x: Bool): Unit {}
            class C { public func g(): Unit {} }
            func $0caller(c: C): Unit { f(1); c.g(); caller(c) }
            "#
                )
        let db = fixture.database()
        let cursor = fixture.cursor.getOrThrow()
        let entry = prepareCallHierarchy(db, cursor.fileId, cursor.offset)[0]

        // act
        let calls = outgoingCalls(db, entry)

        // assert
        @Expect(calls.map { it => it.item.name }, ["f", "g", "caller"])
        @Expect(calls[0].item.target.focusRange.start,
            offsetIn(fixture.files[0].text, "f(x: Int64)"))
        @Expect(calls[1].item.kind, StructureKind.Method)
        @Expect(calls[2].item, entry)
        @Expect(incomingCalls(db, calls[0].item).size, 1)
    }

    @TestCase
    func localFunctionsHaveTheirOwnCallsAndLambdasBelongToTheEnclosingFunction() {
        // arrange
        let fixture =
            Fixture
                .parse(
                    #"
            package m
            func target(): Unit {}
            func $0outer(): Unit {
                func inner(): Unit { target() }
                inner()
                let closure = { => target() }
            }
            "#
                )
        let db = fixture.database()
        let cursor = fixture.cursor.getOrThrow()
        let entry = prepareCallHierarchy(db, cursor.fileId, cursor.offset)[0]

        // act
        let calls = outgoingCalls(db, entry)
        let inner = outgoingCalls(db, calls[0].item)

        // assert
        @Expect(calls.map { it => it.item.name }, ["inner", "target"])
        @Expect(calls[1].ranges.size, 1)
        @Expect(inner.map { it => it.item.name }, ["target"])
        @Expect(incomingCalls(db, inner[0].item).map { it => it.item.name }, ["inner", "outer"])
    }

    @TestCase
    func constructorCallsUseTheSelectedInitializer() {
        // arrange
        let fixture =
            Fixture
                .parse(
                    #"
            package m
            func target(): Unit {}
            class C {
                init(x: Int64) { target() }
                init(x: Bool) {}
            }
            func caller(): Unit { $0C(1) }
            "#
                )
        let db = fixture.database()
        let cursor = fixture.cursor.getOrThrow()

        // act
        let entries = prepareCallHierarchy(db, cursor.fileId, cursor.offset)
        let incoming = incomingCalls(db, entries[0])
        let outgoing = outgoingCalls(db, entries[0])

        // assert
        @Expect(entries.size, 1)
        @Expect(entries[0].kind, StructureKind.Constructor)
        @Expect(incoming.map { it => it.item.name }, ["caller"])
        @Expect(outgoing.map { it => it.item.name }, ["target"])
    }

    @TestCase
    func importedAliasesAndParenthesizedCallsResolveToTheDeclaration() {
        // arrange
        let fixture =
            Fixture
                .parse(
                    #"
            //- /a.cj module=m package=m.a
            package m.a
            public func target(): Unit {}
            //- /b.cj module=m package=m
            package m
            import m.a.target as alias
            func $0caller(): Unit { alias(); (alias)() }
            "#
                )
        let db = fixture.database()
        let cursor = fixture.cursor.getOrThrow()
        let entry = prepareCallHierarchy(db, cursor.fileId, cursor.offset)[0]

        // act
        let calls = outgoingCalls(db, entry)
        let callers = incomingCalls(db, calls[0].item)

        // assert
        @Expect(calls.map { it => it.item.name }, ["target"])
        @Expect(calls[0].ranges.size, 2)
        @Expect(callers.map { it => it.item.name }, ["caller"])
    }

    @TestCase
    func mainIsACallerAndEnumConstructorsAreCallable() {
        // arrange
        let fixture =
            Fixture
                .parse(
                    #"
            package m
            enum E { V(Int64) }
            $0main(): Int64 { let value = E.V(1); 0 }
            "#
                )
        let db = fixture.database()
        let cursor = fixture.cursor.getOrThrow()
        let entry = prepareCallHierarchy(db, cursor.fileId, cursor.offset)[0]

        // act
        let calls = outgoingCalls(db, entry)

        // assert
        @Expect(entry.name, "main")
        @Expect(calls.map { it => it.item.name }, ["V"])
        @Expect(calls[0].item.kind, StructureKind.EnumConstructor)
    }

    @TestCase
    func callEdgesAreInvalidatedAfterAnEdit() {
        // arrange
        let fixture =
            Fixture.parse("package m\nfunc target(): Unit {}\nfunc $0caller(): Unit { target() }")
        let db = fixture.database()
        let cursor = fixture.cursor.getOrThrow()
        let entry = prepareCallHierarchy(db, cursor.fileId, cursor.offset)[0]

        // act
        let before = outgoingCalls(db, entry)
        db
            .setFileText(
                cursor.fileId,
                Rope("package m\nfunc target(): Unit {}\nfunc caller(): Unit {}")
            )
        let updated = prepareCallHierarchy(db, cursor.fileId, cursor.offset)[0]
        let after = outgoingCalls(db, updated)
        let incoming = incomingCalls(db, before[0].item)

        // assert
        @Expect(before.size, 1)
        @Expect(after.isEmpty())
        @Expect(incoming.isEmpty())
    }

    @TestCase
    func inactiveCallsAreExcluded() {
        // arrange
        let fixture =
            Fixture
                .parse(
                    #"
            //- /main.cj cfg=os:Linux
            func target(): Unit {}
            func $0caller(): Unit {
                @When[os == "Windows"]
                let ignored = target()
                target()
            }
            "#
                )
        let db = fixture.database()
        let cursor = fixture.cursor.getOrThrow()
        let entry = prepareCallHierarchy(db, cursor.fileId, cursor.offset)[0]

        // act
        let calls = outgoingCalls(db, entry)

        // assert
        @Expect(calls.map { it => it.item.name }, ["target"])
        @Expect(calls[0].ranges.size, 1)
    }

    @TestCase
    func aVariableHasNoHierarchy() {
        // arrange
        let fixture = Fixture.parse("package m\nlet $0x = 1")
        let db = fixture.database()
        let cursor = fixture.cursor.getOrThrow()

        // act
        let entries = prepareCallHierarchy(db, cursor.fileId, cursor.offset)

        // assert
        @Expect(entries.isEmpty())
    }

    @TestCase
    func trailingLambdaDoesNotDuplicateTheCall() {
        // arrange
        let fixture =
            Fixture
                .parse(
                    #"
            package m
            func apply(f: () -> Unit): Unit { f() }
            func $0caller(): Unit { apply() { => } }
            "#
                )
        let db = fixture.database()
        let cursor = fixture.cursor.getOrThrow()
        let entry = prepareCallHierarchy(db, cursor.fileId, cursor.offset)[0]

        // act
        let calls = outgoingCalls(db, entry)

        // assert
        @Expect(calls.map { it => it.item.name }, ["apply"])
        @Expect(calls[0].ranges.size, 1)
    }
}
