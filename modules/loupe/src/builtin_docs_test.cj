package loupe

import std.collection.*
import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*

/**
 * The language guide `.corpora/cangjie_docs` holds, at the commit `tests/corpora/fetch.py` names.
 */
func cangjieDocsDir(): Path {
    let dir = Path(".corpora/cangjie_docs")
    if (!exists(dir)) {
        throw IllegalStateException("cangjie_docs is not in .corpora/: run `python3 tests/corpora/fetch.py`")
    }
    dir
}

/**
 * The anchor GitHub gives the heading `heading`: lower case, each space a hyphen, what is neither a letter, a digit,
 * a hyphen nor an underscore dropped.
 */
func githubAnchor(heading: String): String {
    let anchor = StringBuilder()
    for (c in heading.trimAscii().toAsciiLower().runes()) {
        if (c == r' ') {
            anchor.append(r'-')
        } else if (c.isAsciiLetter() || c.isAsciiNumber() || c == r'-' || c == r'_' || UInt32(c) > 0x7F) {
            anchor.append(c)
        }
    }
    anchor.toString()
}

/**
 * The anchors of the headings of the Markdown `text`, outside its code blocks.
 */
func anchorsOf(text: String): HashSet<String> {
    let anchors = HashSet<String>()
    var inCode = false
    for (line in text.split("\n")) {
        if (line.trimAsciiStart().startsWith("```")) {
            inCode = !inCode
        } else if (!inCode && line.startsWith("#")) {
            var heading = line
            while (heading.startsWith("#")) {
                heading = heading[1..]
            }
            anchors.add(githubAnchor(heading))
        }
    }
    anchors
}

@Test
class BuiltinDocsTest {
    @TestCase
    func aHeadingIsAnchoredAsGitHubAnchorsIt() {
        @Expect(githubAnchor(" @Frozen"), "frozen")
        @Expect(githubAnchor(" The `Any` Type"), "the-any-type")
        @Expect(githubAnchor(" sizeOf/alignOf"), "sizeofalignof")
    }

    @TestCase
    func theDocsAreFetchedAtTheCommitTheLinksName() {
        // act
        let head = String.fromUtf8(File.readFrom(cangjieDocsDir().join(".git").join("HEAD"))).trimAscii()

        // assert
        @Expect(head, CANGJIE_DOCS_COMMIT)
    }

    @TestCase
    func everyBuiltinLinksToASectionOfTheDocs() {
        // arrange
        let guide = cangjieDocsDir().join("docs").join("dev-guide").join("source_en")

        // act
        let broken = builtinDocs() |> filter {
            doc: BuiltinDoc =>
            let page = guide.join(doc.page)
            !exists(page) || !anchorsOf(String.fromUtf8(File.readFrom(page))).contains(doc.anchor)
        } |> map {doc: BuiltinDoc => "${doc.name}: ${doc.page}#${doc.anchor}"} |> collectArray

        // assert
        @Expect(broken, Array<String>())
    }

    @TestCase
    func everyBuiltinIsToldOnce() {
        // arrange
        let names = HashSet<String>()

        // act
        let twice = builtinDocs() |> filter {doc: BuiltinDoc => !names.add(doc.name)} |>
            map {doc: BuiltinDoc => doc.name} |> collectArray

        // assert
        @Expect(twice, Array<String>())
    }
}
