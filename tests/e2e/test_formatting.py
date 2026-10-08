"""Formatting as an editor asks for it: the request and its edits over stdio, with a real client's capabilities and
options. What the formatter makes of a file is a unit test (C7)."""

from lsprotocol import types
from pytest_lsp import LanguageClient
from test_documents import open_document


async def test_a_document_is_formatted_by_edits_of_its_whitespace(client: LanguageClient):
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
        (0, 10, "\n    "),
        (2, 1, "\n"),
    ]
