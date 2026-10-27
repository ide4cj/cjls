package cjls.handlers

import std.fs.Path
import std.unittest.*
import std.unittest.testmacro.*
import stdxx.Nullable
import cjls.lsp_types.*
import cjls.server.*

func referencesOf(
    state: ServerState,
    path: Path,
    line: UInt32,
    character: UInt32,
    includeDeclaration!: Bool = true
): Nullable<Array<Location>> {
    handleReferences(
        state.snapshot(),
        ReferenceParams(
            textDocument: TextDocumentIdentifier(uri: uriOf(path)),
            position: Position(line: line, character: character),
            context: ReferenceContext(includeDeclaration: includeDeclaration)
        )
    )
}

/**
 * `locations` as `file line:character-line:character`, the file by its name, to compare.
 */
func placesOf(answer: Nullable<Array<Location>>): Array<String> {
    let locations =
        match (answer) {
            case Nullable.Value(locations) => locations
            case _ => throw AssertException("no references")
        }
    locations
        .map {
            one =>
            let parts = one.uri.split("/")
            "${parts[parts.size - 1]} ${at(one.range.start)}-${at(one.range.end)}"
        }
}

@Test
class ReferencesHandlerTest {
    @TestCase
    func theUsesInEveryFileAreTheirRangesWithTheDeclarationWhenAskedFor() {
        // arrange - the emoji is two UTF-16 units and four bytes; the file asked in comes first
        let (state, dir) =
            loaded(
                [
                    ("a.cj", "package m\npublic func f(): String { \"😀\" }\n"),
                    ("b.cj", "package m\nfunc g(): String { \"😀\" + f() + f() }\n")
                ]
            )

        // act
        let all = referencesOf(state, dir.join("b.cj"), 1, 26)
        let uses = referencesOf(state, dir.join("b.cj"), 1, 26, includeDeclaration: false)

        // assert
        @Expect(placesOf(all), ["b.cj 1:26-1:27", "b.cj 1:32-1:33", "a.cj 1:12-1:13"])
        @Expect(placesOf(uses), ["b.cj 1:26-1:27", "b.cj 1:32-1:33"])
    }

    @TestCase
    func aNameNothingResolvesIsNull() {
        // arrange
        let (state, dir) = loaded([("a.cj", "func f(): Unit {\n    nothing\n}\n")])

        // act
        let answer = referencesOf(state, dir.join("a.cj"), 1, 4)

        // assert
        @Expect(answer.isNull())
    }
}
