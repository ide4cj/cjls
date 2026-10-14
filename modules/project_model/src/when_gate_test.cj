package project_model

import std.collection.*
import std.fs.*
import std.sort.sort
import std.unittest.*
import std.unittest.testmacro.*
import cjsyntax.parse
import loupe.hir.whenOf

/**
 * The one file of this repository's code a `@When` may be in (D113): `hostArch`'s, cjpm deducing a
 * feature of `os.*` alone.
 */
const WHEN_OF_THE_ARCHITECTURE = "modules/platform/src/common/os.cj"

/**
 * Whether a `@When` may be in `file`, a path under the repository's root with `/`s: the
 * architecture's, and a test of a module that is not multiplatform, leaving out a test of another
 * platform (D101). `platform`'s tests are in their OS's set.
 */
func mayHaveWhen(file: String): Bool {
    file == WHEN_OF_THE_ARCHITECTURE || file.endsWith("_test.cj") && !file.startsWith("modules/platform/")
}

/**
 * Each `@When` of the `.cj` files under `dir`, every source set's, as `path:line: @When[…]`, the
 * path relative to `root` with `/`s.
 */
func whensUnder(dir: Path, root: String, found: ArrayList<String>): Unit {
    for (entry in Directory.readFrom(dir)) {
        if (entry.isDirectory()) {
            whensUnder(entry.path, root, found)
        } else if (entry.isRegular() && entry.name.endsWith(".cj")) {
            let name = entry.path.toString().replace("\\", "/").removePrefix(root + "/")
            let text = String.fromUtf8(File.readFrom(entry.path))
            for (node in parse(text).syntaxNode().descendants()) {
                if (let Some(annotation) <- whenOf(node)) {
                    let line = text[..annotation.syntax.textRange.start].count("\n") + 1
                    found.add("${name}:${line}: ${annotation.syntax.text()}")
                }
            }
        }
    }
}

@Test
class WhenGateTest {
    /**
     * What differs between platforms is `platform`'s `common` and `specific` (C17): a `@When` elsewhere
     * fails here with where it is.
     */
    @TestCase
    func theArchitectureAndTestsOfAnotherPlatformAreAloneInAWhen() {
        // arrange
        let root = workspaceRoot()
        let found = ArrayList<String>()

        // act
        whensUnder(root.join("modules").filePath.getOrThrow(), root.toString().replace("\\", "/"), found)

        // assert
        let misplaced = found.toArray().filter {one => !mayHaveWhen(one[..one.indexOf(":").getOrThrow()])}
        sort(misplaced)
        // a text, not an array: an array's `@Expect` of another size tells the sizes alone
        @Expect(String.join(misplaced, delimiter: "\n"), "")
        @Expect(found.iterator().any {one => one.startsWith("${WHEN_OF_THE_ARCHITECTURE}:")})
    }
}
