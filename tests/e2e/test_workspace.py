import pathlib

import pytest
from lsprotocol import types
from pygls.uris import to_fs_path
from pytest_lsp import LanguageClient

from conftest import CLIENTS, capabilities


@pytest.mark.parametrize("editor", CLIENTS)
async def test_workspace_symbol_finds_a_declaration_of_a_file_not_open(server: LanguageClient, tmp_path, editor):
    # arrange
    (tmp_path / "src").mkdir()
    (tmp_path / "src" / "a.cj").write_text("class Outer {\n    func findMe() {}\n}\n")
    (tmp_path / "target").mkdir()
    (tmp_path / "target" / "b.cj").write_text("func findMeToo() {}\n")
    registered: list[types.Registration] = []

    @server.feature(types.CLIENT_REGISTER_CAPABILITY)
    def register(params: types.RegistrationParams):
        registered.extend(params.registrations)

    await server.initialize_session(
        types.InitializeParams(
            capabilities=capabilities(editor),
            workspace_folders=[types.WorkspaceFolder(uri=tmp_path.as_uri(), name="ws")],
        )
    )

    # act
    symbols = await server.workspace_symbol_async(types.WorkspaceSymbolParams(query="findme"))

    # assert: `target/` is cjpm's output, never loaded
    assert [(s.name, s.container_name) for s in symbols] == [("findMe", "Outer")]
    # the same file, not the same text: on Windows the server sends the drive's letter lowercase
    assert pathlib.Path(to_fs_path(symbols[0].location.uri)) == tmp_path / "src" / "a.cj"
    assert symbols[0].location.range.start == types.Position(line=1, character=9)
    watches = capabilities(editor).workspace.did_change_watched_files
    if watches and watches.dynamic_registration:
        assert [r.method for r in registered] == ["workspace/didChangeWatchedFiles"]

    await server.shutdown_session()
