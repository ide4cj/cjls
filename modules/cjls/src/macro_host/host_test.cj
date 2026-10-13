package cjls.macro_host

import std.collection.*
import std.collection.concurrent.LinkedBlockingQueue
import std.env.{getTempDirectory, getVariable}
import std.fs.*
import std.io.ByteBuffer
import std.unittest.*
import std.unittest.testmacro.*
import stdx.log.*
import loupe.TextRange
import loupe.db.*
import loupe.fixture.*
import loupe.hir.{macroOutputOf, macroRequests, pendingMacroRequests, setMacroOutputsByKey}
import macro_server.*
import project_model.{hostCfg, sdkTarget}
import loupe.vfs.VfsPath
import rope.Rope

/**
 * The SDK the tests run on (`CANGJIE_HOME`).
 */
func testSdkPaths(): MacroServerPaths {
    let home = getVariable("CANGJIE_HOME") ?? throw IllegalStateException("CANGJIE_HOME names no SDK")
    MacroServerPaths.inSdk(Path(home), sdkTarget(hostCfg()).getOrThrow())
}

func testNumbers(): TokenNumbers {
    TokenNumbers.read(testSdkPaths().tokensInc).getOrThrow()
}

/**
 * A server whose macros give back their input, or fail, or are not reached; and the calls it was sent.
 */
class FakeExpander <: Expander {
    let calls = ArrayList<MacroCallData>()

    FakeExpander(let outcome!: ?CallOutcome = None) {}

    public func expand(call: MacroCallData): CallOutcome {
        calls.add(call)
        outcome ?? Answered(resultOf(MacroResultData(status: 1, tks: call.args)))
    }
}

/**
 * `data` as the server's answer reads: framed, through a connection.
 */
func resultOf(data: MacroResultData): MacroResult {
    let message = MacroMsgData(content: MsgContentData.AsMacroResult(data)).toBytes()
    let input = ByteBuffer()
    var size = UInt64(message.size)
    let length = Array<Byte>(8, repeat: 0)
    for (i in 0..8) {
        length[i] = UInt8(size & 0xff)
        size = size >> 8
    }
    input.write(length)
    input.write(message)
    MacroConnection(input, ByteBuffer()).expand(MacroCallData())
}

/**
 * `/main.cj` of package `m` holding `text`, with the workspace macro package `m.ms`.
 */
