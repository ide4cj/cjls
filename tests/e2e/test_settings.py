"""Settings (#107, D79): their schema printed by `cjls --config-schema`, and a setting taken from the
client as each editor gives it."""

import json
import subprocess

import pytest
from lsprotocol import types
from pytest_lsp import LanguageClient

from conftest import CJLS, CLIENTS, capabilities, loaded


def test_config_schema_prints_every_setting_with_its_type_default_and_description():
    # act
    run = subprocess.run([CJLS, "--config-schema"], capture_output=True, timeout=60)

    # assert
    assert run.returncode == 0, run.stderr.decode()
    schema = json.loads(run.stdout)
    assert schema["type"] == "object"
    assert {"linkedProjects", "cangjieHome", "cangjieSrc"} <= set(schema["properties"])
    for setting in schema["properties"].values():
        assert {"type", "default", "description"} <= set(setting)


@pytest.mark.parametrize("editor", CLIENTS)
async def test_a_setting_changed_in_the_client_is_taken(server: LanguageClient, tmp_path, editor):
    # arrange: the project is linked by the client's configuration, not by `initializationOptions`
    root = tmp_path / "ws"
    root.mkdir()
    linked = tmp_path / "linked"
    linked.mkdir()
    (linked / "l.cj").write_text("func findLinked() {}\n")
    settings = {"linkedProjects": [str(linked)]}
    pulls = capabilities(editor).workspace.configuration
    server.set_configuration(settings, section="cjls")

    @server.feature(types.CLIENT_REGISTER_CAPABILITY)
    def register(params: types.RegistrationParams):
        pass

    await server.initialize_session(
        types.InitializeParams(
            capabilities=capabilities(editor),
            workspace_folders=[types.WorkspaceFolder(uri=root.as_uri(), name="ws")],
        )
    )

    # act: a client that can be asked is asked once initialized, and sends `null` here, as VS Code does
    server.workspace_did_change_configuration(
        types.DidChangeConfigurationParams(settings=None if pulls else {"cjls": settings})
    )
    await loaded(server, loads=2)
    symbols = await server.workspace_symbol_async(types.WorkspaceSymbolParams(query="findLinked"))

    # assert
    assert [s.name for s in symbols] == ["findLinked"]

    await server.shutdown_session()
