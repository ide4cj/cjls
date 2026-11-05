package loupe

import std.collection.ArrayList
import std.unittest.*
import std.unittest.testmacro.*
import ginkgo.TextRange
import loupe.db.*
import loupe.fixture.*
import loupe.hir.{macroExpansion, macroRequests, setMacroOutputs}

/**
 * Pinned SDK 1.3.0-alpha.20261102001050's --debug-macro output for an empty @Test class.
 * The real-server gate checks the live SDK separately; this records the replacement shape.
 */
const SERVED_EMPTY_TEST =
    #"
    @Attribute[TEST_GENERATED] class C <: TestClass {
        public override func asTestSuite(): TestSuite {

            let suiteConfiguration = classConfiguration()
            let suiteBuilder = TestSuite.builder("C").configure(suiteConfiguration)
            return suiteBuilder.build()
        }
        init() {
        }
        private func classConfiguration(): Configuration {
            let configuration = Configuration()

            return configuration
        }
        private func inheritedFromClassAnnotatedByTestTemplate < T >(): TestSuite where T <: TestClass {
            throw Exception("Unreachable code")
        }
    }


    interface TestPackageExtension_C {
        func registerC(): Unit
    }
    extend TestPackage <: TestPackageExtension_C {
        @Attribute[TEST_REGISTER]
        public func registerC() {
            registerSuite({ => C().asTestSuite() })
        }
    }
    "#

/**
 * The generated extension of the same SDK's @Derive[Equatable] on enum E { A | B }.
 */
const SERVED_EQUATABLE =
    #"
    extend E <: Equatable < E > {
        public operator func ==(other: E): Bool {
            return match((this, other)) {
                case(A, A) => true
                case(B, B) => true
                case _ => false
            }
        }
        public operator func !=(other: E): Bool {
            !(this == other)
        }
    }
    "#

/**
 * Supplies the enum copied from its source and the SDK's generated equality extension.
 */
func servedEquatable(parsed: Fixture, db: AnalysisDatabase): Unit {
    let file = parsed.file("/model/main.cj")
    let head = file.text.indexOf("@Derive").getOrThrow()
    let start = file.text.indexOf("public enum E").getOrThrow()
    let copied = file.text[start..].trimAscii()
    let generated = trimIndent(SERVED_EQUATABLE)
    let output = "${copied}\n${generated}"
    answerStdMacro(
        db,
        db.sourceFile(file.fileId).getOrThrow(),
        "Derive",
        MappedText(
            output,
            [
                MappedSpan(
                    TextRange(0, copied.size),
                    SpanOrigin.FromSource(TextRange(start - head, start - head + copied.size))
                ),
                MappedSpan(TextRange(copied.size + 1, output.size), SpanOrigin.FromCall)
            ]
        )
    )
}

/**
 * Supplies @Test's real generated declarations; only the class name is copied in this empty case.
 */
func servedEmptyTest(parsed: Fixture, db: AnalysisDatabase): Unit {
    let file = parsed.file("/main.cj")
    let head = file.text.indexOf("@Test").getOrThrow()
    let sourceName = file.text.indexOf("class C").getOrThrow() + "class ".size - head
    let output = trimIndent(SERVED_EMPTY_TEST)
    let name = output.indexOf("class C").getOrThrow() + "class ".size
    answerStdMacro(
        db,
        db.sourceFile(file.fileId).getOrThrow(),
        "Test",
        MappedText(
            output,
            [
                MappedSpan(TextRange(0, name), SpanOrigin.FromCall),
                MappedSpan(
                    TextRange(name, name + 1),
                    SpanOrigin.FromSource(TextRange(sourceName, sourceName + 1))
                ),
                MappedSpan(TextRange(name + 1, output.size), SpanOrigin.FromCall)
            ]
        )
    )
}

/**
 * Answers one std call using its current fingerprint; checks it replaces the built-in fallback.
 */
