"""Completion as an editor asks for it: the request over stdio, with a real client's capabilities, in a
workspace the server loaded, and the resolve of one item. What a position lists is `loupe`'s tests; the
items, their edits and the resolve the handler's (C7)."""

import pytest
from lsprotocol import types
from pytest_lsp import LanguageClient

from conftest import CLIENTS, capabilities, loaded

SOURCE = """\
/** A point. */
class Point {
    let x = 1
    /** Its norm. */
    func norm(): Int64 { x }
}
func main(): Int64 {
    let p = Point()
    p.
    p.norm()
}
"""


@pytest.mark.parametrize("editor", CLIENTS)
async def test_a_dot_lists_the_members_and_resolve_adds_the_detail(server: LanguageClient, tmp_path, editor):
    # arrange
    file = tmp_path / "a.cj"
    file.write_text(SOURCE)

    @server.feature(types.CLIENT_REGISTER_CAPABILITY)
    def register(params: types.RegistrationParams):
        pass

    await server.initialize_session(
        types.InitializeParams(
            capabilities=capabilities(editor),
            workspace_folders=[types.WorkspaceFolder(uri=tmp_path.as_uri(), name="ws")],
        )
    )
    await loaded(server)

    async def complete(line: int, character: int):
        return await server.text_document_completion_async(
            types.CompletionParams(
                text_document=types.TextDocumentIdentifier(uri=file.as_uri()),
                position=types.Position(line=line, character=character),
            )
        )

    # act
    answer = await complete(8, 6)
    nothing = await complete(0, 4)

    # assert: the members of the value before the dot, an edit at the cursor, no detail yet
    assert isinstance(answer, types.CompletionList)
    assert not answer.is_incomplete
    assert [item.label for item in answer.items] == ["norm", "x"]
    norm = answer.items[0]
    assert norm.kind == types.CompletionItemKind.Function
    assert norm.detail is None
    assert isinstance(norm.text_edit, types.TextEdit)
    assert norm.text_edit.range == types.Range(start=types.Position(line=8, character=6),
                                               end=types.Position(line=8, character=6))
    assert norm.text_edit.new_text == "norm"
    assert nothing is None

    # act: the item resolved
    resolved = await server.completion_item_resolve_async(norm)

    # assert: its declaration and its doc comment
    assert resolved.label == "norm"
    assert resolved.detail == "func norm(): Int64"
    assert isinstance(resolved.documentation, types.MarkupContent)
    assert "Its norm." in resolved.documentation.value
