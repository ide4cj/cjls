"""Binary source roots are a replacement notification, independent of source navigation."""

import asyncio
import json
import pathlib

from lsprotocol import types
from pygls.uris import to_fs_path

from conftest import capabilities


async def test_binary_roots_replace_after_manifest_reload(server, tmp_path):
    # arrange
    root = tmp_path / "ws"
    root.mkdir()
    source = tmp_path / "binary sources #1"
    source.mkdir()
    (source / "lib.cj").write_text("package lib\n")
    dep = root / "dep"
    dep.mkdir()
    (dep / "main.cj").write_text("package dep\n")
    manifest = root / "cj-project.json"
    model = {
        "modules": [{"name": "dep", "root": "dep", "member": False,
                     "packages": [{"name": "dep", "dir": "dep", "files": ["main.cj"]}]}],
        "binaries": [{"name": "lib", "paths": [], "sources": str(source)}],
    }
    manifest.write_text(json.dumps(model))
    reports = asyncio.Queue()

    @server.feature("cjls/binarySourceRoots")
    def roots(params):
        reports.put_nowait(params.roots)

    @server.feature(types.CLIENT_REGISTER_CAPABILITY)
    def register(_params):
        pass

    # act
    result = await server.initialize_session(types.InitializeParams(
        capabilities=capabilities("visual-studio-code"),
        workspace_folders=[types.WorkspaceFolder(uri=root.as_uri(), name="ws")],
        initialization_options={"cangjieHome": str(tmp_path / "no-sdk")},
    ))
    # Compare paths so Windows drive-letter casing and URI escaping are handled.
    first = [pathlib.Path(to_fs_path(uri)) for uri in await reports.get()]

    # assert
    assert result.capabilities.experimental["binarySourceRoots"] is True
    assert source in first
    assert dep not in first

    # act: a manifest reload replaces the previous roots
    model["binaries"] = []
    manifest.write_text(json.dumps(model))
    server.workspace_did_change_watched_files(types.DidChangeWatchedFilesParams(changes=[
        types.FileEvent(uri=manifest.as_uri(), type=types.FileChangeType.Changed),
    ]))
    second = [pathlib.Path(to_fs_path(uri)) for uri in await reports.get()]

    # assert
    assert source not in second
    await server.shutdown_session()
