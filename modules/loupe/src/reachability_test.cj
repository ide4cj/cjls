package loupe

import std.unittest.*
import std.unittest.testmacro.*
import loupe.fixture.*
import loupe.hir.*
import loupe.db.*
import ginkgo.TextRange

func auditFixture(source: String, limit!: Int64 = 100000): Array<TrackedReachability> {
    let fixture =
        Fixture.parse("//- /main.cj module=loupe package=loupe.vfs\n${trimIndent(source)}")
    let db = fixture.database()
    let files = fixture.files.map { file => db.sourceFile(file.fileId).getOrThrow() }
    trackedReachability(db, files, maxNodes: limit)
}

func witnessLengths(answer: TrackedReachability): Array<Int64> {
    answer.witnesses.map { witness => witness.callCount }
}

@Test
class TrackedReachabilityTest {
    @TestCase
    func anUnexpandedMacroDoesNotExecuteItsTokenArguments() {
        let found =
            auditFixture(
                #"
            package loupe.vfs
            func readFile(): Unit {}
            @CalcaTracked
            func root(): Unit { @Unknown(readFile()) }
            "#
            )
        @Expect(found[0].witnesses.size, 0)
        @Expect(found[0].boundaries.any { one => one.reason == "body macro has no readable expansion" }, true)
    }

    @TestCase
    func incrementingAPropertyInvokesItsSetter() {
        let found =
            auditFixture(
                #"
            package loupe.vfs
            func readFile(): Unit {}
            struct Box {
                public prop value: Int64 {
                    get() { 0 }
                    set(value) { readFile() }
                }
            }
            @CalcaTracked
            func root(box: Box): Unit { box.value++ }
            "#
            )
        @Expect(found[0].status("loupe.vfs.readFile"), "reachable")
    }

    @TestCase
    func anOpenPropertyRetainsItsDispatchFrontier() {
        let found =
            auditFixture(
                #"
            package loupe.vfs
            open class Box {
                public open prop value: Int64 { get() { 0 } }
            }
            @CalcaTracked
            func root(box: Box): Unit { let value = box.value }
            "#
            )
        @Expect(found[0].boundaries.any { one => one.reason == "virtual receiver dispatch is not closed" }, true)
    }

    @TestCase
    func recognizesTheActualSdkClockWithItsDefaultTimezone() {
        let fixture =
            Fixture
                .parse(
                    #"
            package app
            import std.time.DateTime
            @CalcaTracked
            func root(): Unit { let time = DateTime.now() }
            "#
                )
        let db =
            fixture
                .database(
                    binaries: [
                        stdCjoRead("std.core", stdCjo("std.core")),
                        stdCjoRead("std.time", stdCjo("std.time"))
                    ]
                )
        let file = db.sourceFile(fixture.files[0].fileId).getOrThrow()
        let found = trackedReachability(db, [file])
        @Expect(found[0].status("std.time.DateTime.now"), "reachable")
        @Expect(witnessLengths(found[0]), [1])
    }

    @TestCase
    func aTargetsDefaultArgumentDoesNotMakeItsCallFree() {
        let found =
            auditFixture(
                #"
            package loupe.vfs
            func readFile(value: Int64 = 0): Unit {}
            @CalcaTracked
            func root(): Unit { readFile() }
            "#
            )
        @Expect(found[0].status("loupe.vfs.readFile"), "reachable")
        @Expect(witnessLengths(found[0]), [1])
    }

    @TestCase
    func choosesTheShorterPathEvenWhenTheLongerOneIsWrittenFirst() {
        let found =
            auditFixture(
                #"
            package loupe.vfs
            func readFile(): Unit {}
            func longer(): Unit { middle() }
            func middle(): Unit { readFile() }
            @CalcaTracked
            func root(): Unit { longer(); readFile() }
            "#
            )
        @Expect(found.size, 1)
        @Expect(found[0].status("loupe.vfs.readFile"), "reachable")
        @Expect(witnessLengths(found[0]), [1])
    }

    @TestCase
    func cyclesTerminateAndDoNotLoseAnExitToATarget() {
        let found =
            auditFixture(
                #"
            package loupe.vfs
            func readRoots(): Unit {}
            func a(): Unit { b() }
            func b(): Unit { a(); readRoots() }
            @CalcaTracked
            func root(): Unit { a() }
            "#
            )
        @Expect(found[0].status("loupe.vfs.readRoots"), "reachable")
        @Expect(witnessLengths(found[0]), [3])
    }

    @TestCase
    func constructingAClosureDoesNotExecuteIt() {
        let found =
            auditFixture(
                #"
            package loupe.vfs
            func readFile(): Unit {}
            @CalcaTracked
            func root(): Unit { let unused = { => readFile() } }
            "#
            )
        @Expect(found[0].witnesses.size, 0)
        @Expect(found[0].status("loupe.vfs.readFile"), "unknown")
    }

