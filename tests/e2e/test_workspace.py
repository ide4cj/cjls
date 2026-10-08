import pathlib

import pytest
from lsprotocol import types
from lsprotocol.converters import get_converter
from pygls.uris import to_fs_path
from pytest_lsp import LanguageClient

from conftest import CLIENTS, capabilities, loaded


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

    await loaded(server)

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


@pytest.mark.parametrize("editor", CLIENTS)
async def test_a_folder_gone_or_come_is_followed_from_one_event_for_it(server: LanguageClient, tmp_path, editor):
    # arrange
    root = tmp_path / "ws"
    (root / "src" / "a").mkdir(parents=True)
    (root / "src" / "a" / "x.cj").write_text("func findMe() {}\n")
    registered: list[types.Registration] = []

    @server.feature(types.CLIENT_REGISTER_CAPABILITY)
    def register(params: types.RegistrationParams):
        registered.extend(params.registrations)

    await server.initialize_session(
        types.InitializeParams(
            capabilities=capabilities(editor),
            workspace_folders=[types.WorkspaceFolder(uri=root.as_uri(), name="ws")],
        )
    )
    await loaded(server)

    async def found() -> list[str]:
        symbols = await server.workspace_symbol_async(types.WorkspaceSymbolParams(query="findme"))
        return [pathlib.Path(to_fs_path(s.location.uri)).relative_to(root).as_posix() for s in symbols]

    # act: VS Code reports a folder come or gone as one event for it, not one per file under it
    (root / "src" / "a").rename(tmp_path / "away")
    server.workspace_did_change_watched_files(
        types.DidChangeWatchedFilesParams(
            changes=[types.FileEvent(uri=(root / "src" / "a").as_uri(), type=types.FileChangeType.Deleted)]
        )
    )
    await loaded(server, 2)
    after_gone = await found()
    (tmp_path / "away").rename(root / "src" / "b")
    server.workspace_did_change_watched_files(
        types.DidChangeWatchedFilesParams(
            changes=[types.FileEvent(uri=(root / "src" / "b").as_uri(), type=types.FileChangeType.Created)]
        )
    )
    await loaded(server, 3)
    after_come = await found()

    # assert: the server follows such an event, and a watcher of the editor's lets it through
    assert after_gone == []
    assert after_come == ["src/b/x.cj"]
    watches = capabilities(editor).workspace.did_change_watched_files
    if watches and watches.dynamic_registration:
        watchers = [
            watcher
            for registration in registered
            for watcher in get_converter()
            .structure(registration.register_options, types.DidChangeWatchedFilesRegistrationOptions)
            .watchers
        ]
        come_or_gone = types.WatchKind.Create | types.WatchKind.Delete
        # a relative pattern, or a glob of the root's path for a client without them
        globs = [w.glob_pattern if isinstance(w.glob_pattern, str) else w.glob_pattern.pattern for w in watchers]
        assert any(g.split("/")[-2:] == ["**", "*"] and w.kind == come_or_gone for g, w in zip(globs, watchers))

    await server.shutdown_session()
