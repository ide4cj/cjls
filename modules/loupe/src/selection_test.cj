package loupe

import std.unittest.*
import std.unittest.testmacro.*
import loupe.fixture.*

/**
 * The selections at the `$0` of `fixture`, innermost first, as the text of each between backquotes,
 * one a line, its line breaks written `\n`; the expected answer is unindented as a fixture is.
 */
func selections(fixture: String): String {
    let parsed = Fixture.parse(fixture)
    let cursor = parsed.cursor ?? throw FixtureException("no $0 in the fixture")
    let text = parsed.files[0].text
    let ranges = extendSelection(parsed.database(), cursor.fileId, cursor.offset)
    let lines = ranges.map {range => unsafe {
        String.fromUtf8Unchecked(text.toArray()[range.start..range.end]).replace("\n", "\\n")
    }}
    String.join(lines.map {line => "`${line}`\n"})
}

@Test
class SelectionTest {
    @TestCase
    func aNameInACallWidensToTheCallThenOutwards() {
        // act
        let result = selections(#"
            func f() {
                a.b$0(c)
            }
            "#)

        // assert - between `b` and `(` the name is taken
        @Expect(result, trimIndent(#"
            `b`
            `a.b`
            `a.b(c)`
            `{\n    a.b(c)\n}`
            `func f() {\n    a.b(c)\n}`
            `func f() {\n    a.b(c)\n}\n`
            "#))
    }

    @TestCase
    func anArgumentWidensWithItsCommaBeforeTheList() {
        // act
        let result = selections(#"
            let x = f(a, b$0b, c)
            "#)

        // assert
        @Expect(result, trimIndent(#"
            `bb`
            `bb, `
            `(a, bb, c)`
            `f(a, bb, c)`
            `let x = f(a, bb, c)`
            `let x = f(a, bb, c)\n`
            "#))
    }

    @TestCase
    func theLastElementOfAListTakesTheCommaBeforeIt() {
        // act
        let result = selections(#"
            let t = (a, $0b)
            "#)

        // assert
        @Expect(result, trimIndent(#"
            `b`
            `, b`
            `(a, b)`
            `let t = (a, b)`
            `let t = (a, b)\n`
            "#))
    }

    @TestCase
    func aTypeArgumentWidensWithItsComma() {
        // act
        let result = selections(#"
            let m: HashMap<St$0ring, Int64> = x
            "#)

        // assert
        @Expect(result, trimIndent(#"
            `String`
            `String, `
            `<String, Int64>`
            `HashMap<String, Int64>`
            `let m: HashMap<String, Int64> = x`
            `let m: HashMap<String, Int64> = x\n`
            "#))
    }

    @TestCase
    func aWordInACommentComesBeforeTheComment() {
        // act - the comment is the declaration's, before all of it
        let result = selections(#"
            // one tw$0o three
            let x = 1
            "#)

        // assert
        @Expect(result, trimIndent(#"
            `two`
            `// one two three`
            `// one two three\nlet x = 1`
            `// one two three\nlet x = 1\n`
            "#))
    }

    @TestCase
    func aPieceOfAnInterpolatedStringThenTheLiteral() {
        // act
        let result = selections(#"
            let s = "one tw$0o ${x} three"
            "#)

        // assert
        @Expect(result, trimIndent(#"
            `two`
            `one two `
            `"one two ${x} three"`
            `let s = "one two ${x} three"`
            `let s = "one two ${x} three"\n`
            "#))
    }

    @TestCase
    func codeInsideAnInterpolationWidensToTheInterpolation() {
        // act
        let result = selections(#"
            let s = "a${x$0 + 1}b"
            "#)

        // assert
        @Expect(result, trimIndent(#"
            `x`
            `x + 1`
            `${x + 1}`
            `"a${x + 1}b"`
            `let s = "a${x + 1}b"`
            `let s = "a${x + 1}b"\n`
            "#))
    }

    @TestCase
    func aDeclarationComesWithItsDocCommentAndAnnotations() {
        // act
        let result = selections(#"
            /** Doc. */
            @Deprecated
            func f$0() {}
            "#)

        // assert
        @Expect(result, trimIndent(#"
            `f`
            `/** Doc. */\n@Deprecated\nfunc f() {}`
            `/** Doc. */\n@Deprecated\nfunc f() {}\n`
            "#))
    }

    @TestCase
    func aPositionInsideAnErrorNodeWidensThroughIt() {
        // act
        let result = selections(#"
            let x = )$0
            "#)

        // assert
        @Expect(result, trimIndent(#"
            `)`
            `let x = )\n`
            "#))
    }

    @TestCase
    func theEndOfTheFileIsTheWholeFileAtLast() {
        // act
        let result = selections(#"let x = 1$0"#)

        // assert
        @Expect(result, trimIndent(#"
            `1`
            `let x = 1`
            "#))
    }

    @TestCase
    func anEmptyFileIsSelectedWhole() {
        // act, assert
        @Expect(selections("$0"), "``\n")
    }
}
