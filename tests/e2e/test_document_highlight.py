"""Document highlight as an editor asks for it: the request over stdio, with a real client's capabilities, in a
workspace the server loaded. What each name means is `loupe`'s tests; ranges and kinds the handler's (C7)."""

import pytest
from lsprotocol import types
from pytest_lsp import LanguageClient

from conftest import CLIENTS, capabilities, loaded

SOURCE = """\
class C {
    var x = 0
    func set(v: Int64): Unit {
        this.x = v
    }
}
func f(c: C, x: Int64): Int64 {
    c.x + x
}
"""


@pytest.mark.parametrize("editor", CLIENTS)
async def test_a_name_highlights_what_means_the_same(server: LanguageClient, tmp_path, editor):
    # arrange
    (tmp_path / "a.cj").write_text(SOURCE)
    file = tmp_path / "a.cj"

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

    async def highlights(line: int, character: int):
        answer = await server.text_document_document_highlight_async(
            types.DocumentHighlightParams(
                text_document=types.TextDocumentIdentifier(uri=file.as_uri()),
                position=types.Position(line=line, character=character),
            )
        )
        return [(h.range.start.line, h.range.start.character, h.kind) for h in answer or []]

    # act, assert: the field, written through `this`, read through a value; not the parameter of its name
    assert result.capabilities.document_highlight_provider
    assert await highlights(7, 6) == [
        (1, 8, types.DocumentHighlightKind.Write),
        (3, 13, types.DocumentHighlightKind.Write),
        (7, 6, types.DocumentHighlightKind.Read),
    ]
    # the parameter: its declaration, text, and its use
    assert await highlights(7, 10) == [
        (6, 13, types.DocumentHighlightKind.Text),
        (7, 10, types.DocumentHighlightKind.Read),
    ]

    await server.shutdown_session()
