package cjformat

import std.unittest.*
import std.unittest.testmacro.*
import cjsyntax.parse
import ginkgo.TextRange
import source_change.applyEdits

@Test
class ImportFormatTest {
    @TestCase[row in [
        ("import source_change.{applyEdits}", "import source_change.applyEdits\n"),
        ("import p.{X as Y}", "import p.X as Y\n"),
        ("import p.{q.X}", "import p.q.X\n"),
        ("import p.{q.{X}}", "import p.q.X\n"),
        ("import {p.X}", "import p.X\n"),
        ("import p.{q.{X}, Y}", "import p.Y\nimport p.q.X\n"),
        ("public import p.{X}", "public import p.X\n"),
        ("import p::{X}", "import p::X\n"),
        ("import p.{\n    X\n}\n", "import p.X\n"),
        ("import p.{\r\n    X\r\n}\r\n", "import p.X\r\n"),
        ("import p.{X,}", "import p.{X,}\n"),
        ("import p.{/* keep */ X}", "import p.{/* keep */ X}\n"),
        ("import p.{X /* keep */}", "import p.{X /* keep */}\n"),
        ("import p.{X // keep\n}", "import p.{\n    X // keep\n}\n"),
        ("import p.*", "import p.*\n"),
        ("import p.{}", "import p.{}\n"),
        ("import p.B\nimport p.A", "import p.{A, B}\n"),
        ("import p.{Z, A}\nimport p.B as C", "import p.{A, B as C, Z}\n"),
        ("public import p.B\npublic import p.A", "public import p.{A, B}\n"),
        ("import p.B\npublic import p.A", "public import p.A\nimport p.B\n"),
        ("import p.*\nimport p.B\nimport p.A", "import p.*\nimport p.{A, B}\n"),
        ("import p.B\nimport p.*\nimport p.A", "import p.*\nimport p.{A, B}\n"),
        ("import p.{B, A,}", "import p.{A, B,}\n"),
        ("import z.Z\nimport stdx.z.Z\nimport std.b.B\nimport a.A\nimport std.a.A",
            "import std.a.A\nimport std.b.B\nimport stdx.z.Z\nimport a.A\nimport z.Z\n"),
        ("import p.B\n\nimport p.A", "import p.{A, B}\n"),
        ("import p.A as Y\nimport p.A as X", "import p.{A as X, A as Y}\n"),
        ("import p.A\nimport p.A", "import p.{A, A}\n"),
        ("import p::q.B\nimport p::q.A", "import p::q.{A, B}\n"),
        ("import p.A\nimport p::B", "import p.A\nimport p::B\n"),
        ("import p.`type`\nimport p.A", "import p.{A, `type`}\n"),
        ("@When[os == \"Linux\"]\nimport p.B\n@When[os==\"Linux\"]\nimport p.A",
            "@When[os == \"Linux\"]\nimport p.{A, B}\n"),
        ("@When[os == \"Linux\"]\nimport p.B\n@When[os == \"Windows\"]\nimport p.A",
            "@When[os == \"Windows\"]\nimport p.A\n@When[os == \"Linux\"]\nimport p.B\n")
    ]]
    func importsHaveOneCanonicalLayout(row: (String, String)): Unit {
        // arrange
        let (source, expected) = row

        // act
        let formatted = formatText(source)
        let second = formatted.flatMap { text => formatText(text) }
        let problems = formattingProblems("imports", source)

        // assert
        @Expect(formatted, Some(expected))
        @Expect(second, formatted)
        @Expect(problems, [])
    }

    @TestCase[header in ["package app", "package app.handlers", "macro package app.macros", "package `app`.handlers"]]
    func modulePackagesFollowDependencies(header: String): Unit {
        // arrange
        let imports =
            "import app.z.Z\nimport z.Z\nimport stdx.z.Z\nimport app.a.B\nimport app.a.A\nimport a.A\nimport std.b.B\nimport app_extra.X\nimport app::external.X\n"
        let source = "${header}\n\n${imports}"
        let expected =
            "${header}\n\nimport std.b.B\nimport stdx.z.Z\nimport a.A\nimport app::external.X\nimport app_extra.X\nimport z.Z\nimport app.a.{A, B}\nimport app.z.Z\n"

        // act
        let formatted = formatText(source)

        // assert
        @Expect(formatted, Some(expected))
        @Expect(formatted.flatMap { text => formatText(text) }, formatted)
        @Expect(formattingProblems("module imports", source), [])
    }

    @TestCase
    func organizationQualifiersDistinguishModules(): Unit {
        // arrange
        let source =
            "package org::app.handlers\n\nimport org::app.z.Z\nimport org::app as current\nimport org::other.A\nimport app.a.A\nimport org::app.a.*\nimport z.Z\n"
        let expected =
            "package org::app.handlers\n\nimport app.a.A\nimport org::other.A\nimport z.Z\nimport org::app as current\nimport org::app.a.*\nimport org::app.z.Z\n"

        // act
        let formatted = formatText(source)

        // assert
        @Expect(formatted, Some(expected))
        @Expect(formatted.flatMap { text => formatText(text) }, formatted)
        @Expect(formattingProblems("qualified module imports", source), [])
    }

