"""Binary source roots are a replacement notification, independent of source navigation."""

import asyncio
import json

from lsprotocol import types

from conftest import capabilities


async def test_binary_roots_replace_after_manifest_reload(server, tmp_path):
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

    result = await server.initialize_session(types.InitializeParams(
        capabilities=capabilities("visual-studio-code"),
        workspace_folders=[types.WorkspaceFolder(uri=root.as_uri(), name="ws")],
        initialization_options={"cangjieHome": str(tmp_path / "no-sdk")},
    ))
    assert result.capabilities.experimental["binarySourceRoots"] is True
    first = await reports.get()
    assert source.as_uri() in first
    assert dep.as_uri() not in first

    model["binaries"] = []
    manifest.write_text(json.dumps(model))
    server.workspace_did_change_watched_files(types.DidChangeWatchedFilesParams(changes=[
        types.FileEvent(uri=manifest.as_uri(), type=types.FileChangeType.Changed),
    ]))
    second = await reports.get()
    assert source.as_uri() not in second
    await server.shutdown_session()
