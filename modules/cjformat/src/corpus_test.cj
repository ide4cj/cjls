package cjformat

import std.collection.{ArrayList, collectArray}
import std.env.getVariable
import std.fs.{Directory, File, Path}
import cjsyntax.{SyntaxKind, parse}
import ginkgo.SyntaxElement

/**
 * The tokens of `text` the formatter has to keep: all but whitespace, a comment without the
 * whitespace it may move or drop.
 */
private func significant(text: String): Array<String> {
    parse(text)
        .syntaxNode()
        .descendantsWithTokens()
        .filterMap {
            element =>
            match (element) {
                case SyntaxElement.Token(t) where isSpace(t.kind) => None
                case SyntaxElement.Token(t) where isComment(t.kind) =>
                    Some(
                        t
                            .text()
                            .replace(" ", "")
                            .replace("\t", "")
                            .replace("\r", "")
                            .replace("\n", "")
                    )
                case SyntaxElement.Token(t) => Some(t.text())
                case _ => None
            }
        } |>
        collectArray
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
    let reparsed = parse(formatted)
    if (!reparsed.errors.isEmpty()) {
        problems.add("${name}: formatting introduced syntax errors: ${reparsed.errors}")
    }
    if (structure(text) != structure(formatted)) {
        problems.add("${name}: formatting changed the syntax tree")
    }
    if (formatText(formatted) != Some(formatted)) {
        problems.add("${name}: formatting it twice changes it again")
    }
    if (!problems.isEmpty()) {
        if (let Some(dir) <- getVariable("CJFORMAT_FAILURES")) {
            let path = Path(dir).join(name.replace("/", "_").replace("\\", "_"))
            File.writeTo(path, formatted.toArray())
            File
                .writeTo(
                    Path("${path}.second"),
                    (formatText(formatted) ?? "<syntax errors>").toArray()
                )
            File
                .writeTo(
                    Path("${path}.problems"),
                    String.join(problems.toArray(), delimiter: "\n").toArray()
                )
        }
    }
    problems.toArray()
}

/**
 * Collects source files recursively, excluding build output, hidden directories and symlinks.
 */
private func cjFilesUnder(dir: Path, files: ArrayList<Path>): Unit {
    for (info in Directory.readFrom(dir) where !info.isSymbolicLink()) {
        if (info.isDirectory() && info.name != "target" && !info.name.startsWith(".")) {
            cjFilesUnder(info.path, files)
        } else if (info.isRegular() && info.name.endsWith(".cj")) {
            files.add(info.path)
        }
    }
}

/**
 * A formatter over real code preserves tokens and syntax, produces parseable output, and
 * leaves its own output unchanged.
 */
@Test
@Tag[gate]
class CorpusTest {
    @TestCase
    func thisRepositoryFormatsToTheSameTokensAndStaysFormatted(): Unit {
        check(Path("modules"))
    }

    /**
     * Over the corpus `CJFORMAT_CORPUS` names, such as the compiler's tests; nothing without it.
     */
    @TestCase
    func aCorpusFormatsToTheSameTokensAndStaysFormatted(): Unit {
        if (let Some(corpus) <- getVariable("CJFORMAT_CORPUS")) {
            check(Path(corpus))
        }
    }

    private func check(root: Path): Unit {
        // arrange
        let files = ArrayList<Path>()
        cjFilesUnder(root, files)

        // act
        let problems = ArrayList<String>()
        for (file in files) {
            let text =
                try {
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

/**
 * Newlines can change a call into a separate statement without changing any token.
 */
private func structure(text: String): Array<SyntaxKind> {
    parse(text)
        .syntaxNode()
        .descendantsWithTokens()
        .filter { e => !e.kind.isTrivia() }
        .map { e => e.kind } |>
        collectArray
}
