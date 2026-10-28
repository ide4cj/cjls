"""Git dependencies use cjpm's actual lock/cache and follow lock updates over LSP."""

import shutil
import subprocess

import pytest
from lsprotocol import types
from pytest_lsp import LanguageClient

from conftest import CLIENTS, capabilities, loaded
from test_definition import targets


def git(repository, *args):
    return subprocess.run(
        ["git", "-C", str(repository), *args], check=True, capture_output=True, text=True, timeout=30,
    ).stdout.strip()


def update(project):
    return subprocess.run(
        ["cjpm", "update", "--skip-script"], cwd=project, capture_output=True, text=True, timeout=60,
    )


@pytest.mark.parametrize("editor", CLIENTS)
async def test_git_workspace_navigation_follows_the_locked_commit(server: LanguageClient, tmp_path, editor):
    # arrange: a real local Git workspace, resolved by cjpm into a private cache
    if shutil.which("cjpm") is None or shutil.which("git") is None:
        pytest.skip("cjpm and git are needed for the local dependency integration")
    remote = tmp_path / "remote"
    source = remote / "modules" / "dep" / "src" / "lib.cj"
    source.parent.mkdir(parents=True)
    source.write_text("package dep\npublic class Remote {}\n")
    (remote / "cjpm.toml").write_text('[workspace]\nmembers = ["modules/dep"]\n')
    (remote / "modules" / "dep" / "cjpm.toml").write_text(
        '[package]\nname = "dep"\nversion = "1.0.0"\ncjc-version = "1.3.0"\noutput-type = "static"\n'
    )
    git(remote, "init", "-b", "main")
    git(remote, "add", ".")
    git(remote, "-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "-m", "first")
    first = git(remote, "rev-parse", "HEAD")
    project = tmp_path / "app"
    (project / "src").mkdir(parents=True)
    file = project / "src" / "main.cj"
    file.write_text("import dep.*\nfunc use(x: Remote): Unit {}\n")
    (project / "cjpm.toml").write_text(
        '[package]\nname = "app"\nversion = "1.0.0"\ncjc-version = "1.3.0"\noutput-type = "static"\n'
        f'[dependencies]\ndep = {{git = "{remote.as_uri()}", branch = "main"}}\n'
    )
    (project / "cangjie-repo.toml").write_text('[repository.cache]\npath = "../cache"\n')
    initial_update = update(project)
    assert initial_update.returncode == 0, initial_update.stdout + initial_update.stderr
    first_source = next((tmp_path / "cache" / "git").glob(f"*/{first}/modules/dep/src/lib.cj"))

    @server.feature(types.CLIENT_REGISTER_CAPABILITY)
    def register(params: types.RegistrationParams):
        pass

    await server.initialize_session(
        types.InitializeParams(
            capabilities=capabilities(editor),
            workspace_folders=[types.WorkspaceFolder(uri=project.as_uri(), name="app")],
        )
    )
    await loaded(server)
    request = types.DefinitionParams(
        text_document=types.TextDocumentIdentifier(uri=file.as_uri()),
        position=types.Position(line=1, character=13),
    )
    try:
        # act
        before = await server.text_document_definition_async(request)

        # assert
        assert targets(before) == [(first_source, 1, 13)]

        # arrange: the same branch now points at a different commit; both checkouts remain
        source.write_text("package dep\n// a new revision\npublic class Remote {}\n")
        git(remote, "add", ".")
        git(remote, "-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "-m", "second")
        second = git(remote, "rev-parse", "HEAD")

        # act
        updated = update(project)
        server.workspace_did_change_watched_files(
            types.DidChangeWatchedFilesParams(changes=[
                types.FileEvent(uri=(project / "cjpm.lock").as_uri(), type=types.FileChangeType.Changed),
            ])
        )
        await loaded(server, 2)
        after = await server.text_document_definition_async(request)

        # assert
        assert updated.returncode == 0, updated.stdout + updated.stderr
        second_source = next((tmp_path / "cache" / "git").glob(f"*/{second}/modules/dep/src/lib.cj"))
        assert targets(after) == [(second_source, 2, 13)]
        assert first_source.is_file()
    finally:
        await server.shutdown_session()
