"""Call hierarchy items round trip through all three requests over stdio."""

import os
from pathlib import Path

import pytest
from lsprotocol import types
from pygls.uris import to_fs_path
from pytest_lsp import LanguageClient

from conftest import CLIENTS, REPO, capabilities, loaded

SDK = os.environ.get("CJLS_E2E_SDK") or os.environ.get("CANGJIE_HOME")
CANGJIE_SRC = REPO / ".corpora" / "cangjie_runtime" / "stdlib" / "libs"


@pytest.mark.parametrize("editor", CLIENTS)
async def test_call_hierarchy_round_trip(server: LanguageClient, tmp_path, editor):
    # arrange
    target = tmp_path / "a.cj"
    target.write_text("func target(): Unit {}\n")
    caller = tmp_path / "b.cj"
    caller.write_text("func caller(): Unit { target(); target() }\n")

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
    roots = await server.text_document_prepare_call_hierarchy_async(
        types.CallHierarchyPrepareParams(
            text_document=types.TextDocumentIdentifier(uri=target.as_uri()),
            position=types.Position(line=0, character=5),
        )
    )
    incoming = await server.call_hierarchy_incoming_calls_async(
        types.CallHierarchyIncomingCallsParams(item=roots[0])
    )
    outgoing = await server.call_hierarchy_outgoing_calls_async(
        types.CallHierarchyOutgoingCallsParams(item=incoming[0].from_)
    )

    # assert
    assert result.capabilities.call_hierarchy_provider
    assert len(roots) == len(incoming) == len(outgoing) == 1
    assert incoming[0].from_.name == "caller"
    assert Path(to_fs_path(incoming[0].from_.uri)) == caller
    assert outgoing[0].to.name == "target"
    assert Path(to_fs_path(outgoing[0].to.uri)) == target
    assert len(incoming[0].from_ranges) == 2
    assert outgoing[0].from_ranges == incoming[0].from_ranges

    await server.shutdown_session()


@pytest.mark.skipif(not SDK, reason="an SDK is needed for binary call hierarchy")
@pytest.mark.parametrize("attach_sources", [False, True])
async def test_binary_call_hierarchy_round_trip(server: LanguageClient, tmp_path, attach_sources):
    # arrange
    caller = tmp_path / "main.cj"
    caller.write_text('package app\nmain() { /* 😀 */ println("one"); println("two"); println(1) }\n',
                      encoding="utf-8")
    overloads = tmp_path / "overloads.cj"
    overloads.write_text("package app\nimport std.core.println\n")

    @server.feature(types.CLIENT_REGISTER_CAPABILITY)
    def register(params: types.RegistrationParams):
        pass

    sources = CANGJIE_SRC if attach_sources else tmp_path / "no-sources"
    if not attach_sources:
        # A valid empty source root prevents fallback to sources bundled with the SDK.
        (sources / "std").mkdir(parents=True)
    await server.initialize_session(types.InitializeParams(
        capabilities=capabilities("visual-studio-code"),
        workspace_folders=[types.WorkspaceFolder(uri=tmp_path.as_uri(), name="ws")],
        initialization_options={
            "cangjieHome": Path(SDK).resolve().as_uri(),
            "cangjieSrc": sources.resolve().as_uri(),
        },
    ))
    await loaded(server)
    server.text_document_did_open(types.DidOpenTextDocumentParams(
        text_document=types.TextDocumentItem(
            uri=caller.as_uri(), language_id="cangjie", version=1,
            text=caller.read_text(encoding="utf-8"),
        ),
    ))

    # act
    roots = await server.text_document_prepare_call_hierarchy_async(types.CallHierarchyPrepareParams(
        text_document=types.TextDocumentIdentifier(uri=caller.as_uri()),
        position=types.Position(line=1, character=20),
    ))
    assert roots and len(roots) == 1
    incoming = await server.call_hierarchy_incoming_calls_async(
        types.CallHierarchyIncomingCallsParams(item=roots[0]))
    main_calls = [call for call in incoming if call.from_.uri == caller.as_uri()]
    assert len(main_calls) == 1
    outgoing = await server.call_hierarchy_outgoing_calls_async(
        types.CallHierarchyOutgoingCallsParams(item=main_calls[0].from_))
    repeated = await server.call_hierarchy_incoming_calls_async(
        types.CallHierarchyIncomingCallsParams(item=outgoing[0].to))

    # assert
    assert roots[0].name == "println"
    assert main_calls[0].from_.name == "main"
    assert [r.start.character for r in main_calls[0].from_ranges] == [18, 34]
    assert [call.to.name for call in outgoing] == ["println", "println"]
    assert [len(call.from_ranges) for call in outgoing] == [2, 1]
    assert [call.from_ranges for call in repeated if call.from_.uri == caller.as_uri()] == [
        main_calls[0].from_ranges]
    if attach_sources:
        assert Path(to_fs_path(roots[0].uri)) == CANGJIE_SRC.resolve() / "std/core/print.cj"
        source = Path(to_fs_path(roots[0].uri)).read_text(encoding="utf-8")
        assert "println" in source.splitlines()[roots[0].selection_range.start.line]
    else:
        assert roots[0].uri == caller.as_uri()
        assert roots[0].selection_range.start == types.Position(line=1, character=18)
        leaf = await server.call_hierarchy_outgoing_calls_async(
            types.CallHierarchyOutgoingCallsParams(item=roots[0]))
        assert leaf is not None and len(leaf) == 0

        # act: an imported overload set shares one fallback location and name.
        candidates = await server.text_document_prepare_call_hierarchy_async(
            types.CallHierarchyPrepareParams(
                text_document=types.TextDocumentIdentifier(uri=overloads.as_uri()),
                position=types.Position(line=1, character=18),
            ))
        assert len(candidates) > 2
        counts = []
        for candidate in candidates:
            calls = await server.call_hierarchy_incoming_calls_async(
                types.CallHierarchyIncomingCallsParams(item=candidate))
            counts.extend(len(call.from_ranges) for call in calls if call.from_.uri == caller.as_uri())

        # assert
        assert sorted(counts) == [1, 2]

        # act: the saved location now calls another overload with the same name.
        server.text_document_did_change(types.DidChangeTextDocumentParams(
            text_document=types.VersionedTextDocumentIdentifier(uri=caller.as_uri(), version=2),
            content_changes=[types.TextDocumentContentChangeWholeDocument(
                text=caller.read_text(encoding="utf-8").replace('"one"', "true"),
            )],
        ))
        stale = await server.call_hierarchy_incoming_calls_async(
            types.CallHierarchyIncomingCallsParams(item=roots[0]))

        # assert
        assert stale is None

    await server.shutdown_session()