func macroFixture(text: String): (AnalysisDatabase, SourceFile, String) {
    let parsed = Fixture.parse(#"
        //- /main.cj module=m package=m
        "# + text + #"
        //- /ms/ms.cj module=m package=m.ms
        macro package m.ms
        import std.ast.*
        public macro M(attrs: Tokens, input: Tokens): Tokens { input }
        "#)
    let db = parsed.database()
    (db, db.sourceFile(parsed.file("/main.cj").fileId).getOrThrow(), parsed.file("/main.cj").text)
}

/**
 * `library` as the library of the macro package of the first call of `file`.
 */
func libraryOf(db: AnalysisDatabase, file: SourceFile, library: MacroLibrary): HashMap<VfsPath, MacroLibrary> {
    HashMap<VfsPath, MacroLibrary>([(macroRequests(db, file)[0].definition.pkg.dir(db), library)])
}

let MAIN = #"
        package m
        import m.ms.*
        @M[x]
        class C { let a = 1 }
"#

@Test
class MacroRoundTest {
    @TestCase
    func aCallIsSentAsItsMacroAndItsLibraryAndWhatItAnswersEndsItsRequest() {
        // arrange
        let (db, file, _) = macroFixture(MAIN)
        let libraries = libraryOf(db, file, MacroLibrary("/lib-macro_m.ms.so", 0))
        let expander = FakeExpander()

        // act
        let answers = expandAll(db, sendableRequests(db, [file], libraries), testNumbers(), expander)
        setMacroOutputsByKey(db, answers)

        // assert
        @Expect(expander.calls.size, 1)
        let call = expander.calls[0]
        @Expect(call.methodName, Some("macroCall_a_M_m_ms"))
        @Expect(call.packageName, Some("m.ms"))
        @Expect(call.libPath, Some("/lib-macro_m.ms.so"))
        @Expect(call.attrs.map {t => t.value ?? ""}, ["x"])
        @Expect(pendingMacroRequests(db, file).size, 0)
    }

    @TestCase
    func whatTheMacroGivesBackComesFromWhereTheSourceWroteIt() {
        // arrange
        let (db, file, source) = macroFixture(MAIN)
        let libraries = libraryOf(db, file, MacroLibrary("/lib", 0))
        let request = macroRequests(db, file)[0]

        // act
        setMacroOutputsByKey(db, expandAll(db, sendableRequests(db, [file], libraries), testNumbers(), FakeExpander()))

        // assert
        let expansion = macroOutputOf(db, request.call).getOrThrow().expansion.getOrThrow()
        let c = expansion.text.indexOf("C").getOrThrow()
        let anchor = source.indexOf("@M").getOrThrow()
        let written = source.indexOf("C {").getOrThrow() - anchor
        @Expect(expansion.originOf(TextRange(c, c + 1)), Some(SpanOrigin.FromSource(TextRange(written, written + 1))))
    }

    @TestCase
    func aCallWhoseLibraryIsNotBuiltIsNotSent() {
        // arrange
        let (db, file, _) = macroFixture(MAIN)

        // act
        let requests = sendableRequests(db, [file], HashMap<VfsPath, MacroLibrary>())

        // assert
        @Expect(requests.size, 0)
    }

    @TestCase
    func aCallIsNotSentUntilTheAnalysisHasTheStampOfItsLibrary() {
        // arrange
        let (db, file, _) = macroFixture(MAIN)
        let libraries = libraryOf(db, file, MacroLibrary("/lib", 5))

        // act
        let before = sendableRequests(db, [file], libraries).size
        macroRequests(db, file)[0].definition.pkg.setMacroLibrary(db).to(5)
        let after = sendableRequests(db, [file], libraries).size

        // assert
        @Expect(before, 0)
        @Expect(after, 1)
    }

    @TestCase
    func aCallThatFailsKeepsNoExpansionAndSaysSoOnTheCall() {
        // arrange
        let (db, file, _) = macroFixture(MAIN)
        let request = macroRequests(db, file)[0]
        let (_, layout) = callDataOf(request, "m.ms", "/lib", testNumbers())

        // act
        let failed = outputOf(request, layout, Answered(resultOf(MacroResultData(status: MACRO_FAILED))), testNumbers())
        let lost = outputOf(request, layout, Unanswered("it ran longer than 10 s"), testNumbers())

        // assert
        @Expect(failed.expansion.isNone())
        @Expect(failed.diagnostics, [MacroDiagnostic(MacroSeverity.MacroError, SpanOrigin.FromCall, "@M failed", "")])
        @Expect(lost.diagnostics[0].message, "@M was not expanded: it ran longer than 10 s")
        @Expect(lost.fingerprint, request.fingerprint)
    }
}

@Test
class WatchdogTest {
    @TestCase
    func whatRunsPastItsDeadlineIsEndedAndCannotBeDisarmed() {
        // arrange
        let fired = LinkedBlockingQueue<Int64>()
        let watchdog = Watchdog(NoopLogger())

        // act
        let id = watchdog.arm(Duration.Zero) {=> fired.add(1)}
        fired.remove()

        // assert
        @Expect(!watchdog.disarm(id))
        watchdog.stop()
    }

    @TestCase
    func whatEndsInTimeIsDisarmed() {
        // arrange
        let watchdog = Watchdog(NoopLogger())
        let id = watchdog.arm(Duration.hour) {=> throw IllegalStateException("fired")}

        // act
        let disarmed = watchdog.disarm(id)

        // assert
        @Expect(disarmed)
        watchdog.stop()
    }
}

let TOY_MACROS = ##"
macro package toy.ms

import std.ast.*

public macro Same(input: Tokens): Tokens {
    input
}

public macro Spin(input: Tokens): Tokens {
    var n = 0
    while (n >= 0) {
        n = (n + 1) % 2
    }
    input
}
"##

/**
 * A macro package built by the SDK's cjc, run in its server: what D104 wires together.
 */
@Test
class GuardedServerTest {
    func built(): (MacroServerPaths, String) {
        let paths = testSdkPaths()
        let root = Directory.createTemp(getTempDirectory())
        let dir = root.join("src").join("ms")
        Directory.create(dir, recursive: true)
        File.writeTo(dir.join("ms.cj"), TOY_MACROS.toArray())
        let toolchain = SdkToolchain(paths)
        let built = MacroBuilder(root.join("macro-build"), toolchain.version().getOrThrow(), toolchain).build(
            [BuildUnit("toy.ms", "toy", dir, true, [], [])]).getOrThrow()
        match (built.get("toy.ms")) {
            case Some(Built(library, _)) => (paths, library.toString())
            case Some(NotBuilt(reason)) => throw IllegalStateException(reason)
            case None => throw IllegalStateException("nothing built")
        }
    }

    func call(name: String, library: String, numbers: TokenNumbers): MacroCallData {
        MacroCallData(
            id: IdInfoData(name: name, pos: PositionData(fileId: 1, line: 1, column: 2)),
            args: macroTokens("class A {}", numbers, PositionData(fileId: 1, line: 2, column: 1)),
            methodName: methodNameOf(name, "toy.ms", false),
            packageName: "toy.ms",
            libPath: library,
            begin: PositionData(fileId: 1, line: 1, column: 1),
            end: PositionData(fileId: 1, line: 2, column: 11)
        )
    }

    @TestCase
    func aMacroOfTheWorkspaceBuiltByCjcIsExpandedByTheServer() {
        // arrange
        let (paths, library) = built()
        let numbers = testNumbers()
        let server = GuardedServer(paths, Duration.minute, NoopLogger())

        // act
        let outcome = server.expand(call("Same", library, numbers))
        server.close()

        // assert
        match (outcome) {
            case Answered(result) =>
                @Expect(result.status != MACRO_FAILED)
                @Expect(printMacroTokens(result.tks, numbers).text, "class A { }")
            case Unanswered(reason) => @Fail(reason)
        }
    }

    @TestCase
    func aMacroThatNeverReturnsCostsItsCallAndTheNextIsAnswered() {
        // arrange
        let (paths, library) = built()
        let numbers = testNumbers()
        let server = GuardedServer(paths, Duration.second, NoopLogger())

        // act
        let spun = server.expand(call("Spin", library, numbers))
        let next = server.expand(call("Same", library, numbers))
        server.close()

        // assert
        match (spun) {
            case Unanswered(reason) => @Expect(reason, "it ran longer than 1 s")
            case Answered(_) => @Fail("Spin was answered")
        }
        match (next) {
            case Answered(result) => @Expect(result.status != MACRO_FAILED)
            case Unanswered(reason) => @Fail(reason)
        }
    }
}

@Test
class DirNameTest {
    @TestCase
    func aCompilersVersionNamesItsDirectory() {
        // act
        let name = dirNameOf("Cangjie Compiler: 1.3.0-alpha.20261002001050 (cjnative)\nTarget: x86_64-unknown-linux-gnu\n")

        // assert
        @Expect(name, "1.3.0-alpha.20261002001050-cjnative")
    }
}

/**
 * A server whose macros give back their input, which makes an edit on its first call.
 */
class EditingExpander <: Expander {
    let calls = ArrayList<MacroCallData>()

    EditingExpander(let edit: () -> Unit) {}

    public func expand(call: MacroCallData): CallOutcome {
        calls.add(call)
        if (calls.size == 1) {
            edit()
        }
        Answered(resultOf(MacroResultData(status: 1, tks: call.args)))
    }
}

let USES = #"
        package m
        import m.ms.*
        @M
        class C { let a = 1 }
"#

/**
 * `/a.cj` and `/b.cj` of package `m`, each holding `USES`, with the workspace macro package `m.ms` built.
 */
func twoFilesFixture(): (AnalysisDatabase, SourceFile, SourceFile, HashMap<VfsPath, MacroLibrary>) {
    let parsed = Fixture.parse(#"
        //- /a.cj module=m package=m
        "# + USES + #"
        //- /b.cj module=m package=m
        "# + USES + #"
        //- /ms/ms.cj module=m package=m.ms
        macro package m.ms
        import std.ast.*
        public macro M(input: Tokens): Tokens { input }
        "#)
    let db = parsed.database()
    let a = db.sourceFile(parsed.file("/a.cj").fileId).getOrThrow()
    (db, a, db.sourceFile(parsed.file("/b.cj").fileId).getOrThrow(), libraryOf(db, a, MacroLibrary("/lib", 0)))
}

@Test
class MacroRoundEditTest {
    @TestCase
    func anEditMidwayEndsTheRoundAndWhatWasAnsweredBeforeItIsKept() {
        // arrange
        let (db, a, b, libraries) = twoFilesFixture()
        let snapshot = db.snapshot()
        let requests = sendableRequests(snapshot, [a, b], libraries)
        let expander = EditingExpander({=> db.setFileText(b.fileId(db), Rope(USES.replace("a = 1", "b = 2")))})

        // act
        let answers = expandAll(snapshot, requests, testNumbers(), expander)
        setMacroOutputsByKey(db, answers)

        // assert
        @Expect(expander.calls.size, 1)
        @Expect(pendingMacroRequests(db, a).size, 0)
        @Expect(pendingMacroRequests(db, b).size, 1)
    }

    @TestCase
    func anAnswerToARequestTheEditChangedIsAskedAgain() {
        // arrange
        let (db, a, b, libraries) = twoFilesFixture()
        let snapshot = db.snapshot()
        let requests = sendableRequests(snapshot, [a, b], libraries)
        let expander = EditingExpander({=> db.setFileText(a.fileId(db), Rope(USES.replace("a = 1", "b = 2")))})

        // act
        let answers = expandAll(snapshot, requests, testNumbers(), expander)
        setMacroOutputsByKey(db, answers)

        // assert
        @Expect(answers.size, 1)
        @Expect(pendingMacroRequests(db, a).size, 1)
    }

    @TestCase
    func theRequestsOfTheOpenFilesAreSentFirst() {
        // arrange
        let (db, a, b, libraries) = twoFilesFixture()

        // act
        let requests = sendableRequests(db, [a, b], libraries, isOpen: {file => file.fileId(db).index == b.fileId(db).index})

        // assert
        @Expect(requests.map {one => one[0].fileId(db).index}, [b.fileId(db).index, a.fileId(db).index])
    }
}
