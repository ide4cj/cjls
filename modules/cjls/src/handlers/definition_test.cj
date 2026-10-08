package cjls.handlers

import std.fs.{Path, remove}
import std.unittest.*
import std.unittest.testmacro.*
import stdx.log.NoopLogger
import stdxx.Nullable
import cjls.lsp_types.*
import cjls.server.*

/**
 * A state with the project of `files` loaded, as a client taking links, or not, finds it; the
 * directory is gone already, the files are in the state.
 */
func loaded(files: Array<(String, String)>, links!: Bool = true): (ServerState, Path) {
    let dir = workspaceOf(files)
    let state = initializedWith([dir], watches: false)
    state.locationLinks = links
    handleInitialized(state, Client(), NoopLogger(), InitializedParams())
    remove(dir, recursive: true)
    (state, dir)
}

func definitionOf(state: ServerState, path: Path, line: UInt32, character: UInt32): Nullable<DefinitionOrDefinitionLinks> {
    handleDefinition(state.snapshot(), DefinitionParams(textDocument: TextDocumentIdentifier(uri: uriOf(path)),
        position: Position(line: line, character: character)))
}

/**
 * `position` as `line:character`, to compare.
 */
func at(position: Position): String {
    "${position.line}:${position.character}"
}

func linksOf(answer: Nullable<DefinitionOrDefinitionLinks>): Array<LocationLink> {
    match (answer) {
        case Nullable.Value(DefinitionOrDefinitionLinks.AsDefinitionLinks(links)) => links
        case _ => throw AssertException("not links")
    }
}

@Test
class DefinitionTest {
    @TestCase
    func aNameGoesToItsDeclarationWholeAndItsNameInTheColumnsAgreedOn() {
        // arrange - the emoji is two UTF-16 units and four bytes
        let (state, dir) = loaded([("a.cj", "class A { let s = \"😀\" }\nfunc f(a: A) {}\n")])

        // act
        let links = linksOf(definitionOf(state, dir.join("a.cj"), 1, 10))

        // assert
        @Expect(links.size, 1)
        @Expect(links[0].targetUri, uriOf(dir.join("a.cj")))
        @Expect(at(links[0].targetRange.start), "0:0")
        @Expect(at(links[0].targetRange.end), "0:24")
        @Expect(at(links[0].targetSelectionRange.start), "0:6")
        @Expect(at(links[0].targetSelectionRange.end), "0:7")
    }

    @TestCase
    func aDeclarationOfAnotherFileIsInThatFile() {
        // arrange
        let (state, dir) = loaded([("a.cj", "func f() {\n    g()\n}\n"), ("b.cj", "\nfunc g() {}\n")])

        // act
        let links = linksOf(definitionOf(state, dir.join("a.cj"), 1, 4))

        // assert
        @Expect(links.size, 1)
        @Expect(links[0].targetUri, uriOf(dir.join("b.cj")))
        @Expect(at(links[0].targetSelectionRange.start), "1:5")
    }

    @TestCase
    func anOverloadGoesToEachOfItsFunctions() {
        // arrange
        let (state, dir) = loaded([("a.cj", "func g(n: Int64) {}\nfunc g(s: String) {}\nfunc f() {\n    g(1)\n}\n")])

        // act
        let links = linksOf(definitionOf(state, dir.join("a.cj"), 3, 4))

        // assert
        @Expect(links.map {link => link.targetSelectionRange.start.line}, [0u32, 1u32])
    }

    @TestCase
    func aClientTakingNoLinksGetsLocationsAtTheNames() {
        // arrange
        let (state, dir) = loaded([("a.cj", "class A {}\nfunc f(a: A) {}\n")], links: false)

        // act
        let answer = definitionOf(state, dir.join("a.cj"), 1, 10)

        // assert
        match (answer) {
            case Nullable.Value(DefinitionOrDefinitionLinks.AsDefinition(Definition.AsLocations(locations))) =>
                @Expect(locations.size, 1)
                @Expect(locations[0].uri, uriOf(dir.join("a.cj")))
                @Expect(at(locations[0].range.start), "0:6")
                @Expect(at(locations[0].range.end), "0:7")
            case _ => @Fail("not locations")
        }
    }

    @TestCase
    func aNameNothingResolvesIsNull() {
        // arrange
        let (state, dir) = loaded([("a.cj", "func f() {\n    nowhere()\n}\n")])

        // act
        let answer = definitionOf(state, dir.join("a.cj"), 1, 4)

        // assert
        @Expect(answer.isNull())
    }

    @TestCase
    func aDocumentTheServerDoesNotKnowIsNull() {
        // act
        let answer = handleDefinition(ServerState().snapshot(), DefinitionParams(
            textDocument: TextDocumentIdentifier(uri: URI), position: Position(line: 0, character: 0)))

        // assert
        @Expect(answer.isNull())
    }

    @TestCase[row in [
        (ClientCapabilities(textDocument: TextDocumentClientCapabilities(
            definition: DefinitionClientCapabilities(linkSupport: true))), true),
        (ClientCapabilities(textDocument: TextDocumentClientCapabilities(
            definition: DefinitionClientCapabilities())), false),
        (ClientCapabilities(), false)
    ]]
    func linksGoOnlyToAClientThatSaysItTakesThem(row: (ClientCapabilities, Bool)) {
        // arrange
        let (capabilities, links) = row
        let state = ServerState()

        // act
        handleInitialize(state, InitializeParams(processId: Nullable.Null, rootUri: Nullable.Null,
            capabilities: capabilities))

        // assert
        @Expect(state.locationLinks, links)
    }
}
