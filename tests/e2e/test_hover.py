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
    builtin = await hover(2, 13)
    nothing = await hover(2, 1)

    # assert: a function called, its doc; a local, the type inferred for it; a type the language builds in, what the
    # docs say of it; nothing on a keyword
    assert isinstance(call.contents, types.MarkupContent)
    assert call.contents.kind == (types.MarkupKind.Markdown if markdown else types.MarkupKind.PlainText)
    assert "func twice(n: Int64): Int64" in call.contents.value
    assert "Twice `n`." in call.contents.value
    assert call.range == types.Range(start=types.Position(line=3, character=12),
                                     end=types.Position(line=3, character=17))
    assert "let k: Int64" in local.contents.value
    assert "type Int64" in builtin.contents.value
    assert nothing is None

    await server.shutdown_session()


@pytest.mark.parametrize("markup", [types.MarkupKind.Markdown, types.MarkupKind.PlainText])
async def test_generic_call_hover_keeps_markup_docs_and_utf8_range(
    server: LanguageClient, tmp_path, markup
):
    # arrange
    source = """\
/** Keeps `value`. */
func identity<T>(value: T): T { value }
func f() { /* 😀 */ identity(1) }
"""
    file = tmp_path / "generic.cj"
    file.write_text(source, encoding="utf-8")
    caps = types.ClientCapabilities(
        window=types.WindowClientCapabilities(work_done_progress=True),
        general=types.GeneralClientCapabilities(
            position_encodings=[types.PositionEncodingKind.Utf8]
        ),
        text_document=types.TextDocumentClientCapabilities(
            hover=types.HoverClientCapabilities(content_format=[markup])
        ),
    )

    @server.feature(types.CLIENT_REGISTER_CAPABILITY)
    def register(params: types.RegistrationParams):
        pass

    initialized = await server.initialize_session(
        types.InitializeParams(
            capabilities=caps,
            workspace_folders=[types.WorkspaceFolder(uri=tmp_path.as_uri(), name="ws")],
        )
    )
    await loaded(server)
    call_line = source.splitlines()[2]
    start = len(call_line.split("identity", 1)[0].encode("utf-8"))
    document = types.TextDocumentIdentifier(uri=file.as_uri())

    # act
    call = await server.text_document_hover_async(
        types.HoverParams(
            text_document=document,
            position=types.Position(line=2, character=start + 2),
        )
    )
    declaration = await server.text_document_hover_async(
        types.HoverParams(text_document=document, position=types.Position(line=1, character=7))
    )

    # assert
    assert initialized.capabilities.position_encoding == types.PositionEncodingKind.Utf8
    assert isinstance(call.contents, types.MarkupContent)
    assert call.contents.kind == markup
    assert "func identity<Int64>(value: Int64): Int64" in call.contents.value
    assert "Keeps `value`." in call.contents.value
    assert call.range == types.Range(
        start=types.Position(line=2, character=start),
        end=types.Position(line=2, character=start + len("identity")),
    )
    assert "func identity<T>(value: T): T" in declaration.contents.value
    assert declaration.contents.kind == markup
    assert "Keeps `value`." in declaration.contents.value

    await server.shutdown_session()
