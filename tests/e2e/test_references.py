"""References as an editor asks for them: the request over stdio, with a real client's capabilities, in a workspace the
server loaded. What each name means and where it is looked for is `loupe`'s tests; locations the handler's (C7)."""

import pathlib

import pytest
from lsprotocol import types
from pygls.uris import to_fs_path
from pytest_lsp import LanguageClient

from conftest import CLIENTS, capabilities, loaded

DECLARING = """\
func f(n: Int64): Int64 { n }
func f(b: Bool): Int64 { 0 }
"""

USING = """\
func g(): Int64 {
    f(1) + f(true) + f(2)
}
"""


@pytest.mark.parametrize("editor", CLIENTS)
async def test_the_uses_of_a_function_are_found_in_every_file(server: LanguageClient, tmp_path, editor):
    # arrange
    (tmp_path / "a.cj").write_text(DECLARING)
    (tmp_path / "b.cj").write_text(USING)

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

    async def references(file: str, line: int, character: int, declaration: bool):
        answer = await server.text_document_references_async(
            types.ReferenceParams(
                text_document=types.TextDocumentIdentifier(uri=(tmp_path / file).as_uri()),
                position=types.Position(line=line, character=character),
                context=types.ReferenceContext(include_declaration=declaration),
            )
        )
        return sorted(
            (pathlib.Path(to_fs_path(one.uri)).name, one.range.start.line, one.range.start.character)
            for one in answer or []
        )

    # act: the overload of `Int64`, declared in one file and called in another; not the other overload
    with_declaration = await references("b.cj", 1, 4, declaration=True)
    without_declaration = await references("a.cj", 0, 5, declaration=False)

    # assert
    assert result.capabilities.references_provider
    assert with_declaration == [("a.cj", 0, 5), ("b.cj", 1, 4), ("b.cj", 1, 21)]
    assert without_declaration == [("b.cj", 1, 4), ("b.cj", 1, 21)]

    await server.shutdown_session()
