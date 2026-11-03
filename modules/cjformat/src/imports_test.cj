package cjformat

import std.unittest.*
import std.unittest.testmacro.*
import cjsyntax.parse
import ginkgo.TextRange

@Test
class ImportFormatTest {
    @TestCase
    func aSingleImportDropsItsBraces(): Unit {
        // arrange
        let source = "import source_change.{applyEdits}"
        let expected = "import source_change.applyEdits\n"

        // act
        let formatted = formatText(source)

        // assert
        @Expect(formatted, Some(expected))
        @Expect(formatText(expected), Some(expected))
        @Expect(formattingProblems("singleton", source), [])
    }

    @TestCase
    func aliasesPathsAndNestedGroupsKeepTheirMeaning(): Unit {
        check("import p.{X as Y}", "import p.X as Y\n")
        check("import p.{q.X}", "import p.q.X\n")
        check("import p.{q.{X}}", "import p.q.X\n")
        check("import {p.X}", "import p.X\n")
        check("import p.{q.{X}, Y}", "import p.{q.X, Y}\n")
        check("public import p.{X}", "public import p.X\n")
        check("import p::{X}", "import p::X\n")
    }

    @TestCase
    func multilineSingletonsKeepTheLineEndingConvention(): Unit {
        check("import p.{\n    X\n}\n", "import p.X\n")
        check("import p.{\r\n    X\r\n}\r\n", "import p.X\r\n")
    }

    @TestCase
    func commentsAndTrailingCommasKeepTheirBraces(): Unit {
        check("import p.{X,}", "import p.{X,}\n")
        check("import p.{/* keep */ X}", "import p.{/* keep */ X}\n")
        check("import p.{X /* keep */}", "import p.{X /* keep */}\n")
        check("import p.{X // keep\n}", "import p.{\n    X // keep\n}\n")
        check("import p.{X, Y}", "import p.{X, Y}\n")
        check("import p.*", "import p.*\n")
        check("// before\nimport p.{X} // after", "// before\nimport p.X // after\n")
    }

    @TestCase
    func stringsAndMacroTokensStayVerbatim(): Unit {
        check(#"let text = "import p.{X}""#, #"let text = "import p.{X}""# + "\n")
        check("func f() { @M(import p.{X}) }", "func f() {\n    @M(import p.{X})\n}\n")
    }

    @TestCase
    func onlyTheSelectedImportIsSimplified(): Unit {
        // arrange
        let source = "import p.{X}\nimport q.{Y}\nfunc   f() {}\n"
        let start = source.indexOf("Y").getOrThrow()

        // act
        let formatted = formattedIn(source, TextRange(start, start + 1))

        // assert
        @Expect(formatted, Some("import p.{X}\nimport q.Y\nfunc   f() {}\n"))
    }

    @TestCase
    func syntaxErrorsStillRefuseFormatting(): Unit {
        // arrange
        let source = "import p.{X}\nfunc f( {"

        // act
        let formatted = formatText(source)
        let ranged = formatRange(parse(source), TextRange(0, 1))

        // assert
        @Expect(formatted, None)
        @Expect(ranged, None)
    }
}
