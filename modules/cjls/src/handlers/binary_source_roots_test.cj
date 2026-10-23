package cjls.handlers

import std.collection.ArrayList
import std.fs.remove
import std.unittest.*
import std.unittest.testmacro.*
import stdx.log.NoopLogger
import jsonrpc.{Body, Connection}
import cjls.lsp_ext.{BinarySourceRootsNotificationSpec, BinarySourceRootsParams}
import cjls.server.Client

/** Drains the synchronous load's wire, retaining only source-root replacements. */
func sourceReports(transport: AnsweringTransport): Array<BinarySourceRootsParams> {
    let reports = ArrayList<BinarySourceRootsParams>()
    while (let Some(body) <- transport.written.tryRemove()) {
        if (let Body.Notification(notification) <- body &&
            notification.method == BinarySourceRootsNotificationSpec.METHOD) {
            reports.add(notification.params.getOrThrow().read<BinarySourceRootsParams>())
        }
    }
    reports.toArray()
}

@Test
class BinarySourceRootsTest {
    @TestCase
    func onlyTheCurrentLoadReportsRootsAndANoWorkspaceLoadClearsThem() {
        let dir = workspaceOf([("cj-project.json", ##"{"modules":[],"binaries":[{"name":"lib","paths":[],"sources":"lib sources"},{"name":"other","paths":[],"sources":"lib sources"}]}"##),
            ("lib sources/lib.cj", "package lib")])
        let loop = initializedWith([dir], watches: false)
        let transport = AnsweringTransport(answers: false)
        let client = Client()
        client.connect(Connection(transport, NoHandler(), NoopLogger()))
        let older = loadRequest(loop.state).getOrThrow()
        let current = loadRequest(loop.state).getOrThrow()

        load(loop, client, NoopLogger(), older)
        @Expect(sourceReports(transport).isEmpty())
        load(loop, client, NoopLogger(), current)
        let reports = sourceReports(transport)
        @Expect(reports.size, 1)
        @Expect(reports[0].roots.filter {root => root == uriOf(dir.join("lib sources"))}.size, 1)
        let stale = loadRequest(loop.state).getOrThrow()
        loop.state.roots.clear()
        startLoad(loop, client, NoopLogger())
        @Expect(sourceReports(transport)[0].roots.isEmpty())
        @Expect(!loop.state.loading)
        load(loop, client, NoopLogger(), stale)
        @Expect(sourceReports(transport).isEmpty())
        remove(dir, recursive: true)
    }
}
