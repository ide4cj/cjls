package loupe

import std.unittest.*
import std.unittest.testmacro.*
import rope.Rope
import loupe.vfs.FileId
import loupe.db.AnalysisDatabase

/**
 * The folds of `text` as `kind@range text`, line breaks in the text written `⏎`.
 */
func folded(text: String): Array<String> {
    let db = AnalysisDatabase()
    db.setFileText(FileId(0), Rope(text))
    let bytes = text.toArray()
    foldingRanges(db, FileId(0)).map {
        it => "${it} ${String.fromUtf8(bytes[it.range.start..it.range.end]).replace("\n", "⏎")}"
    }
}

@Test
class FoldingRangesTest {
    @TestCase
    func aBodyOnOneLineDoesNotFold() {
        // act, assert
        @Expect(folded("class A { func f(a: Int64, b: Int64) { [a, b] } }"), Array<String>())
    }

    @TestCase
    func nestedBodiesGiveNestedFoldsTheOuterFirst() {
        // act
        let result = folded("class A {\n    func f() {\n        1\n    }\n}")

        // assert
        @Expect(result, [
            "Block@8..42 {⏎    func f() {⏎        1⏎    }⏎}",
            "Block@23..40 {⏎        1⏎    }"
        ])
    }

    @TestCase
    func lineCommentsOneUnderTheOtherAreOneFoldABlankLineParts() {
        // act
        let result = folded("// a\n// b\n\n// c\n  // d\nlet x = 1 // e")

        // assert - the doc comment `let` holds folds as well
        @Expect(result, ["Comment@0..9 // a⏎// b", "Comment@11..22 // c⏎  // d"])
    }

    @TestCase
    func aBlockCommentFoldsAlone() {
        // act
        let result = folded("/* a\n */\n// b\n// c\nfunc f() {}")

        // assert
        @Expect(result, ["Comment@0..8 /* a⏎ */", "Comment@9..18 // b⏎// c"])
    }

    @TestCase
    func importsOneUnderTheOtherAreOneFoldABlankLineParts() {
        // act
        let result = folded("package p\nimport a.b\nimport c.{\n    d,\n    e\n}\n\nimport f.g\nimport h.i\n")

        // assert - a list of names folds inside
        @Expect(result, [
            "Imports@10..46 import a.b⏎import c.{⏎    d,⏎    e⏎}",
            "ArgList@30..46 {⏎    d,⏎    e⏎}",
            "Imports@48..69 import f.g⏎import h.i"
        ])
    }

    @TestCase
    func aLoneImportDoesNotFold() {
        // act, assert
        @Expect(folded("import a.b\n\nimport c.d\n"), Array<String>())
    }

    @TestCase
    func listsLiteralsLambdasAndMatchesFold() {
        // act
        let result = folded("main() {\n    f(\n        1\n    )\n    let a = [\n        (1,\n        2)\n    ]\n    match (a) {\n        case _ =>\n            g { x =>\n                x\n            }\n    }\n    \"\"\"\n    s\n    \"\"\"\n}")

        // assert
        @Expect(result, [
            "Block@7..191 {⏎    f(⏎        1⏎    )⏎    let a = [⏎        (1,⏎        2)⏎    ]⏎    match (a) {⏎        case _ =>⏎            g { x =>⏎                x⏎            }⏎    }⏎    \"\"\"⏎    s⏎    \"\"\"⏎}",
            "ArgList@14..31 (⏎        1⏎    )",
            "ArrayLiteral@44..74 [⏎        (1,⏎        2)⏎    ]",
            "ArrayLiteral@54..68 (1,⏎        2)",
            "Block@89..167 {⏎        case _ =>⏎            g { x =>⏎                x⏎            }⏎    }",
            "MatchArm@99..161 case _ =>⏎            g { x =>⏎                x⏎            }",
            "Block@123..161 { x =>⏎                x⏎            }",
            "StringLiteral@172..189 \"\"\"⏎    s⏎    \"\"\""
        ])
    }

    @TestCase
    func anUnterminatedBlockFoldsWhatItHas() {
        // act
        let result = folded("func f() {\n    g(\n        1\n")

        // assert
        @Expect(result, ["Block@9..27 {⏎    g(⏎        1", "ArgList@16..27 (⏎        1"])
    }

    @TestCase
    func aFileTheDatabaseDoesNotKnowHasNoFolds() {
        // act, assert
        @Expect(foldingRanges(AnalysisDatabase(), FileId(0)).isEmpty())
    }
}
