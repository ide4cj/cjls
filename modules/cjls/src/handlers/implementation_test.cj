package cjls.handlers

import std.fs.Path
import std.unittest.*
import std.unittest.testmacro.*
import stdxx.Nullable
import cjls.lsp_types.*
import cjls.server.*

func implementationsOf(state: ServerState, path: Path, line: UInt32, character: UInt32): Nullable<DefinitionOrDefinitionLinks> {
    handleImplementation(state.snapshot(), ImplementationParams(textDocument: TextDocumentIdentifier(uri: uriOf(path)),
        position: Position(line: line, character: character)))
}

/**
 * The `Location`s of an answer as `file line:character-line:character`, the file by its name.
 */
func implementationPlaces(answer: Nullable<DefinitionOrDefinitionLinks>): Array<String> {
    let locations = match (answer) {
        case Nullable.Value(DefinitionOrDefinitionLinks.AsDefinition(Definition.AsLocations(locations))) => locations
        case _ => throw AssertException("no locations")
    }
    locations.map {
        one => let parts = one.uri.split("/")
        "${parts[parts.size - 1]} ${at(one.range.start)}-${at(one.range.end)}"
    }
}

@Test
class ImplementationHandlerTest {
    @TestCase
    func theImplementationsInEveryFileAreTheirNamesAsLocations() {
        // arrange - the emoji before `D` is two UTF-16 units and four bytes
        let (state, dir) = loaded([
            ("a.cj", "package m\ninterface I { func g(): String }\n"),
            ("b.cj", "package m\nclass C <: I { public func g(): String { \"\" } }\n/* 😀 */ class D <: I { public func g(): String { \"\" } }\n")
        ])

        // act
        let answer = implementationsOf(state, dir.join("a.cj"), 1, 19)

        // assert
        @Expect(implementationPlaces(answer), ["b.cj 1:27-1:28", "b.cj 2:36-2:37"])
    }

    @TestCase
    func aNameNothingImplementsIsNull() {
        // arrange
        let (state, dir) = loaded([("a.cj", "package m\nfunc f(): Unit {}\n")])

        // act
        let answer = implementationsOf(state, dir.join("a.cj"), 1, 5)

        // assert
        @Expect(answer.isNull())
    }
}
