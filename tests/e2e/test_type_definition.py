"""Type navigation advertised and served over stdio, independently of definition link support."""

import pytest
from lsprotocol import types
from pytest_lsp import LanguageClient

from conftest import loaded
from test_definition import targets


@pytest.mark.parametrize("links", [False, True])
async def test_type_definition_keeps_constructor_definition(server: LanguageClient, tmp_path, links):
    # arrange
    file = tmp_path / "main.cj"
    file.write_text("class User { init(id: Int64) {} }\nfunc f() { let user = User(42); user }\n")

    @server.feature(types.CLIENT_REGISTER_CAPABILITY)
    def register(params: types.RegistrationParams):
        pass

    initialized = await server.initialize_session(types.InitializeParams(
        capabilities=types.ClientCapabilities(
            window=types.WindowClientCapabilities(work_done_progress=True),
            text_document=types.TextDocumentClientCapabilities(
                definition=types.DefinitionClientCapabilities(link_support=not links),
                type_definition=types.TypeDefinitionClientCapabilities(link_support=links))),
        workspace_folders=[types.WorkspaceFolder(uri=tmp_path.as_uri(), name="ws")],
    ))
    await loaded(server)
    document = types.TextDocumentIdentifier(uri=file.as_uri())

    # act
    answers = [await server.text_document_type_definition_async(types.TypeDefinitionParams(
        text_document=document, position=types.Position(line=1, character=column)))
        for column in (15, 22, 32)]
    constructor = await server.text_document_definition_async(types.DefinitionParams(
        text_document=document, position=types.Position(line=1, character=22)))

    # assert
    assert initialized.capabilities.type_definition_provider is True
    for answer in answers:
        assert targets(answer) == [(file, 0, 6)]
        assert isinstance(answer[0], types.LocationLink if links else types.Location)
    assert targets(constructor) == [(file, 0, 13)]
    assert isinstance(constructor[0], types.Location if links else types.LocationLink)
    await server.shutdown_session()
