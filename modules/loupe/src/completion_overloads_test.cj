package loupe

import std.sort.sort
import std.unittest.*
import std.unittest.testmacro.*
import loupe.fixture.{Fixture, stdCjo, stdCjoRead}

/**
 * Checks one grouped candidate and every declaration it retains, independent of the unrelated
 * names and keywords at the position. The order must remain stable when the list is resolved again.
 */
func checkCompletionGroup(
    fixture: String,
    label: String,
    expected: Array<String>,
    kind!: CompletionKind = CompletionKind.FuncItem,
    relevance!: Int64 = 80
): Unit {
    let parsed = Fixture.parse(fixture)
    let db = parsed.database()
    let cursor = parsed.cursor.getOrThrow()
    let result = completionsAt(db, cursor.fileId, cursor.offset).getOrThrow()
    let groups = result.items.filter { item => item.label == label && item.kind == kind }
    @Assert(groups.size == 1)
    let group = groups[0]
    @Expect(group.overloadCount, expected.size)
    @Expect(group.relevance, relevance)
    let details = completionDetails(db, cursor.fileId, cursor.offset, group)
    let codes = details.map { item => item.code }
    let wanted = expected.clone()
    sort(codes)
    sort(wanted)
    @Expect(codes, wanted)
    @Expect(completionsAt(db, cursor.fileId, cursor.offset).getOrThrow(), result)
    @Expect(completionDetails(db, cursor.fileId, cursor.offset, group), details)
}

@Test
class CompletionOverloadTest {
    @TestCase
    func importedOverloadsCountEachDeclarationOnceAndKeepTheBestRank() {
        checkCompletionGroup(
            #"
            //- /lib.cj module=m package=m.lib
            package m.lib
            public func print(value: Int64): Unit {}
            public func print(value: Int32): Unit {}
            //- /main.cj module=m package=m deps=m.lib
            package m
            import m.lib.print
            import m.lib.*
            func print(value: Bool): Unit {}
            func use() { pr$0 }
            "#,
            "print",
            [
                "func print(value: Bool): Unit",
                "public func print(value: Int64): Unit",
                "public func print(value: Int32): Unit"
            ],
            relevance: 60
        )
    }

    @TestCase
    func genericMemberOverloadsKeepTheirReceiverAndExcludeInaccessibleMembers() {
        checkCompletionGroup(
            #"
            //- /main.cj module=m package=m
            package m
            class Box<T> {
                public func put(value: T): Unit {}
                public func put(value: T, count: Int64): Unit {}
                private func put(value: Bool): Unit {}
            }
            func use(box: Box<Int32>) { box.p$0 }
            "#,
            "put",
            [
                "public func put(value: Int32): Unit",
                "public func put(value: Int32, count: Int64): Unit"
            ]
        )
    }

    @TestCase
    func constructorGroupsStaySeparateFromATypesMatchingName() {
        let fixture =
            #"
            //- /main.cj module=m package=m
            package m
            struct Value {}
            enum Number { | Value(Int64) }
            enum SmallNumber { | Value(Int32) }
            func use() { Va$0 }
            "#
        checkCompletionGroup(
            fixture,
            "Value",
            ["Value(Int64)", "Value(Int32)"],
            kind: CompletionKind.CtorItem,
            relevance: 60
        )
        checkCompletionGroup(
            fixture,
            "Value",
            ["struct Value"],
            kind: CompletionKind.StructItem,
            relevance: 60
        )
    }

    @TestCase
    func stdPrintOverloadsShareOneItem() {
        let parsed =
            Fixture
                .parse(
                    #"
            //- /main.cj module=m package=m
            package m
            func use() { pr$0 }
            "#
                )
        let db = parsed.database(binaries: [stdCjoRead("std.core", stdCjo("std.core"))])
        let cursor = parsed.cursor.getOrThrow()
        let items = completionsAt(db, cursor.fileId, cursor.offset).getOrThrow().items
        let prints = items.filter { item => item.label == "print" }
        @Assert(prints.size == 1)
        @Expect(prints[0].overloadCount > 1)
        @Expect(completionDetails(db, cursor.fileId, cursor.offset, prints[0]).size, prints[0].overloadCount)
        @Expect(items.filter {item => item.label == "println"}.size, 1)
    }
}
