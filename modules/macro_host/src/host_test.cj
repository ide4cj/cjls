package macro_host

import std.collection.*
import std.collection.concurrent.LinkedBlockingQueue
import std.env.{getTempDirectory, getVariable, getVariables}
import std.fs.*
import std.io.ByteBuffer
import std.sync.Mutex
import std.unittest.*
import std.unittest.testmacro.*
import stdx.log.*
import loupe.{hoverAt, TextRange}
import loupe.db.*
import loupe.fixture.*
import loupe.hir.{expandedCalls, macroExpansion, macroOutputOf, MacroPackage, macroRequests, pendingMacroRequests,
    setMacroOutputsByKey}
import macro_server.*
import project_model.{hostCfg, sdkTarget}
import rope.Rope

/**
 * The SDK the tests run on (`CANGJIE_HOME`).
 */
func testSdkPaths(): MacroServerPaths {
    let home = getVariable("CANGJIE_HOME") ?? throw IllegalStateException("CANGJIE_HOME names no SDK")
    MacroServerPaths.inSdk(Path(home), sdkTarget(hostCfg()).getOrThrow())
}

/**
 * How the SDK the tests run on numbers its token kinds, found as the server finds it (`tokenNumbersOf`): an SDK of
 * the window that ships no `Tokens.inc` (1.0.5) runs these tests too (#310).
 */
