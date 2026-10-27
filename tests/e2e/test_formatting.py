"""Formatting as an editor asks for it: the request and its edits over stdio, with a real client's capabilities and
options. What the formatter makes of a file is a unit test (C7)."""

from pathlib import Path

from lsprotocol import types
from pytest_lsp import LanguageClient
from test_documents import open_document


async def test_saved_project_policy_overrides_editor_options(
    client: LanguageClient, tmp_path: Path
):
    # arrange
    config = tmp_path / "cjformat.toml"
    config.write_text('indent_width = 2\nsimple_if = "compact"\n')
    uri = (tmp_path / "a.cj").as_uri()
    open_document(client, uri, "func f() {\nif (a) { b } else { c }\n}\n")
    document = types.TextDocumentIdentifier(uri=uri)
    options = types.FormattingOptions(tab_size=8, insert_spaces=False)

    # act
    whole = await client.text_document_formatting_async(
        types.DocumentFormattingParams(text_document=document, options=options)
    )
    selected = await client.text_document_range_formatting_async(
        types.DocumentRangeFormattingParams(
            text_document=document,
            range=types.Range(
                start=types.Position(line=1, character=0),
                end=types.Position(line=1, character=27),
            ),
            options=options,
        )
    )
    config.write_text('indent_width = 6\nsimple_if = "compact"\n')
    reloaded = await client.text_document_formatting_async(
        types.DocumentFormattingParams(text_document=document, options=options)
    )

    # assert
    assert whole is not None and selected is not None and reloaded is not None
    assert [edit.new_text for edit in whole] == ["  "]
    assert [edit.new_text for edit in selected] == ["  "]
    assert [edit.new_text for edit in reloaded] == ["      "]


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
    # arrange
    uri = "untitled:range"
    open_document(client, uri, "func f() {\ncall(a,\nb)\nx\n}\n")

    # act
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

    # assert
    assert edits is not None
    assert len(edits) == 1
    assert edits[0].range.start == types.Position(line=1, character=0)
    assert edits[0].range.end == types.Position(line=2, character=0)
    assert edits[0].new_text == "    call(a, "
