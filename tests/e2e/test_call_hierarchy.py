"""Call hierarchy items round trip through all three requests over stdio."""

import pytest
from lsprotocol import types
from pytest_lsp import LanguageClient

from conftest import CLIENTS, capabilities, loaded


@pytest.mark.parametrize("editor", CLIENTS)
async def test_call_hierarchy_round_trip(server: LanguageClient, tmp_path, editor):
    # arrange
    target = tmp_path / "a.cj"
    target.write_text("func target(): Unit {}\n")
    caller = tmp_path / "b.cj"
    caller.write_text("func caller(): Unit { target(); target() }\n")

    @server.feature(types.CLIENT_REGISTER_CAPABILITY)
    def register(params: types.RegistrationParams):
        pass

    result = await server.initialize_session(
        types.InitializeParams(
            capabilities=capabilities(editor),
            workspace_folders=[types.WorkspaceFolder(uri=tmp_path.as_uri(), name="ws")],
        )
    )
    await loaded(server)

    # act
    roots = await server.text_document_prepare_call_hierarchy_async(
        types.CallHierarchyPrepareParams(
            text_document=types.TextDocumentIdentifier(uri=target.as_uri()),
            position=types.Position(line=0, character=5),
        )
    )
    incoming = await server.call_hierarchy_incoming_calls_async(
        types.CallHierarchyIncomingCallsParams(item=roots[0])
    )
    outgoing = await server.call_hierarchy_outgoing_calls_async(
        types.CallHierarchyOutgoingCallsParams(item=incoming[0].from_)
    )

    # assert
    assert result.capabilities.call_hierarchy_provider
    assert len(roots) == len(incoming) == len(outgoing) == 1
    assert incoming[0].from_.name == "caller"
    assert incoming[0].from_.uri == caller.as_uri()
    assert outgoing[0].to.name == "target"
    assert outgoing[0].to.uri == target.as_uri()
    assert len(incoming[0].from_ranges) == 2
    assert outgoing[0].from_ranges == incoming[0].from_ranges

    await server.shutdown_session()