    @TestCase[lineBreak in ["\n", "\r\n"]]
    func importRangesKeepTheModuleContext(lineBreak: String): Unit {
        // arrange
        let source =
            "package app.handlers\nimport untouched.Z\nimport app.a.A\nimport z.Z\nfunc   f() {}\n"
                .replace("\n", lineBreak)
        let start = source.indexOf("import app").getOrThrow()
        let end = source.indexOf("func").getOrThrow()
        let expected =
            "package app.handlers\nimport untouched.Z\nimport z.Z\nimport app.a.A\nfunc   f() {}\n"
                .replace("\n", lineBreak)

        // act
        let formatted = formattedIn(source, TextRange(start, end))

        // assert
        @Expect(formatted, Some(expected))
    }

    @TestCase[row in [
        ("import p.B\n// keep\nimport p.A", "import p.B\n// keep\nimport p.A\n"),
        ("import p.B // keep\nimport p.A", "import p.B // keep\nimport p.A\n"),
        ("import p.B /* keep */\nimport p.A", "import p.B /* keep */\nimport p.A\n"),
        ("import p.{B, /* keep */ A}\nimport p.C", "import p.{B, /* keep */ A}\nimport p.C\n"),
        ("// before\nimport p.{X} // after", "// before\nimport p.X // after\n"),
        (#"let text = "import p.{X}""#, #"let text = "import p.{X}""# + "\n"),
        ("func f() { @M(import p.{X}) }", "func f() {\n    @M(import p.{X})\n}\n")
    ]]
    func commentsAndProtectedTextKeepTheirPlacement(row: (String, String)): Unit {
        // arrange
        let (source, expected) = row

        // act
        let formatted = formatText(source)
        let problems = formattingProblems("protected imports", source)

        // assert
        @Expect(formatted, Some(expected))
        @Expect(problems, [])
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

    @TestCase[lineBreak in ["\n", "\r\n"]]
    func onlyTheSelectedImportBlockIsSortedAndMerged(lineBreak: String): Unit {
        // arrange
        let source = "import z.Z\nimport p.B\nimport p.A\nfunc   f() {}\n".replace("\n", lineBreak)
        let start = source.indexOf("import p.B").getOrThrow()
        let end = source.indexOf("func").getOrThrow()
        let expected = "import z.Z\nimport p.{A, B}\nfunc   f() {}\n".replace("\n", lineBreak)

        // act
        let formatted = formattedIn(source, TextRange(start, end))

        // assert
        @Expect(formatted, Some(expected))
    }

    @TestCase[comment in ["// keep", "/* keep */"]]
    func aRangeRetainsTrailingCommentContextAndRemovesRootIndentation(comment: String): Unit {
        // arrange
        let source = "  import p.{B, A} ${comment}\nfunc   f() {}\n"
        let at = source.indexOf("B").getOrThrow()
        let expected = "import p.{B, A} ${comment}\nfunc   f() {}\n"

        // act
        let formatted = formattedIn(source, TextRange(at, at + 1))

        // assert
        @Expect(formatted, Some(expected))
    }

    @TestCase[lineBreak in ["\n", "\r\n"]]
    func aLineWithATrailingCommentDoesNotSelectTheNextImport(lineBreak: String): Unit {
        // arrange
        let source = "  import p.B // keep\nimport p.A\nfunc   f() {}\n".replace("\n", lineBreak)
        let expected = "import p.B // keep\nimport p.A\nfunc   f() {}\n".replace("\n", lineBreak)
        let range = linesOf(source, 0, 0)

        // act
        let formatted = formattedIn(source, range)

        // assert
        @Expect(formatted, Some(expected))
    }

    @TestCase[row in [
        ("package p\r\nimport q.{LongSecondName, LongFirstName}\r\nfunc   f() {}\r\n",
            "package p\r\nimport q.{\r\n  LongFirstName,\r\n  LongSecondName\r\n}\r\nfunc   f() {}\r\n", 25),
        ("package p\r\nimport q.B", "package p\r\nimport q.B\r\n", 100)
    ]]
    func aSingleImportRangeUsesTheFilesLineEndingConvention(row: (String, String, Int64)): Unit {
        // arrange
        let (source, expected, width) = row
        let options = FormatOptions(lineWidth: width, indentWidth: 2)
        let at = source.indexOf("import").getOrThrow()

        // act
        let edits = formatRange(parse(source), TextRange(at, at + 1), options: options).getOrThrow()
        let formatted = applyEdits(source, edits)

        // assert
        @Expect(formatted, expected)
    }

    @TestCase
    func longMergedListsUseTheConfiguredWidthAndIndentation(): Unit {
        // arrange
        let source = "import p.LongSecondName\nimport p.LongFirstName"
        let options = FormatOptions(lineWidth: 25, indentWidth: 2)
        let expected = "import p.{\n  LongFirstName,\n  LongSecondName\n}\n"

        // act
        let formatted = formatText(source, options: options)

        // assert
        @Expect(formatted, Some(expected))
        @Expect(formattingProblems("wide imports", source, options: options), [])
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