func testNumbers(): TokenNumbers {
    let paths = testSdkPaths()
    tokenNumbersOf(paths, SdkToolchain(paths).version().getOrThrow()).getOrThrow()
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
 * `library` as the library of the workspace macro package of the first call of `file`.
 */
func libraryOf(db: AnalysisDatabase, file: SourceFile, library: MacroLibrary): HashMap<Package, MacroLibrary> {
    match (macroRequests(db, file)[0].definition.pkg) {
        case MacroPackage.WorkspacePackage(pkg) => HashMap<Package, MacroLibrary>([(pkg, library)])
        case _ => throw IllegalStateException("the first call of the file is not of a workspace macro")
    }
}

const MAIN = #"
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
    func aCallInABodyIsSentWithItsArgumentsAndItsAnswerComesFromWhereTheyAre() {
        // arrange
        let (db, file, source) = macroFixture(#"
        package m
        import m.ms.*
        func f(): Int64 { @M[x](1 + 2) }
"#)
        let libraries = libraryOf(db, file, MacroLibrary("/lib", 0))
        let expander = FakeExpander()
        let request = macroRequests(db, file)[0]

        // act
        setMacroOutputsByKey(db, expandAll(db, sendableRequests(db, [file], libraries), testNumbers(), expander))

        // assert
        @Expect(expander.calls.size, 1)
        @Expect(expander.calls[0].args.map {t => t.value ?? ""}, ["1", "+", "2"])
        @Expect(pendingMacroRequests(db, file).size, 0)
        let expansion = macroOutputOf(db, request.call).getOrThrow().expansion.getOrThrow()
        let two = expansion.text.indexOf("2").getOrThrow()
        let written = source.indexOf("2)").getOrThrow() - source.indexOf("func").getOrThrow()
        @Expect(expansion.originOf(TextRange(two, two + 1)), Some(SpanOrigin.FromSource(TextRange(written, written + 1))))
    }

    /**
     * cjc gives a macro no line break before the first token of its attribute or of its input in parentheses, a
     * comment's included, and those after the last (Optics's `@Optic[` fields on lines of their own).
     */
    @TestCase
    func anAttributeAndArgumentsAreSentWithoutTheLineBreaksTheyStartWithAsCjcGivesThem() {
        // arrange
        let (db, file, _) = macroFixture(#"
        package m
        import m.ms.*
        func f(): Int64 {
            @M[ // the fields

                x
            ](

                1
            )
        }
"#)
        let libraries = libraryOf(db, file, MacroLibrary("/lib", 0))
        let expander = FakeExpander()

        // act
        expandAll(db, sendableRequests(db, [file], libraries), testNumbers(), expander)

        // assert
        @Expect(expander.calls[0].attrs.map {t => t.value ?? ""}, ["x", "\n"])
        @Expect(expander.calls[0].args.map {t => t.value ?? ""}, ["1", "\n"])
    }

    @TestCase
    func aCallInABodyKeepsWhereItsArgumentsAreWhenTheyStartOnALineOfTheirOwn() {
        // arrange
        let (db, file, source) = macroFixture(#"
        package m
        import m.ms.*
        func f(): Int64 { @M[x](
            1 + 2) }
"#)
        let libraries = libraryOf(db, file, MacroLibrary("/lib", 0))
        let request = macroRequests(db, file)[0]

        // act
        setMacroOutputsByKey(db, expandAll(db, sendableRequests(db, [file], libraries), testNumbers(), FakeExpander()))

        // assert
        let expansion = macroOutputOf(db, request.call).getOrThrow().expansion.getOrThrow()
        let two = expansion.text.indexOf("2").getOrThrow()
        let written = source.indexOf("2)").getOrThrow() - source.indexOf("func").getOrThrow()
        @Expect(expansion.originOf(TextRange(two, two + 1)), Some(SpanOrigin.FromSource(TextRange(written, written + 1))))
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
        let requests = sendableRequests(db, [file], HashMap<Package, MacroLibrary>())

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
        if (let MacroPackage.WorkspacePackage(pkg) <- macroRequests(db, file)[0].definition.pkg) {
            pkg.setMacroLibrary(db).to(5)
        }
        let after = sendableRequests(db, [file], libraries).size

        // assert
        @Expect(before, 0)
        @Expect(after, 1)
    }

    @TestCase
    func aCallOfStdIsSentWithTheLibraryTheSdkShipsWhateverIsBuilt() {
        // arrange
        let (db, file) = deriveFixture()
        let expander = FakeExpander()

        // act
        let answers = expandAll(db, sendableRequests(db, [file], HashMap<Package, MacroLibrary>(),
            stdLibrary: {pkg => "/sdk/libcangjie-${pkg}.so"}), testNumbers(), expander)

        // assert
        @Expect(expander.calls.size, 1)
        let call = expander.calls[0]
        @Expect(call.methodName, Some("macroCall_a_Derive_std_deriving"))
        @Expect(call.packageName, Some("std.deriving"))
        @Expect(call.libPath, Some("/sdk/libcangjie-std.deriving.so"))
        @Expect(answers.size, 1)
    }

    @TestCase
    func aCallOfStdWhoseLibraryTheSdkLacksIsNotSent() {
        // arrange
        let (db, file) = deriveFixture()

        // act
        let requests = sendableRequests(db, [file], HashMap<Package, MacroLibrary>(), stdLibrary: {_ => None})

        // assert
        @Expect(requests.size, 0)
    }

    @TestCase[text in [None<String>, Some("")], row in [
        (0i32, MacroSeverity.MacroError, "@M reported an error"),
        (1i32, MacroSeverity.MacroWarning, "@M reported a warning")
    ]]
    func anEmptyDiagnosticHasTheMacrosNameAndSeverityAsItsMessage(text: ?String, row: (Int32, MacroSeverity, String)) {
        // arrange
        let (level, severity, message) = row
        let (db, file, _) = macroFixture(MAIN)
        let request = macroRequests(db, file)[0]
        let (_, layout) = callDataOf(request, "m.ms", "/lib", testNumbers())

        // act
        let output = outputOf(request, layout, Answered(resultOf(MacroResultData(status: 1,
            diags: [DiagnosticData(diagSeverity: level, errorMessage: text, mainHint: text)]))), testNumbers())

        // assert
        @Expect(output.diagnostics, [MacroDiagnostic(severity, None, message, "")])
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

/**
 * `/main.cj` of package `m` deriving `Equatable` for a class with std's `@Derive`, std's `.cjo`s among the packages.
 */
func deriveFixture(): (AnalysisDatabase, SourceFile) {
    let parsed = Fixture.parse(#"
        //- /main.cj module=m package=m
        package m
        import std.deriving.*
        @Derive[Equatable]
        class A { let x: Int64 = 1 }
        "#)
    let db = parsed.database(binaries: [stdCjoRead("std.core", stdCjo("std.core")),
        stdCjoRead("std.deriving", stdCjo("std.deriving"))])
    (db, db.sourceFile(parsed.file("/main.cj").fileId).getOrThrow())
}

/**
 * Deadlines a test fires by hand, whatever time passed: each armed one's id is put in `armed`.
 */
class HandFiredDeadlines <: Deadlines {
    let armed = LinkedBlockingQueue<Int64>()
    private let lock = Mutex()
    // guarded by `lock`
    private let pending = HashMap<Int64, () -> Unit>()
    private var count = 0

    public func arm(_: Duration, fire: () -> Unit): Int64 {
        let id = synchronized(lock) {
            count++
            pending.add(count, fire)
            count
        }
        armed.add(id)
        id
    }

    public func disarm(id: Int64): Bool {
        synchronized(lock) {
            pending.remove(id).isSome()
        }
    }

    public func stop(): Unit {}

    /**
     * Runs what `id` was armed with, unless disarmed: it cannot be disarmed after.
     */
    func fire(id: Int64): Unit {
        let fire = synchronized(lock) {
            pending.remove(id)
        }
        if (let Some(it) <- fire) {
            it()
        }
    }
}

const TOY_MACROS = ##"
macro package toy.ms

import std.ast.*

public macro Id(baseType: Tokens, size: Tokens): Tokens {
    let typeTokens = Token(IDENTIFIER, "${baseType}${size}").toTokens()
    quote(func id(v: $typeTokens): $typeTokens { v })
}

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
 * `TOY_MACROS` as the package `toy.ms`, built by `toolchain` into a fresh directory.
 */
func buildToyMacros(toolchain: SdkToolchain): BuiltLibrary {
    let root = Directory.createTemp(getTempDirectory())
    let dir = root.join("src").join("ms")
    Directory.create(dir, recursive: true)
    File.writeTo(dir.join("ms.cj"), TOY_MACROS.toArray())
    let built = MacroBuilder(root.join("macro-build"), toolchain.version().getOrThrow(), toolchain).build(
        [BuildUnit("toy.ms", "toy", dir, true, [], [])]).getOrThrow()
    built.get("toy.ms") ?? NotBuilt("nothing built")
}

/**
 * What an editor starts the server under on macOS: not `envsetup`'s environment, so no `SDKROOT`.
 */
@When[os == "macOS"]
@Test
class SdkToolchainMacosTest {
    @TestCase
    func aMacroPackageIsLinkedWhereTheEnvironmentNamesNoSdkroot() {
        // arrange
        let variables = getVariables().filter {variable => variable[0] != "SDKROOT"}
        let toolchain = SdkToolchain(testSdkPaths(), variables: variables)

        // act
        let built = buildToyMacros(toolchain)

        // assert
        match (built) {
            case Built(library, _) => @Expect(exists(library))
            case NotBuilt(reason) => @Fail(reason)
        }
    }
}

/**
 * A macro package built by the SDK's cjc, run in its server: what D104 wires together.
 */
@Test
class GuardedServerTest {
    func built(): (MacroServerPaths, String) {
        let paths = testSdkPaths()
        match (buildToyMacros(SdkToolchain(paths))) {
            case Built(library, _) => (paths, library.toString())
            case NotBuilt(reason) => throw IllegalStateException(reason)
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
    func anUnloadableLibraryDoesNotRestartTheSdkServerForEveryCall() {
        // arrange
        let (paths, library) = built()
        let numbers = testNumbers()
        let host = RetryTestHost()
        let server = GuardedServer(Duration.minute, host, HandFiredDeadlines(), {=>
            host.starts++
            SdkMacroSession(startMacroServer(paths))
        }, {=> host.clock})

        // act
        for (_ in 0..100) {
            server.expand(call("Same", "${library}.missing", numbers))
        }
        let healthy = server.expand(call("Same", library, numbers))
        server.close()

        // assert
        @Expect(host.starts, 4)
        @Expect(host.messages.size, 2)
        match (healthy) {
            case Answered(result) => @Expect(result.status != MACRO_FAILED)
            case Unanswered(reason) => @Fail(reason)
        }
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
    func aDeriveOfStdIsExpandedFromTheSdksLibraryAndItsOutputWithBodiesReplacesTheAnalysissOwn() {
        // arrange
        let paths = testSdkPaths()
        let numbers = testNumbers()
        let (db, file) = deriveFixture()
        let server = GuardedServer(paths, Duration.minute, NoopLogger())
        let call = expandedCalls(db, file)[0]
        let own = macroExpansion(db, call)

        // act
        let requests = sendableRequests(db, [file], HashMap<Package, MacroLibrary>(),
            stdLibrary: {pkg => paths.stdMacroLibrary(pkg).map {path => path.toString()}})
        setMacroOutputsByKey(db, expandAll(db, requests, numbers, server))
        server.close()
        let served = macroExpansion(db, call)

        // assert
        @Expect(requests.size, 1)
        @Expect(expandedCalls(db, file), [call])
        @Expect(own.replaces, false)
        @Expect(served.replaces, true)
        @Expect(served.text.replace("\r\n", "\n").contains("public operator func ==(other: A): Bool {"), true)
        @Expect(pendingMacroRequests(db, file).size, 0)
    }

    @TestCase
    func aBuiltKeywordIdentifierKeepsItsPrimitiveType() {
        // arrange
        let (paths, library) = built()
        let fixture = Fixture.parse(trimIndent(#"
            //- /main.cj module=toy package=toy
            package toy
            import toy.ms.*
            @Id[Int](8)
            main() {
                let value = id(1)
                $0value
            }
            //- /ms/ms.cj module=toy package=toy.ms
            "#) + TOY_MACROS)
        let db = fixture.database()
        let file = db.sourceFile(fixture.file("/main.cj").fileId).getOrThrow()
        let libraries = libraryOf(db, file, MacroLibrary(library, 0))
        let server = GuardedServer(paths, Duration.minute, NoopLogger())

        // act
        setMacroOutputsByKey(db, expandAll(db, sendableRequests(db, [file], libraries), testNumbers(), server))
        server.close()
        let expansion = macroExpansion(db, expandedCalls(db, file)[0])
        let cursor = fixture.cursor.getOrThrow()
        let hover = hoverAt(db, cursor.fileId, cursor.offset).getOrThrow()

        // assert
        @Expect(expansion.text, "func id(v: Int8): Int8 { v }")
        @Expect(hover.items.map {item => item.code}, ["let value: Int8"])
    }

    @TestCase
    func aMacroThatNeverReturnsCostsItsCallAndTheNextIsAnswered() {
        // arrange
        let (paths, library) = built()
        let numbers = testNumbers()
        let deadlines = HandFiredDeadlines()
        let server = GuardedServer(paths, Duration.second, NoopLogger(), deadlines)

        // act - Spin's deadline fired while it runs, which it never stops doing; Same's never
        let spinning = spawn {server.expand(call("Spin", library, numbers))}
        deadlines.fire(deadlines.armed.remove())
        let spun = spinning.get()
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

const USES = #"
        package m
        import m.ms.*
        @M
        class C { let a = 1 }
"#

/**
 * `/a.cj` and `/b.cj` of package `m`, each holding `USES`, with the workspace macro package `m.ms` built.
 */
func twoFilesFixture(): (AnalysisDatabase, SourceFile, SourceFile, HashMap<Package, MacroLibrary>) {
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
