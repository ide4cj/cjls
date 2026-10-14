package cjsyntax

import std.collection.*
import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*
import ginkgo.*

/** A name as completion inserts one at the cursor to parse the file as if it were there. */
let MARKER = "cjlsCompletionMarker"

func edited(text: String, delete: TextRange, insert: String): String {
    text[..delete.start] + insert + text[delete.end..]
}

func after(text: String, needle: String): Int64 {
    text.indexOf(needle).getOrThrow() + needle.size
}

@Test
class ReparseTest {
    @TestCase
    func aMarkerAfterADotReparsesTheBodyAloneAndSharesTheOtherDeclarations() {
        // arrange
        let text = "func a() {\n    x.\n    foo()\n}\n\nfunc b() { 1 }\n"
        let before = parse(text)
        let decls = collectArray(before.syntaxNode().children())
        let edit = TextRange.empty(after(text, "x."))

        // act
        let reparsed = reparse(before, edit, MARKER)

        // assert
        @Expect(reparsed == parse(edited(text, edit, MARKER)))
        @Expect(reparsed.syntaxNode().text().contains("x.${MARKER}\n    foo()"))
        let declsAfter = collectArray(reparsed.syntaxNode().children())
        @Expect(refEq(declsAfter[1].green, decls[1].green))
        @Expect(!refEq(declsAfter[0].green, decls[0].green))
    }

    @TestCase
    func theNearestBlockIsReparsedNotTheWholeBody() {
        // arrange
        let text = "func a() {\n    let y = 1\n    if (y > 0) {\n        y.\n    }\n    y\n}\n"
        let before = parse(text)
        let body = before.syntaxNode().descendants().filter {n => n.kind == Block}.next().getOrThrow()
        let statements = collectArray(body.children())
        let edit = TextRange.empty(after(text, "y."))

        // act
        let reparsed = reparse(before, edit, MARKER)

        // assert
        @Expect(reparsed == parse(edited(text, edit, MARKER)))
        let bodyAfter = reparsed.syntaxNode().descendants().filter {n => n.kind == Block}.next().getOrThrow()
        let statementsAfter = collectArray(bodyAfter.children())
        @Expect(statementsAfter.size, statements.size)
        @Expect(refEq(statementsAfter[0].green, statements[0].green))
        @Expect(!refEq(statementsAfter[1].green, statements[1].green))
        @Expect(refEq(statementsAfter[2].green, statements[2].green))
    }

    @TestCase
    func errorsOutsideTheBlockAreKeptAndShiftedPastTheEdit() {
        // arrange
        let text = "func a( {\n    x.\n}\nfunc b( {}\n"
        let before = parse(text)
        let edit = TextRange.empty(after(text, "x."))

        // act
        let reparsed = reparse(before, edit, MARKER)

        // assert
        let full = parse(edited(text, edit, MARKER))
        @Expect(reparsed == full)
        @Expect(reparsed.errors.size, full.errors.size)
        @Expect(reparsed.errors.size >= 2)
    }

    @TestCase
    func anEditThatUnbalancesTheBlockIsParsedInFull() {
        // arrange
        let text = "func a() {\n    x.\n}\n"
        let before = parse(text)
        let edit = TextRange.empty(after(text, "x."))

        // act
        let incremental = REPARSER.reparse(before, edit, "}")
        let reparsed = reparse(before, edit, "}")

        // assert
        @Expect(incremental.isNone())
        @Expect(reparsed == parse(edited(text, edit, "}")))
    }

    @TestCase
    func aDeclarationOnlyAFileHoldsTypedInABodyIsParsedInFull() {
        // arrange
        let text = "func a() {\n    x\n}\n"
        let before = parse(text)
        let edit = TextRange.empty(after(text, "x\n"))

        // act
        let incremental = REPARSER.reparse(before, edit, "class ")
        let reparsed = reparse(before, edit, "class ")

        // assert
        @Expect(incremental.isNone())
        @Expect(reparsed == parse(edited(text, edit, "class ")))
    }

    @TestCase
    func anEditOutsideAnyBlockIsParsedInFull() {
        // arrange
        let text = "func a() {}\nlet x = 1\n"
        let before = parse(text)
        let edit = TextRange.empty(after(text, "let x"))

        // act
        let incremental = REPARSER.reparse(before, edit, "y")
        let reparsed = reparse(before, edit, "y")

        // assert
        @Expect(incremental.isNone())
        @Expect(reparsed == parse(edited(text, edit, "y")))
    }

    /**
     * Every source of this repository, a marker inserted after a `.` and at the ends of a body: the reparse is
     * the full parse. Six places per file, to stay quick.
     */
    @TestCase
    func aMarkerAnywhereInThisRepositoryReparsesAsAFullParseDoes() {
        // arrange
        let files = ArrayList<Path>()
        for (info in Directory.readFrom(Path("modules"))) {
            if (info.isDirectory() && exists(info.path.join("src"))) {
                cjFilesUnder(info.path.join("src"), files)
            }
        }

        // act
        var cases = 0
        var incremental = 0
        let mismatches = ArrayList<String>()
        for (file in files) {
            let text = String.fromUtf8(File.readFrom(file))
            let before = parse(text)
            for (offset in markerPlaces(before.syntaxNode())) {
                let edit = TextRange.empty(offset)
                cases++
                if (REPARSER.reparse(before, edit, MARKER).isSome()) {
                    incremental++
                }
                if (reparse(before, edit, MARKER) != parse(edited(text, edit, MARKER))) {
                    mismatches.add("${file}:${offset}")
                }
            }
        }

        // assert
        @Expect(files.size > 100)
        @Expect(cases > 500)
        @Expect(incremental > cases / 2)
        @Expect(mismatches.toArray(), Array<String>())
    }
}

func cjFilesUnder(dir: Path, into: ArrayList<Path>): Unit {
    for (info in Directory.readFrom(dir)) {
        if (info.isDirectory()) {
            cjFilesUnder(info.path, into)
        } else if (info.path.toString().endsWith(".cj")) {
            into.add(info.path)
        }
    }
}

/**
 * Up to six offsets in `root`: after the `{` of the first block, before the `}` of the last, and after up to four
 * `.` tokens inside blocks, spread over the file.
 */
func markerPlaces(root: CjSyntaxNode): Array<Int64> {
    let blocks = collectArray(root.descendants().filter {n => n.kind == Block})
    let places = ArrayList<Int64>()
    if (blocks.isEmpty()) {
        return places.toArray()
    }
    places.add(blocks[0].textRange.start + 1)
    places.add(blocks[blocks.size - 1].textRange.end - 1)
    let dots = ArrayList<Int64>()
    for (element in root.descendantsWithTokens()) {
        if (let SyntaxElement.Token(token) <- element) {
            if (token.kind == Dot && token.ancestors().any {n => n.kind == Block}) {
                dots.add(token.textRange.end)
            }
        }
    }
    let step = max(dots.size / 4, 1)
    var i = 0
    while (i < dots.size && places.size < 6) {
        places.add(dots[i])
        i += step
    }
    places.toArray()
}
