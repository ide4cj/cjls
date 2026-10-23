"""Semantic tokens as an editor asks for them: what the unit tests cannot see is the request and its answer over stdio,
with a real client's capabilities. What each token is, is a unit test (C7)."""

from lsprotocol import types
from pytest_lsp import LanguageClient
from test_documents import open_document


async def test_a_document_is_highlighted_from_its_start(client: LanguageClient):
    # arrange
    uri = "untitled:a"
    open_document(client, uri, "class A {}\nlet b = 1")

    # act
    tokens = await client.text_document_semantic_tokens_full_async(
        types.SemanticTokensParams(text_document=types.TextDocumentIdentifier(uri=uri))
    )

    # assert: five numbers a token; `class` first, a keyword, the legend's first type, unless the
    # editor's grammar names it, and `A` is first (D105)
    assert tokens is not None
    assert len(tokens.data) % 5 == 0
    semantic_tokens = client.capabilities.text_document.semantic_tokens
    if semantic_tokens.augments_syntax_tokens:
        assert list(tokens.data[:3]) == [0, 6, 1]
    else:
        assert list(tokens.data[:5]) == [0, 0, 5, 0, 0]
    # `let` starts the next line
    assert [tokens.data[i] for i in range(0, len(tokens.data), 5)].count(1) == 1


async def test_interpolation_boundaries_are_operators_over_an_editors_grammar(client: LanguageClient):
    uri = "untitled:interpolation"
    text = 'main() { let n = 1; let s = "${n}" }'
    open_document(client, uri, text)
    tokens = await client.text_document_semantic_tokens_full_async(
        types.SemanticTokensParams(text_document=types.TextDocumentIdentifier(uri=uri))
    )
    assert tokens is not None
    # The standard legend keeps operator at index 4; every editor gets the boundaries,
    # even when ordinary operators/literals are left to its base grammar (D148).
    column = 0
    found = {}
    for offset in range(0, len(tokens.data), 5):
        line_delta, start_delta, length, kind, _ = tokens.data[offset:offset + 5]
        assert line_delta == 0
        column += start_delta
        found[text[column:column + length]] = kind
    assert found["${"] == 4
    assert found["}"] == 4
