"""Hover as an editor asks for it: the request over stdio, with a real client's capabilities, in a workspace
the server loaded. What a name shows is `loupe`'s tests; the Markdown and plain text the handler's (C7)."""

import pytest
from lsprotocol import types
from pytest_lsp import LanguageClient

from conftest import CLIENTS, capabilities, loaded

SOURCE = """\
/** Twice `n`. */
func twice(n: Int64): Int64 { n * 2 }
func main(): Int64 {
    let k = twice(1)
    k
}
"""


@pytest.mark.parametrize("editor", CLIENTS)
async def test_a_name_shows_its_declaration_or_its_type(server: LanguageClient, tmp_path, editor):
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

    async def hover(line: int, character: int):
        return await server.text_document_hover_async(
            types.HoverParams(
                text_document=types.TextDocumentIdentifier(uri=file.as_uri()),
                position=types.Position(line=line, character=character),
            )
        )

    hover_caps = capabilities(editor).text_document.hover
    markdown = hover_caps is not None and types.MarkupKind.Markdown in (hover_caps.content_format or [])

    # act
    call = await hover(3, 12)
    local = await hover(4, 4)
    nothing = await hover(2, 13)

    # assert: a function called, its doc; a local, the type inferred for it; nothing on a keyword
    assert isinstance(call.contents, types.MarkupContent)
    assert call.contents.kind == (types.MarkupKind.Markdown if markdown else types.MarkupKind.PlainText)
    assert "func twice(n: Int64): Int64" in call.contents.value
    assert "Twice `n`." in call.contents.value
    assert call.range == types.Range(start=types.Position(line=3, character=12),
                                     end=types.Position(line=3, character=17))
    assert "let k: Int64" in local.contents.value
    assert nothing is None

    await server.shutdown_session()
