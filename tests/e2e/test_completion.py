"""Completion as an editor asks for it: the request over stdio, with a real client's capabilities, in a workspace
the server loaded, and the item resolved. What a position lists is `loupe`'s tests; the items the handler's (C7)."""

import pytest
from lsprotocol import types
from pytest_lsp import LanguageClient

from conftest import CLIENTS, capabilities, loaded

SOURCE = """\
struct Point {
    /** How far right. */
    public let x: Int64 = 1
    public func norm(): Int64 { x }
}
func main(): Int64 {
    let p = Point()
    p.
    0
}
"""


@pytest.mark.parametrize("editor", CLIENTS)
async def test_a_dot_lists_the_members_and_resolves_their_docs(server: LanguageClient, tmp_path, editor):
    # arrange
    file = tmp_path / "a.cj"
    file.write_text(SOURCE)

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
    answer = await server.text_document_completion_async(
        types.CompletionParams(
            text_document=types.TextDocumentIdentifier(uri=file.as_uri()),
            position=types.Position(line=7, character=6),
            context=types.CompletionContext(trigger_kind=types.CompletionTriggerKind.TriggerCharacter,
                                            trigger_character="."),
        )
    )
    x = next(item for item in answer.items if item.label == "x")
    resolved = await server.completion_item_resolve_async(x)

    # assert: advertised with `.` to trigger it; the members, inserted at the cursor; the declaration and the doc
    # comment on resolve
    assert "." in result.capabilities.completion_provider.trigger_characters
    assert result.capabilities.completion_provider.resolve_provider
    assert isinstance(answer, types.CompletionList)
    assert {"norm", "x"} <= {item.label for item in answer.items}
    assert x.text_edit.range == types.Range(start=types.Position(line=7, character=6),
                                            end=types.Position(line=7, character=6))
    assert resolved.detail == "public let x: Int64"
    assert "How far right." in resolved.documentation.value

    await server.shutdown_session()
