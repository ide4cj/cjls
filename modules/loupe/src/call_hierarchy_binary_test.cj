package loupe

import std.unittest.*
import std.unittest.testmacro.*
import loupe.fixture.*
import rope.Rope

@Test
class BinaryCallHierarchyTest {
    @TestCase
    func localFunctionsInAttachedBodiesKeepTheirOwnIdentity() {
        // arrange
        let fixture = Fixture.parse(
            #"
            //- /main.cj module=m package=m
            package m
            main() { $0println("x") }
            "#
        )
        let db = fixture.database(
            binaries: [stdCjoRead("std.core", stdCjo("std.core"))],
            models: [stdWithSources(["std.core"])]
        )
        let cursor = fixture.cursor.getOrThrow()
        let target = prepareCallHierarchy(db, cursor.fileId, cursor.offset)[0].target
        let text = db.sourceFile(target.fileId).getOrThrow().text(db).toString()
        let start =
            target.focusRange.start + text[target.focusRange.start..].indexOf("{").getOrThrow()
        let before = text[..start]
        let after = text[target.fullRange.end..]
        db.setFileText(
            target.fileId,
            Rope("${before}{ func inner(): Unit { inner() }; inner() }${after}")
        )

        // act
        let entry = prepareCallHierarchy(db, cursor.fileId, cursor.offset)[0]
        let calls = outgoingCalls(db, entry)

        // assert
        @Assert(calls.size, 1)
        @Expect(calls[0].item.name, "inner")
        @Expect(calls[0].ranges.size, 1)
        @Expect(calls[0].item.definition.isNone())

        // act
        let nested = outgoingCalls(db, calls[0].item)

        // assert
        @Assert(nested.size, 1)
        @Expect(nested[0].item, calls[0].item)
        @Expect(nested[0].ranges.size, 1)
    }

    @TestCase
    func attachedStdFunctionsKeepTheirHierarchyAcrossCallsAndDeclarations() {
        // arrange
        let fixture = Fixture.parse(
            #"
            //- /main.cj module=m package=m
            package m
            main() { $0println("x"); println("y") }
            "#
        )
        let db = fixture.database(
            binaries: [stdCjoRead("std.core", stdCjo("std.core"))],
            models: [stdWithSources(["std.core"])]
        )
        let cursor = fixture.cursor.getOrThrow()
        let target = definitionAt(db, cursor.fileId, cursor.offset)[0]

        // act
        let entries = prepareCallHierarchy(db, cursor.fileId, cursor.offset)
        let declarations = prepareCallHierarchy(db, target.fileId, target.focusRange.start)

        // assert
        @Assert(entries.size, 1)
        @Expect(entries[0].name, "println")
        @Expect(entries, declarations)

        // act
        let incoming = incomingCalls(db, entries[0]).filter { it => it.item.name == "main" }

        // assert
        @Assert(incoming.size, 1)
        @Expect(incoming[0].item.name, "main")
        @Expect(incoming[0].ranges.size, 2)

        // act
        let outgoing = outgoingCalls(db, incoming[0].item)
        let body = outgoingCalls(db, entries[0])

        // assert
        @Expect(outgoing.map { it => it.item }, entries)
        @Expect(body.isEmpty(), false)
    }

    @TestCase
    func binaryFunctionsWithoutSourcesGroupByDeclarationAcrossFilesAndOverloads() {
        // arrange
        let fixture = Fixture.parse(
            #"
            //- /main.cj module=m package=m
            package m
            main() { $0println("x"); println("y"); println(1) }
            //- /other.cj module=m package=m
            package m
            func other(): Unit { println("z") }
            "#
        )
        let db = fixture.database(binaries: [stdCjoRead("std.core", stdCjo("std.core"))])
        let cursor = fixture.cursor.getOrThrow()

        // act
        let entries = prepareCallHierarchy(db, cursor.fileId, cursor.offset)

        // assert
        @Expect(definitionAt(db, cursor.fileId, cursor.offset).isEmpty())
        @Assert(entries.size, 1)
        @Expect(entries[0].name, "println")

        // act
        let incoming = incomingCalls(db, entries[0])

        // assert
        @Expect(incoming.map { it => it.item.name }, ["main", "other"])
        @Expect(incoming.map { it => it.ranges.size }, [2, 1])

        // act
        let outgoing = outgoingCalls(db, incoming[0].item)
        let body = outgoingCalls(db, entries[0])

        // assert
        @Expect(outgoing.map { it => it.item.name }, ["println", "println"])
        @Expect(outgoing.map { it => it.ranges.size }, [2, 1])
        @Expect(body.isEmpty())
    }

    @TestCase
    func binaryInitializersAndMethodsWithoutSourcesKeepSeparateEdges() {
        // arrange
        let fixture = Fixture.parse(
            #"
            //- /main.cj module=m package=m
            package m
            import std.collection.ArrayList
            main() {
                let list = ArrayList<Int64>()
                list.$0add(1)
                list.add(2)
            }
            "#
        )
        let db = fixture.database(
            binaries: ["std.core", "std.collection"].map { name => stdCjoRead(name, stdCjo(name)) }
        )
        let cursor = fixture.cursor.getOrThrow()

        // act
        let entries = prepareCallHierarchy(db, cursor.fileId, cursor.offset)

        // assert
        @Assert(entries.size, 1)
        @Expect(entries[0].kind, StructureKind.Method)

        // act
        let incoming = incomingCalls(db, entries[0])

        // assert
        @Assert(incoming.size, 1)
        @Expect(incoming[0].ranges.size, 2)

        // act
        let outgoing = outgoingCalls(db, incoming[0].item)

        // assert
        @Expect(outgoing.map { it => it.item.kind }, [StructureKind.Constructor, StructureKind.Method])
        @Expect(outgoing.map { it => it.item.name }, ["init", "add"])
        @Expect(outgoing.map { it => it.ranges.size }, [1, 2])
    }
}
