package loupe

import std.unittest.*
import std.unittest.testmacro.*
import ginkgo.TextRange
import loupe.fixture.Fixture

/**
 * A place, as a line to compare.
 */
func describe(place: ?ExpandedPlace): String {
    match (place) {
        case Some(InSource(offset)) => "source ${offset}"
        case Some(InExpansion(_, offset)) => "expansion ${offset}"
        case None => "none"
    }
}

@Test
class ShownExpansionTest {
    @TestCase
    func anExpansionIsFormattedAndItsOffsetsGoBothWays(): Unit {
        // arrange
        let written = "class A {\nfunc f(): Unit {}\n  let x = 1\n}\n\n"

        // act
        let shown = ShownExpansion.of(written)

        // assert
        @Expect(shown.text, "class A {\n    func f(): Unit {}\n    let x = 1\n}")
        @Expect(shown.fromWritten(offsetIn(written, "func")), offsetIn(shown.text, "func"))
        @Expect(shown.toWritten(offsetIn(shown.text, "let")), offsetIn(written, "let"))
        // the end of a range stays at the end of what it covers
        @Expect(shown.fromWritten(offsetIn(written, "{}", plus: 2)), offsetIn(shown.text, "{}", plus: 2))
    }

    @TestCase
    func reflowedLinesKeepTheMappingToTheMacroOutput(): Unit {
        // arrange
        let written = "func f(x: Int64) { g(x) }"

        // act
        let shown = ShownExpansion.of(written)

        // assert
        @Expect(shown.text, "func f(x: Int64) {\n    g(x)\n}")
        let oldName = offsetIn(written, "g(x)", plus: 2)
        let newName = offsetIn(shown.text, "g(x)", plus: 2)
        @Expect(shown.fromWritten(TextRange(oldName, oldName + 1)), TextRange(newName, newName + 1))
        @Expect(shown.toWritten(newName), oldName)
    }

    @TestCase
    func anExpansionThatDoesNotFormatIsShownAsWritten(): Unit {
        // arrange
        let written = "class A {\nfunc f(: Unit {}\n"

        // act
        let shown = ShownExpansion.of(written)

        // assert
        @Expect(shown.text, "class A {\nfunc f(: Unit {}")
        @Expect(shown.toWritten(offsetIn(shown.text, "func")), offsetIn(written, "func"))
    }
}

@Test
class ExpandFileTest {
    @TestCase
    func aCallOfTheWorkspaceIsReplacedByItsExpansionFromTheCallOn(): Unit {
        // arrange
        let (db, file, _, written) = answeredM()
        let source = file.text(db).toString()

        // act
        let expanded =
            expandFile(db, file.fileId(db), "// header")
                .getOrThrow {
                    =>
                    IllegalStateException("the fixture must produce an expanded file")
                }

        // assert
        @Expect(source.contains("@M[x]\nclass C {}"))
        let formatted = written.replace("{ C() }", "{\n    C()\n}")
        let replaced =
            source.replace("@M[x]\nclass C {}", "// @M[x] expanded by cjls\n${formatted}")
        @Expect(expanded.text, "// header\n${replaced}")
    }

    @TestCase
    func anOffsetIsInTheSourceInAnExpansionOrInWhatTheAnalysisWrote(): Unit {
        // arrange
        let (db, file, call, written) = answeredM()
        let source = file.text(db).toString()
        let expanded =
            expandFile(db, file.fileId(db), "// header")
                .getOrThrow {
                    =>
                    IllegalStateException("the fixture must produce an expanded file")
                }
        let text = expanded.text

        // act
        let onImport = expanded.placeOf(offsetIn(text, "import"))
        let onGen = expanded.placeOf(offsetIn(text, "Gen"))
        let onHeader = expanded.placeOf(offsetIn(text, "header"))
        let onComment = expanded.placeOf(offsetIn(text, "expanded by"))

        // assert
        @Expect(describe(onImport), "source ${offsetIn(source, "import")}")
        @Expect(describe(onGen), "expansion ${offsetIn(written, "Gen")}")
        @Expect(match (onGen) {
            case Some(InExpansion(one, _)) => one == call
            case _ => false
        })
        @Expect(describe(onHeader), "none")
        @Expect(describe(onComment), "none")
    }

    @TestCase
    func rangesOfTheSourceAndOfAnExpansionAreFoundInTheFile(): Unit {
        // arrange
        let (db, file, call, written) = answeredM()
        let source = file.text(db).toString()
        let expanded =
            expandFile(db, file.fileId(db), "// header")
                .getOrThrow {
                    =>
                    IllegalStateException("the fixture must produce an expanded file")
                }
        let text = expanded.text
        let import_ = offsetIn(source, "import")
        let gen = offsetIn(written, "Gen")

        // act
        let fromSource = expanded.fromSource(TextRange(import_, import_ + 6))
        let fromReplaced =
            expanded.fromSource(TextRange(offsetIn(source, "C {}"), offsetIn(source, "C {}") + 1))
        let fromExpansion = expanded.fromExpansion(call, TextRange(gen, gen + 3))

        // assert
        @Expect(fromSource.map {range => text[range.start..range.end]}, Some("import"))
        @Expect(fromReplaced, None)
        @Expect(fromExpansion.map {range => text[range.start..range.end]}, Some("Gen"))
        @Expect(expanded.expansionOf(call).map {range => text[range.start..range.end].startsWith("class C {}")},
            Some(true))
    }

    @TestCase
    func aStdDeriveIsFollowedByTheAnalysissSignatures(): Unit {
        // arrange
        let parsed =
            Fixture
                .parse(
                    #"
            //- /main.cj module=m package=m
            package m
            import std.deriving.*
            @Derive[Hashable]
            struct S {}
            func f() {}
            "#
                )
        let db = deriveDatabase(parsed)
        let file = parsed.file("/main.cj")

        // act
        let expanded =
            expandFile(db, file.fileId, "// header")
                .getOrThrow {
                    =>
                    IllegalStateException("the fixture must produce an expanded file")
                }
        let text = expanded.text

        // assert
        @Expect(text.startsWith(
            "// header\npackage m\nimport std.deriving.*\n@Derive[Hashable]\nstruct S {}\n\n// @Derive[Hashable] expanded by cjls: its own, signatures only, no bodies\nextend S <: Hashable"))
        @Expect(text.endsWith("}\nfunc f() {}\n"))
        @Expect(describe(expanded.placeOf(offsetIn(text, "S <:"))).startsWith("expansion "))
        @Expect(describe(expanded.placeOf(offsetIn(text, "f()"))), "source ${offsetIn(file.text, "f()")}")
    }

    @TestCase
    func aFileWithNoExpansionHasNone(): Unit {
        // arrange
        let (db, file) =
            expansionDatabase(
                #"
            package m
            class C {}
            "#
            )

        // act
        let expanded = expandFile(db, file.fileId(db), "// header")

        // assert
        @Expect(expanded.isNone())
    }
}
