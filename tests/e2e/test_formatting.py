"""Formatting as an editor asks for it: the request and its edits over stdio, with a real client's capabilities and
options. What the formatter makes of a file is a unit test (C7)."""

from lsprotocol import types
from pytest_lsp import LanguageClient
from test_documents import open_document


async def test_a_document_uses_the_shared_layout(client: LanguageClient):
    # arrange
    uri = "untitled:a"
    open_document(client, uri, "func f() {\nlet x = 1\n}")

    # act: an indent of two, which the formatter's own style overrides
    edits = await client.text_document_formatting_async(
        types.DocumentFormattingParams(
            text_document=types.TextDocumentIdentifier(uri=uri),
            options=types.FormattingOptions(tab_size=2, insert_spaces=True),
        )
    )

    # assert: `let` indented by four, and a line break added at the end
    assert edits is not None
    assert [(e.range.start.line, e.range.start.character, e.new_text) for e in edits] == [
        (1, 0, "    let x = 1\n}\n"),
    ]


async def test_a_range_formats_its_complete_statement(client: LanguageClient):
    uri = "untitled:range"
    open_document(client, uri, "func f() {\ncall(a,\nb)\nx\n}\n")
    edits = await client.text_document_range_formatting_async(
        types.DocumentRangeFormattingParams(
            text_document=types.TextDocumentIdentifier(uri=uri),
            range=types.Range(
                start=types.Position(line=2, character=0),
                end=types.Position(line=2, character=1),
            ),
            options=types.FormattingOptions(tab_size=2, insert_spaces=True),
        )
    )
    assert edits is not None
    assert len(edits) == 1
    assert edits[0].range.start == types.Position(line=1, character=0)
    assert edits[0].range.end == types.Position(line=2, character=0)
    assert edits[0].new_text == "    call(a, "
