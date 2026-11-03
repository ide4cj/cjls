"""New-file headers share source-change translation with other editor edits."""

import asyncio
from pathlib import Path
from urllib.parse import urlsplit
from urllib.request import url2pathname

import pytest
from lsprotocol import types
from pytest_lsp import LanguageClient

from conftest import capabilities, loaded
from test_documents import open_document


@pytest.mark.parametrize("versioned", [True, False])
async def test_package_header_is_an_insertion_in_the_open_buffer(
    server: LanguageClient, tmp_path, versioned
):
    # arrange
    (tmp_path / "cjpm.toml").write_text('[package]\nname = "app"\n')
    (tmp_path / "src").mkdir()
    (tmp_path / "src" / "main.cj").write_text("package app\nmain() {}\n")
    path = tmp_path / "src" / "new.cj"
    caps = capabilities("neovim")
    caps.workspace.apply_edit = True
    caps.workspace.workspace_edit.document_changes = versioned
    edits = asyncio.Queue()

    @server.feature(types.CLIENT_REGISTER_CAPABILITY)
    def register(_params):
        pass

    @server.feature(types.WORKSPACE_APPLY_EDIT)
    def apply_edit(params: types.ApplyWorkspaceEditParams):
        edits.put_nowait(params)
        return types.ApplyWorkspaceEditResult(applied=True)

    await server.initialize_session(types.InitializeParams(
        capabilities=caps,
        workspace_folders=[types.WorkspaceFolder(uri=tmp_path.as_uri(), name="app")],
        initialization_options={"macroExpansion": False},
    ))
    await loaded(server)

    # act
    open_document(server, path.as_uri(), " \t\r\n\n", version=3)
    params = await edits.get()

    # assert
    assert params.label == "package app"
    if versioned:
        assert params.edit.changes is None
        assert len(params.edit.document_changes) == 1
        document = params.edit.document_changes[0]
        edit_uri = document.text_document.uri
        assert document.text_document.version == 3
        text_edits = document.edits
    else:
        assert params.edit.document_changes is None
        assert len(params.edit.changes) == 1
        (edit_uri, text_edits), = params.edit.changes.items()
    uri = urlsplit(edit_uri)
    assert uri.scheme == "file"
    assert uri.netloc == ""
    assert Path(url2pathname(uri.path)) == path
    assert len(text_edits) == 1
    assert text_edits[0].range == types.Range(
        start=types.Position(line=0, character=0), end=types.Position(line=0, character=0)
    )
    assert text_edits[0].new_text == "package app\n"
    assert not path.exists()

    await server.shutdown_session()