func answerStdMacro(
    db: AnalysisDatabase,
    file: SourceFile,
    name: String,
    output: MappedText
): Unit {
    let requests = macroRequests(db, file).filter { one => one.definition.name == name }
    if (requests.size != 1 || !requests[0].definition.isStd) {
        throw FixtureException("expected one std @${name} request")
    }
    let request = requests[0]
    setMacroOutputs(db, [(request.call, MacroOutput(request.fingerprint, output, [], []))])
    let expanded = macroExpansion(db, request.call)
    @Expect(expanded.replaces, true)
    @Expect(expanded.text, output.text)
}

/**
 * Observes the local type at the optional cursor and every source diagnostic in both readings.
 */
func stdMacroObservations(parsed: Fixture, db: AnalysisDatabase): Array<Annotation> {
    let found = ArrayList<Annotation>()
    for (file in parsed.files) {
        for (diagnostic in diagnostics(db, file.fileId)) {
            found.add(Annotation(file.fileId, diagnostic.range, diagnostic.message))
        }
    }
    if (let Some(cursor) <- parsed.cursor) {
        let hovered = hoverAt(db, cursor.fileId, cursor.offset).getOrThrow()
        for (item in hovered.items) {
            found.add(Annotation(cursor.fileId, hovered.range, item.code))
        }
    }
    found.toArray()
}

/**
 * Generated interfaces and members must type source uses equally before and after a server answer.
 */
@Test
class StdMacroReadingsTest {
    @TestCase
    func derivedEqualityKeepsItsTypeAcrossPackages(): Unit {
        checkStdMacroReadings(
            #"
            //- /model/main.cj module=m package=m.model
            package m.model
            import std.deriving.*
            @Derive[Equatable]
            public enum E { | A | B }
            //- /main.cj module=m package=m
            package m
            import m.model.*
            func f(a: E, b: E): Unit {
                let $0same = a == b
            //        ^^^^ let same: Bool
            }
            "#,
            servedEquatable,
            stdMacroObservations
        )
    }

    @TestCase
    func derivedEqualityRejectsTheWrongOperandInBothReadings(): Unit {
        checkStdMacroReadings(
            #"
            //- /model/main.cj module=m package=m.model
            package m.model
            import std.deriving.*
            @Derive[Equatable]
            public enum E { | A | B }
            //- /main.cj module=m package=m
            package m
            import m.model.*
            func f(a: E): Unit {
                let same = a == "wrong"
            //               ^^ invalid binary operator '==' on type 'E' and 'String'
            }
            "#,
            servedEquatable,
            stdMacroObservations
        )
    }

    @TestCase
    func aCopiedEnumBodyKeepsItsDiagnosticRange(): Unit {
        checkStdMacroReadings(
            #"
            //- /model/main.cj module=m package=m.model
            package m.model
            import std.deriving.*
            func takesBool(value: Bool): Unit {}
            @Derive[Equatable]
            public enum E {
                | A | B
                func bad(): Unit { takesBool("wrong") }
            //                               ^^^^^^^ mismatched types: expected 'Bool', found 'String'
            }
            "#,
            servedEquatable,
            stdMacroObservations
        )
    }

    @TestCase
    func unittestGeneratedMemberKeepsItsReturnType(): Unit {
        checkStdMacroReadings(
            #"
            //- /main.cj module=m package=m
            package m
            import std.unittest.*
            import std.unittest.testmacro.*
            @Test
            class C {}
            func f(c: C): Unit {
                let $0suite = c.asTestSuite()
            //        ^^^^^ let suite: TestSuite
            }
            "#,
            servedEmptyTest,
            stdMacroObservations
        )
    }

    @TestCase
    func unittestGeneratedMemberRejectsAnArgumentInBothReadings(): Unit {
        checkStdMacroReadings(
            #"
            //- /main.cj module=m package=m
            package m
            import std.unittest.*
            import std.unittest.testmacro.*
            @Test
            class C {}
            func f(c: C): Unit {
                c.asTestSuite(1)
            //               ^^^ extra argument given for parameter list '()' in call: expected 0 arguments, found 1
            }
            "#,
            servedEmptyTest,
            stdMacroObservations
        )
    }
}
