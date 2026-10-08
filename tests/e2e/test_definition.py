"""Go to definition as an editor asks for it: the request over stdio, with a real client's capabilities, in a
workspace the server loaded. What each name resolves to is `loupe`'s tests; links and their ranges the handler's (C7)."""

import pathlib

import pytest
from lsprotocol import types
from pygls.uris import to_fs_path
from pytest_lsp import LanguageClient

from conftest import CLIENTS, capabilities, loaded

SOURCE = """\
class K {
    func f(): Int64 { 1 }
}
func g(n: Int64): Int64 { n }
func g(s: String): Int64 { 0 }
func main(): Int64 {
    let k: K = K()
    k.f() + g(1)
}
"""


def targets(answer) -> list[tuple[pathlib.Path, int, int]]:
    """Where each target of a definition is: its file, and the line and column of its name."""
    if answer is None:
        return []
    found = answer if isinstance(answer, list) else [answer]
    return [
        (pathlib.Path(to_fs_path(t.target_uri)), t.target_selection_range.start.line,
         t.target_selection_range.start.character)
        if isinstance(t, types.LocationLink)
        else (pathlib.Path(to_fs_path(t.uri)), t.range.start.line, t.range.start.character)
        for t in found
    ]


@pytest.mark.parametrize("editor", CLIENTS)
async def test_a_name_goes_to_its_declarations(server: LanguageClient, tmp_path, editor):
    # arrange
    (tmp_path / "a.cj").write_text(SOURCE)
    file = tmp_path / "a.cj"

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

    async def definition(line: int, character: int):
        return await server.text_document_definition_async(
            types.DefinitionParams(
                text_document=types.TextDocumentIdentifier(uri=file.as_uri()),
                position=types.Position(line=line, character=character),
            )
        )

    # act, assert: a type, a name in a body, a member after a `.`, an overload
    assert targets(await definition(6, 11)) == [(file, 0, 6)]
    assert targets(await definition(7, 4)) == [(file, 6, 8)]
    assert targets(await definition(7, 6)) == [(file, 1, 9)]
    assert targets(await definition(7, 12)) == [(file, 3, 5), (file, 4, 5)]
    # `Int64` is built in: nothing to go to
    assert await definition(3, 10) is None
    # a link where the client takes one
    definition_caps = capabilities(editor).text_document.definition
    if definition_caps and definition_caps.link_support:
        assert isinstance((await definition(6, 11))[0], types.LocationLink)

    await server.shutdown_session()
