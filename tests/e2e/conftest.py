"""End-to-end tests: the built `cjls` binary, driven over stdio as an editor drives it.

The binary is target/release/bin/cjls (`cjls.exe` on Windows); CJLS_BIN overrides it.
"""

import asyncio
import json
import os
import pathlib
import sys

import pytest_lsp
from lsprotocol import types
from lsprotocol.converters import get_converter
from packaging.version import Version
from pytest_lsp import ClientServerConfig, LanguageClient, client_capabilities

REPO = pathlib.Path(__file__).resolve().parents[2]
CJLS = os.environ.get("CJLS_BIN") or str(
    REPO / "target" / "release" / "bin" / ("cjls.exe" if sys.platform == "win32" else "cjls")
)
CONFIG = ClientServerConfig(server_command=[CJLS])

# the capabilities of real editors, as pytest-lsp captured them, or clients/ those it has not
CLIENTS = ["visual-studio-code", "neovim", "zed"]
OWN_CLIENTS = pathlib.Path(__file__).parent / "clients"


def capabilities(editor: str) -> types.ClientCapabilities:
    """An editor's capabilities: its latest `clients/<editor>_v<version>.json`, the `clientInfo` and
    `capabilities` of the `initialize` it sent, `experimental` left out (a language's own), else
    pytest-lsp's."""
    own = OWN_CLIENTS.glob(f"{editor.replace('-', '_')}_v*.json")
    latest = max(own, key=lambda path: Version(path.stem.split("_v")[-1]), default=None)
    if latest is None:
        return client_capabilities(editor)
    params = json.loads(latest.read_text())
    return get_converter().structure(params, types.InitializeParams).capabilities


async def loaded(client: LanguageClient, loads: int = 1):
    """Waits for the end of the server's `loads`th load of the workspace, as its `$/progress` tells: it
    loads on a thread of its own, and a request before the end answers from what is loaded so far (D61)."""
    # nothing is awaited between the look and the wait, so no notification falls between them
    while sum(isinstance(report, types.WorkDoneProgressEnd)
              for reports in client.progress_reports.values() for report in reports) < loads:
        await client.wait_for_notification(types.PROGRESS)


def answers_refreshes(client: LanguageClient):
    """Answers the server asking for semantic tokens again, as an editor of `refreshSupport` does
    (D70): it may ask after any change of the files."""

    @client.feature(types.WORKSPACE_SEMANTIC_TOKENS_REFRESH)
    def refresh(_params: None):
        return None


async def hang_up(client: LanguageClient):
    """Ends a server a failed test left running: pygls' `stop` would wait for it forever."""
    server = client._server
    if server is None or server.returncode is not None:
        return
    server.stdin.close()
    try:
        await asyncio.wait_for(server.wait(), timeout=5)
    except TimeoutError:
        server.kill()
        await server.wait()


@pytest_lsp.fixture(config=CONFIG, params=CLIENTS)
async def client(request, lsp_client: LanguageClient):
    """A session initialized with the capabilities of a real editor, shut down afterwards.

    `position_encoding` holds the encoding the two agreed on.
    """
    answers_refreshes(lsp_client)
    result = await lsp_client.initialize_session(
        types.InitializeParams(capabilities=capabilities(request.param))
    )
    lsp_client.position_encoding = result.capabilities.position_encoding
    yield
    try:
        await lsp_client.shutdown_session()
    finally:
        await hang_up(lsp_client)


@pytest_lsp.fixture(config=CONFIG)
async def server(lsp_client: LanguageClient):
    """A server just started: the test takes it through its lifecycle itself."""
    answers_refreshes(lsp_client)
    yield
    await hang_up(lsp_client)
