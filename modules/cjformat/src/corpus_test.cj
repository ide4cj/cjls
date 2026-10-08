package cjformat

import std.collection.ArrayList
import std.env.getVariable
import std.fs.{Directory, File, Path}
import ginkgo.SyntaxElement
import cjsyntax.*

/**
 * The tokens of `text` the formatter has to keep: all but whitespace, a comment without the
 * whitespace it may move or drop.
 */
func significant(text: String): Array<String> {
    let tokens = ArrayList<String>()
    for (element in parse(text).syntaxNode().descendantsWithTokens()) {
        match (element) {
            case SyntaxElement.Token(t) where t.kind == Whitespace || t.kind == Newline => ()
            case SyntaxElement.Token(t) where t.kind == LineComment || t.kind == BlockComment =>
                tokens.add(t.text().replace(" ", "").replace("\t", "").replace("\r", "").replace("\n", ""))
            case SyntaxElement.Token(t) => tokens.add(t.text())
            case _ => ()
        }
    }
    tokens.toArray()
}

/**
 * What is wrong with formatting `text`, as lines; nothing for a file with syntax errors, which is
 * not formatted.
 */
func formattingProblems(name: String, text: String): Array<String> {
    let formatted = formatText(text) ?? return []
    let problems = ArrayList<String>()
    if (significant(formatted) != significant(text)) {
        problems.add("${name}: formatting changed more than whitespace")
    }
    if (formatText(formatted) != Some(formatted)) {
        problems.add("${name}: formatting it twice changes it again")
    }
    problems.toArray()
}

func cjFilesUnder(dir: Path, files: ArrayList<Path>): Unit {
    for (info in Directory.readFrom(dir) where !info.isSymbolicLink()) {
        if (info.isDirectory() && info.name != "target" && !info.name.startsWith(".")) {
            cjFilesUnder(info.path, files)
        } else if (info.isRegular() && info.name.endsWith(".cj")) {
            files.add(info.path)
        }
    }
}

/**
 * The two properties of a formatter over real code: it changes only whitespace, and what it
 * makes it leaves alone.
 */
@Test
class CorpusTest {
    @TestCase
    func thisRepositoryFormatsToTheSameTokensAndStaysFormatted() {
        check(Path("modules"))
    }

    /**
     * Over the corpus `CJFORMAT_CORPUS` names, such as the compiler's tests; nothing without it.
     */
    @TestCase
    func aCorpusFormatsToTheSameTokensAndStaysFormatted() {
        if (let Some(corpus) <- getVariable("CJFORMAT_CORPUS")) {
            check(Path(corpus))
        }
    }

    private func check(root: Path) {
        // arrange
        let files = ArrayList<Path>()
        cjFilesUnder(root, files)

        // act
        let problems = ArrayList<String>()
        for (file in files) {
            let text = try {
                String.fromUtf8(File.readFrom(file))
            } catch (_: IllegalArgumentException) {
                continue
            }
            problems.add(all: formattingProblems(file.toString(), text))
        }

        // assert
        @Expect(files.size > 0)
        @Expect(String.join(problems.toArray(), delimiter: "\n"), "")
    }
}
