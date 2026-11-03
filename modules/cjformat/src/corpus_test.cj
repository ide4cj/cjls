package cjformat

import std.collection.{ArrayList, collectArray}
import std.env.getVariable
import std.fs.{Directory, File, Path}
import std.sort.sort
import cjsyntax.{CjSyntaxNode, SyntaxKind, parse}
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
func formattingProblems(
    name: String,
    text: String,
    options!: FormatOptions = FormatOptions()
): Array<String> {
    let formatted = formatText(text, options: options) ?? return []
    // Import punctuation/order may change; the imported paths, aliases, conditions, visibility
    // and their multiplicities must not. The oracle does not call the production normalizer.
    let canonical = withoutImports(parse(text).syntaxNode())
    let canonicalFormatted = withoutImports(parse(formatted).syntaxNode())
    let problems = ArrayList<String>()
    if (significant(canonicalFormatted) != significant(canonical)) {
        problems.add("${name}: formatting changed tokens outside imports")
    }
    if (importInventory(text) != importInventory(formatted)) {
        problems.add("${name}: formatting changed imported names, aliases or conditions")
    }
    if (importComments(text) != importComments(formatted)) {
        problems.add("${name}: formatting changed comment order or content")
    }
    let reparsed = parse(formatted)
    if (!reparsed.errors.isEmpty()) {
        problems.add("${name}: formatting introduced syntax errors: ${reparsed.errors}")
    }
    if (structure(canonical) != structure(canonicalFormatted)) {
        problems.add("${name}: formatting changed the syntax tree")
    }
    if (formatText(formatted, options: options) != Some(formatted)) {
        problems.add("${name}: formatting it twice changes it again")
    }
    if (!problems.isEmpty()) {
        if (let Some(dir) <- getVariable("CJFORMAT_FAILURES")) {
            let path = Path(dir).join(name.replace("/", "_").replace("\\", "_"))
            File.writeTo(path, formatted.toArray())
            File.writeTo(
                Path("${path}.second"),
                (formatText(formatted, options: options) ?? "<syntax errors>").toArray()
            )
            File.writeTo(
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
 * Real code keeps non-import tokens and syntax plus the complete import inventory, reparses successfully,
 * and stays unchanged on a second formatting pass.
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
            problems.add(
                all: formattingProblems(
                    file.toString(),
                    text,
                    options: FormatOptions(simpleIf: SimpleIf.Compact)
                )
            )
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

/**
 * Remove imports before comparing the rest of the tree; their comments are checked separately.
 */
private func withoutImports(n: CjSyntaxNode): String {
    if (n.kind == SyntaxKind.ImportDecl) {
        return "\n"
    }
    if (isOpaque(n.kind)) {
        return n.text()
    }
    let out = StringBuilder()
    for (child in n.childrenWithTokens()) {
        match (child) {
            case SyntaxElement.Node(node) => out.append(withoutImports(node))
            case SyntaxElement.Token(token) => out.append(token.text())
        }
    }
    out.toString()
}

/**
 * Compare a sorted multiset of fully qualified imports, rather than their grouping syntax.
 */
private func importInventory(text: String): Array<String> {
    let inventory = ArrayList<String>()
    for (decl in parse(text).syntaxNode().children() where decl.kind == SyntaxKind.ImportDecl) {
        let header = StringBuilder()
        for (element in decl.descendantsWithTokens()) {
            let token = element.asToken() ?? continue
            if (token.kind == SyntaxKind.ImportKw) {
                break
            }
            if (!token.kind.isTrivia()) {
                let value = token.text()
                header.append("${value.size}:${value}")
            }
        }
        for (tree in decl.children() where tree.kind == SyntaxKind.ImportTree) {
            inventoryPaths(tree, "", header.toString(), inventory)
        }
    }
    let result = inventory.toArray()
    sort(result)
    result
}

/**
 * Expand lists independently of production grouping so canonicalization cannot hide a changed import.
 */
private func inventoryPaths(
    tree: CjSyntaxNode,
    prefix: String,
    header: String,
    inventory: ArrayList<String>
): Unit {
    var path = prefix
    for (part in tree.childrenWithTokens()) {
        if (let Some(node) <- part.asNode()) {
            if (node.kind == SyntaxKind.ImportTreeList) {
                let members =
                    node.children().filter { n => n.kind == SyntaxKind.ImportTree } |> collectArray
                // Even a parser-accepted empty list must not disappear silently.
                if (members.isEmpty()) {
                    inventory.add("${header}|${path}{}")
                }
                for (member in members) {
                    inventoryPaths(member, path, header, inventory)
                }
                return
            }
            if (node.kind == SyntaxKind.NameRef) {
                path = "${path}${node.text().trimAscii()}"
            } else if (node.kind == SyntaxKind.ImportAlias) {
                let tokens =
                    node
                        .descendantsWithTokens()
                        .filterMap<String> {
                            element =>
                            match (element) {
                                case SyntaxElement.Token(token) where !token.kind.isTrivia() =>
                                    Some(token.text())
                                case _ => None
                            }
                        } |>
                        collectArray
                path = "${path} ${String.join(tokens, delimiter: " ")}"
            }
        } else if (
            part.kind == SyntaxKind.Dot || part.kind == SyntaxKind.ColonColon ||
                part.kind == SyntaxKind.Star
        ) {
            path = "${path}${part.asToken().getOrThrow().text()}"
        }
    }
    inventory.add("${header}|${path}")
}

/**
 * Imports are omitted from the token/tree check, so compare all comments separately in source order.
 */
private func importComments(text: String): Array<String> {
    parse(text)
        .syntaxNode()
        .descendantsWithTokens()
        .filterMap {
            element =>
            match (element) {
                case SyntaxElement.Token(token) where isComment(token.kind) =>
                    Some(
                        token
                            .text()
                            .replace(" ", "")
                            .replace("\t", "")
                            .replace("\r", "")
                            .replace("\n", "")
                    )
                case _ => None
            }
        } |>
        collectArray
}

@Test
class ImportInventoryTest {
    @TestCase[row in [
        ("import p.B\nimport p.A", "import p.{A, B}", true),
        ("import p.*\nimport p.A", "import p.*", false),
        ("import p.A as X", "import p.A as Y", false),
        ("public import p.A", "import p.A", false),
        ("import p.A\nimport p.A", "import p.A", false),
        ("import p::A", "import p.A", false),
        ("@When[os == \"Linux\"]\nimport p.A", "@When[os == \"Windows\"]\nimport p.A", false)
    ]]
    func theOracleAllowsRegroupingButDetectsChangedImportSemantics(
        row: (String, String, Bool)
    ): Unit {
        // arrange
        let (before, after, expected) = row

        // act
        let same = importInventory(before) == importInventory(after)

        // assert
        @Expect(same, expected)
    }
}
