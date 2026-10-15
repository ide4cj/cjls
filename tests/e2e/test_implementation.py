"""Go to implementation as an editor asks for it: the request over stdio, with a real client's capabilities, in a
workspace the server loaded. What implements what is `loupe`'s tests; locations the handler's (C7)."""

import pathlib

import pytest
from lsprotocol import types
from pygls.uris import to_fs_path
from pytest_lsp import LanguageClient

from conftest import CLIENTS, capabilities, loaded

DECLARING = """\
interface I {
    func g(): Int64
}
"""

IMPLEMENTING = """\
class C <: I {
    public func g(): Int64 { 1 }
}
extend Int64 <: I {
    public func g(): Int64 { this }
}
"""


@pytest.mark.parametrize("editor", CLIENTS)
async def test_the_implementations_of_an_interface_member_are_found_in_every_file(
    server: LanguageClient, tmp_path, editor
):
    # arrange
    (tmp_path / "a.cj").write_text(DECLARING)
    (tmp_path / "b.cj").write_text(IMPLEMENTING)

    @server.feature(types.CLIENT_REGISTER_CAPABILITY)
    def register(params: types.RegistrationParams):
        pass

    result = await server.initialize_session(
        types.InitializeParams(
            capabilities=capabilities(editor),
            workspace_folders=[types.WorkspaceFolder(uri=tmp_path.as_uri(), name="ws")],
        )
    )
    await loaded(server)

    # act
    answer = await server.text_document_implementation_async(
        types.ImplementationParams(
            text_document=types.TextDocumentIdentifier(uri=(tmp_path / "a.cj").as_uri()),
            position=types.Position(line=1, character=9),
        )
    )

    # assert: the class's member and the `extend`'s, as `Location`s
    assert result.capabilities.implementation_provider
    assert sorted(
        (pathlib.Path(to_fs_path(one.uri)).name, one.range.start.line, one.range.start.character)
        for one in answer or []
    ) == [("b.cj", 1, 16), ("b.cj", 4, 16)]

    await server.shutdown_session()
