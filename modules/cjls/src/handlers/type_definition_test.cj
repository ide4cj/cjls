package cjls.handlers

import std.fs.Path
import std.unittest.*
import std.unittest.testmacro.*
import stdx.log.NoopLogger
import cjls.lsp_types.*
import cjls.server.{Client, ServerState}
import rope.Encoding
import stdxx.Nullable

/**
 * Asks for a type definition using a fresh snapshot.
 */
func typeDefinitionOf(
    state: ServerState,
    path: Path,
    line: UInt32,
    character: UInt32
): Nullable<DefinitionOrDefinitionLinks> {
    handleTypeDefinition(
        state.snapshot(),
        TypeDefinitionParams(
            textDocument: TextDocumentIdentifier(uri: uriOf(path)),
            position: Position(line: line, character: character)
        )
    )
}

@Test
class TypeDefinitionTest {
    @TestCase[row in [(Encoding.Utf8, 4u32), (Encoding.Utf16, 2u32), (Encoding.Utf32, 1u32)]]
    func linksUseTheSnapshotEncodingForBothRequestAndTarget(row: (Encoding, UInt32)) {
        // arrange
        let (encoding, width) = row
        let (state, dir) =
            loaded(
                [
                    ("types.cj", "/*😀*/ class User {}"),
                    ("main.cj", "func f(user: User) { /*😀*/ user }")
                ]
            )
        state.encoding = encoding
        state.typeDefinitionLinks = true
        state.locationLinks = false

        // act
        let links = linksOf(typeDefinitionOf(state, dir.join("main.cj"), 0, 26 + width))

        // assert
        @Assert(links.size, 1)
        @Expect(links[0].targetUri, uriOf(dir.join("types.cj")))
        @Expect(links[0].targetRange.start.character, 0u32)
        @Expect(links[0].targetRange.end.character, 18 + width)
        @Expect(links[0].targetSelectionRange.start.character, 11 + width)
        @Expect(links[0].targetSelectionRange.end.character, 15 + width)
    }

    @TestCase
    func definitionLinkSupportDoesNotEnableTypeDefinitionLinks() {
        // arrange
        let (state, dir) = loaded([("main.cj", "class User {}\nfunc f(user: User) { user }")])

        // act
        let result = typeDefinitionOf(state, dir.join("main.cj"), 1, 21)

        // assert
        match (result) {
            case Nullable.Value(
                    DefinitionOrDefinitionLinks.AsDefinition(Definition.AsLocations(locations))
                ) =>
                @Assert(locations.size, 1)
                @Expect(locations[0].uri, uriOf(dir.join("main.cj")))
                @Expect(at(locations[0].range.start), "0:6")
                @Expect(at(locations[0].range.end), "0:10")
            case _ => @Fail("expected locations")
        }
    }

    @TestCase[code in ["func f() { missing }", "func f() { let n = 1; n }"]]
    func unresolvedAndPrimitiveTypesReturnNull(code: String) {
        // arrange
        let (state, dir) = loaded([("main.cj", code)])

        // act
        let result = typeDefinitionOf(state, dir.join("main.cj"), 0, UInt32(code.size - 3))

        // assert
        @Expect(result.isNull())
    }

    @TestCase
    func unknownDocumentsReturnNull() {
        // arrange
        let state = ServerState()

        // act
        let result =
            handleTypeDefinition(
                state.snapshot(),
                TypeDefinitionParams(
                    textDocument: TextDocumentIdentifier(uri: URI),
                    position: Position(line: 0, character: 0)
                )
            )

        // assert
        @Expect(result.isNull())
    }

    @TestCase[row in [
        (ClientCapabilities(), false, false),
        (ClientCapabilities(textDocument: TextDocumentClientCapabilities(
            definition: DefinitionClientCapabilities(linkSupport: true))), true, false),
        (ClientCapabilities(textDocument: TextDocumentClientCapabilities(
            typeDefinition: TypeDefinitionClientCapabilities(linkSupport: true))), false, true),
        (ClientCapabilities(textDocument: TextDocumentClientCapabilities(
            typeDefinition: TypeDefinitionClientCapabilities())), false, false)
    ]]
    func initializationNegotiatesLinksForEachMethod(row: (ClientCapabilities, Bool, Bool)) {
        // arrange
        let (caps, definition, typeDefinition) = row
        let state = ServerState()

        // act
        handleInitialize(
            state,
            Client(),
            NoopLogger(),
            InitializeParams(processId: Nullable.Null, rootUri: Nullable.Null, capabilities: caps)
        )
        let snap = state.snapshot()

        // assert
        @Expect(snap.locationLinks, definition)
        @Expect(snap.typeDefinitionLinks, typeDefinition)
    }

    @TestCase
    func generatedTypeTargetsAreMappedIntoTheExpandedDocument() {
        // arrange
        let (state, dir) = macroWorkspace()
        state.typeDefinitionLinks = true
        expandAndOpen(state, dir)

        // act
        let links = linksOf(typeDefinitionOf(state, expandedOf(dir), 6, 13))

        // assert
        removeWorkspace(dir)
        @Assert(links.size, 1)
        @Expect(links[0].targetUri, uriOf(expandedOf(dir)))
        @Expect(at(links[0].targetSelectionRange.start), "5:6")
        @Expect(at(links[0].targetSelectionRange.end), "5:9")
    }
}
