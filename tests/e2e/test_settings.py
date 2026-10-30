"""Settings (#107, D79): their schema printed by `cjls --config-schema`, and a setting taken from the
client as each editor gives it."""

import json
import os
from pathlib import Path
import subprocess

import pytest
from lsprotocol import types
from pytest_lsp import LanguageClient

from conftest import CJLS, CLIENTS, capabilities, loaded


def test_config_schema_prints_every_setting_with_its_type_default_and_description():
    # arrange
    command = [CJLS, "--config-schema"]

    # act
    run = subprocess.run(command, capture_output=True, timeout=60)

    # assert
    assert run.returncode == 0, run.stderr.decode()
    schema = json.loads(run.stdout)
    assert schema["type"] == "object"
    assert {"linkedProjects", "cangjieHome", "cangjieSrc", "cangjieStdxPath"} <= set(schema["properties"])
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


@pytest.mark.parametrize("declared", [True, False])
async def test_stdx_setting_resolves_only_declared_dependencies(server: LanguageClient, tmp_path, declared):
    sdk = os.environ.get("CJLS_E2E_SDK") or os.environ.get("CANGJIE_HOME")
    stdx = os.environ.get("CANGJIE_STDX_PATH")
    if not stdx:
        candidates = list(Path(sdk).glob("third_party/stdx/*/static/stdx")) if sdk else []
        if len(candidates) == 1:
            stdx = str(candidates[0])
    if not stdx or not (Path(stdx) / "stdx.log.cjo").is_file():
        pytest.skip("matching stdx binaries are required")
    (tmp_path / "src").mkdir()
    source = "package app\nimport stdx.log.NoopLogger\nfunc f(logger: NoopLogger) {}\n"
    file = tmp_path / "src" / "app.cj"
    file.write_text(source)
    model = {"modules": [{"name": "app", "root": "src", "deps": ["stdx"] if declared else []}]}
    if declared:
        model["binaries"] = [{"name": "stdx", "paths": ["${CANGJIE_STDX_PATH}"]}]
    (tmp_path / "cj-project.json").write_text(json.dumps(model))

    @server.feature(types.CLIENT_REGISTER_CAPABILITY)
    def register(_params):
        pass

    # CI deliberately leaves the SDK environment unset. Select both directories through
    # client settings so this also exercises an editor launched without that environment.
    empty = tmp_path / "empty"
    empty.mkdir()
    caps = capabilities("neovim")
    caps.workspace.configuration = False
    options = {"cangjieStdxPath": str(empty), "macroExpansion": False}
    if sdk:
        options["cangjieHome"] = sdk
    await server.initialize_session(types.InitializeParams(
        capabilities=caps,
        workspace_folders=[types.WorkspaceFolder(uri=tmp_path.as_uri(), name="ws")],
        initialization_options=options,
    ))
    await loaded(server)
    position = types.HoverParams(text_document=types.TextDocumentIdentifier(uri=file.as_uri()),
                                 position=types.Position(line=2, character=15))
    assert await server.text_document_hover_async(position) is None

    server.workspace_did_change_configuration(types.DidChangeConfigurationParams(
        settings={"cjls": {**options, "cangjieStdxPath": stdx}},
    ))
    await loaded(server, loads=2)
    hover = await server.text_document_hover_async(position)
    if declared:
        assert hover is not None
        assert "NoopLogger" in hover.contents.value
    else:
        assert hover is None
    await server.shutdown_session()