    @TestCase
    func invokingALocalClosureDoesExecuteIt() {
        let found =
            auditFixture(
                #"
            package loupe.vfs
            func readFile(): Unit {}
            @CalcaTracked
            func root(): Unit { let action = { => readFile() }; action() }
            "#
            )
        @Expect(found[0].status("loupe.vfs.readFile"), "reachable")
        @Expect(witnessLengths(found[0]), [2])
    }

    @TestCase
    func callbackBindingsRemainSpecificToTheirCallers() {
        let found =
            auditFixture(
                #"
            package loupe.vfs
            func readFile(): Unit {}
            func pure(): Unit {}
            func apply(action: () -> Unit): Unit { action() }
            @CalcaTracked
            func withEffect(): Unit { apply(readFile) }
            @CalcaTracked
            func withoutEffect(): Unit { apply(pure) }
            "#
            )
        @Expect(found.size, 2)
        @Expect(found[0].status("loupe.vfs.readFile"), "reachable")
        @Expect(witnessLengths(found[0]), [2])
        @Expect(found[1].witnesses.size, 0)
    }

    @TestCase
    func aCallbackNotInvokedByItsCalleeIsNotAnEdge() {
        let found =
            auditFixture(
                #"
            package loupe.vfs
            func readFile(): Unit {}
            func ignore(action: () -> Unit): Unit {}
            @CalcaTracked
            func root(): Unit { ignore(readFile) }
            "#
            )
        @Expect(found[0].witnesses.size, 0)
    }

    @TestCase
    func anUnboundCallbackIsAFrontierAndNotAnAbsenceProof() {
        let found =
            auditFixture(
                #"
            package loupe.vfs
            @CalcaTracked
            func root(action: () -> Unit): Unit { action() }
            "#
            )
        @Expect(found[0].status("loupe.vfs.readFile"), "unknown")
        @Expect(found[0].boundaries.any { one => one.reason == "unresolved call or callback binding" }, true)
    }

    @TestCase
    func defaultExpressionsAreEvaluatedOnlyForOmittedArguments() {
        let found =
            auditFixture(
                #"
            package loupe.vfs
            func readFile(): Int64 { 0 }
            func take(value: Int64 = readFile()): Unit {}
            @CalcaTracked
            func omitted(): Unit { take() }
            @CalcaTracked
            func supplied(): Unit { take(0) }
            "#
            )
        @Expect(found[0].status("loupe.vfs.readFile"), "reachable")
        @Expect(witnessLengths(found[0]), [1])
        @Expect(found[1].witnesses.size, 0)
    }

    @TestCase
    func matchesAllSevenFamiliesByResolvedDeclarationIdentity() {
        let found =
            auditFixture(
                #"
            package loupe.vfs
            import std.fs.touch as fileTouch
            import std.env.touch as envTouch
            import std.random.touch as randomTouch
            import std.time.DateTime
            func readFile(): Unit {}
            func readRoots(): Unit {}
            func readCjoFiles(): Unit {}
            @CalcaTracked func fs(): Unit { fileTouch() }
            @CalcaTracked func env(): Unit { envTouch() }
            @CalcaTracked func random(): Unit { randomTouch() }
            @CalcaTracked func clock(): Unit { let time = DateTime.now }
            @CalcaTracked func file(): Unit { readFile() }
            @CalcaTracked func roots(): Unit { readRoots() }
            @CalcaTracked func cjo(): Unit { readCjoFiles() }
            //- /fs.cj module=std package=std.fs
            package std.fs
            public func touch(): Unit {}
            //- /env.cj module=std package=std.env
            package std.env
            public func touch(): Unit {}
            //- /random.cj module=std package=std.random
            package std.random
            public func touch(): Unit {}
            //- /time.cj module=std package=std.time
            package std.time
            public struct DateTime {
                public static prop now: Int64 { get() { 0 } }
            }
            "#
            )
        @Expect(found.size, 7)
        for (i in 0..found.size) {
            @Expect(found[i].witnesses.size, 1)
        }
        @Expect(found[0].status("std.fs.*"), "reachable")
        @Expect(found[1].status("std.env.*"), "reachable")
        @Expect(found[2].status("std.random.*"), "reachable")
        @Expect(found[3].status("std.time.DateTime.now"), "reachable")
        @Expect(found[4].status("loupe.vfs.readFile"), "reachable")
        @Expect(found[5].status("loupe.vfs.readRoots"), "reachable")
        @Expect(found[6].status("loupe.vfs.readCjoFiles"), "reachable")
    }

    @TestCase
    func similarlyNamedClocksAndLocalFunctionsDoNotMatch() {
        let found =
            auditFixture(
                #"
            package loupe.vfs
            import std.time.*
            func random(): Unit {}
            @CalcaTracked
            func root(): Unit { DateTime.nowUTC(); MonoTime.now(); random() }
            //- /time.cj module=std package=std.time
            package std.time
            public struct DateTime { public static func nowUTC(): Unit {} }
            public struct MonoTime { public static func now(): Unit {} }
            "#
            )
        @Expect(found[0].witnesses.size, 0)
    }

    @TestCase
    func followsTheSelectedOverloadRatherThanEveryNameCandidate() {
        let found =
            auditFixture(
                #"
            package loupe.vfs
            func readFile(): Unit {}
            func select(value: Int64): Unit {}
            func select(value: Bool): Unit { readFile() }
            @CalcaTracked func pure(): Unit { select(1) }
            @CalcaTracked func effect(): Unit { select(true) }
            "#
            )
        @Expect(found[0].witnesses.size, 0)
        @Expect(found[1].status("loupe.vfs.readFile"), "reachable")
        @Expect(witnessLengths(found[1]), [2])
    }

    @TestCase
    func aDefaultCallbackIsBoundAndInvoked() {
        let found =
            auditFixture(
                #"
            package loupe.vfs
            func readFile(): Unit {}
            func apply(action: () -> Unit = readFile): Unit { action() }
            @CalcaTracked
            func root(): Unit { apply() }
            "#
            )
        @Expect(found[0].status("loupe.vfs.readFile"), "reachable")
        @Expect(witnessLengths(found[0]), [2])
    }

    @TestCase
    func aPropertyReadDoesNotExecuteItsSetter() {
        let found =
            auditFixture(
                #"
            package loupe.vfs
            func readFile(): Unit {}
            struct Box {
                public prop value: Int64 {
                    get() { 0 }
                    set(value) { readFile() }
                }
            }
            @CalcaTracked
            func root(box: Box): Unit { let value = box.value }
            "#
            )
        @Expect(found[0].witnesses.size, 0)
    }

    @TestCase
    func aPropertyWriteExecutesItsSetter() {
        let found =
            auditFixture(
                #"
            package loupe.vfs
            func readFile(): Unit {}
            struct Box {
                public prop value: Int64 {
                    get() { 0 }
                    set(value) { readFile() }
                }
            }
            @CalcaTracked
            func root(box: Box): Unit { box.value = 1 }
            "#
            )
        @Expect(found[0].status("loupe.vfs.readFile"), "reachable")
        @Expect(witnessLengths(found[0]), [2])
    }

    @TestCase
    func budgetExhaustionCannotBecomeANegativeAnswer() {
        let found =
            auditFixture(
                #"
            package loupe.vfs
            func readFile(): Unit {}
            func helper(): Unit { readFile() }
            @CalcaTracked
            func root(): Unit { helper() }
            "#,
                limit: 1
            )
        @Expect(found[0].status("loupe.vfs.readFile"), "unknown")
        @Expect(found[0].boundaries.any { one => one.reason == "node budget exhausted" }, true)
    }

    @TestCase
    func followsServedWrapperBodiesAndCanCloseAPureGraph() {
        let fixture =
            Fixture
                .parse(
                    #"
            //- /main.cj module=m package=m
            package m
            import m.ms.CalcaTracked
            @CalcaTracked
            func root(): Unit {}
            //- /ms.cj module=m package=m.ms
            macro package m.ms
            public macro CalcaTracked(input: Tokens): Tokens { input }
            "#
                )
        let db = fixture.database()
        let file = db.sourceFile(fixture.files[0].fileId).getOrThrow()
        let output = "func root(): Unit {}"
        answer(
            db,
            file,
            "CalcaTracked",
            output,
            [
                MappedSpan(
                    TextRange(0, output.size),
                    SpanOrigin.FromSource(TextRange(14, 14 + output.size))
                )
            ]
        )
        let found = trackedReachability(db, [file])
        @Expect(found.size, 1)
        @Expect(found[0].status("std.fs.*"), "not_reachable")
    }

    @TestCase
    func aServedWrapperCanIntroduceATargetAbsentFromTheWrittenBody() {
        let fixture =
            Fixture
                .parse(
                    #"
            //- /main.cj module=loupe package=loupe.vfs
            package loupe.vfs
            import loupe.ms.CalcaTracked
            func readRoots(): Unit {}
            @CalcaTracked
            func root(): Unit {}
            //- /ms.cj module=loupe package=loupe.ms
            macro package loupe.ms
            public macro CalcaTracked(input: Tokens): Tokens { input }
            "#
                )
        let db = fixture.database()
        let file = db.sourceFile(fixture.files[0].fileId).getOrThrow()
        let copied = "func root(): Unit "
        let output = "${copied}{ readRoots() }"
        answer(
            db,
            file,
            "CalcaTracked",
            output,
            [
                MappedSpan(
                    TextRange(0, copied.size),
                    SpanOrigin.FromSource(TextRange(14, 14 + copied.size))
                ),
                MappedSpan(TextRange(copied.size, output.size), SpanOrigin.FromCall)
            ]
        )
        let found = trackedReachability(db, [file])
        @Expect(found[0].status("loupe.vfs.readRoots"), "reachable")
        @Expect(witnessLengths(found[0]), [1])
        @Expect(found[0].witnesses[0].calls[0].source.def.file(db), ItemFile.Expansion(requestFor(db, file, "CalcaTracked").call))
    }
}
