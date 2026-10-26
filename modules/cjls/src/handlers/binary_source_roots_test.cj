package cjls.handlers

import std.collection.ArrayList
import std.fs.remove
import std.unittest.*
import std.unittest.testmacro.*
import stdx.log.NoopLogger
import cjls.lsp_ext.{BinarySourceRootsNotificationSpec, BinarySourceRootsParams}
import cjls.server.Client
import jsonrpc.{Body, Connection}

/**
 * Drains the synchronous load's wire, retaining only source-root replacements.
 */
private func sourceReports(transport: AnsweringTransport): Array<BinarySourceRootsParams> {
    let reports = ArrayList<BinarySourceRootsParams>()
    while (let Some(body) <- transport.written.tryRemove()) {
        if (let Body.Notification(notification) <- body &&
            notification.method == BinarySourceRootsNotificationSpec.METHOD) {
            let params = notification.params ?? throw IllegalStateException("a source-root report needs params")
            reports.add(params.read<BinarySourceRootsParams>())
        }
    }
    reports.toArray()
}

@Test
class BinarySourceRootsTest {
    @TestCase
    func onlyTheCurrentLoadReportsDeduplicatedBinarySourceRoots(): Unit {
        // arrange: two binaries share sources, while a source dependency contributes no root
        let manifest = ##"
{
    "modules": [{"name": "dep", "root": "dep", "member": false,
        "packages": [{"name": "dep", "dir": "dep", "files": ["lib.cj"]}]}],
    "binaries": [
        {"name": "lib", "paths": [], "sources": "lib sources"},
        {"name": "other", "paths": [], "sources": "lib sources"},
        {"name": "noSources", "paths": []}
    ]
}
"##
        let dir = workspaceOf([("cj-project.json", manifest),
            ("lib sources/lib.cj", "package lib"), ("dep/lib.cj", "package dep")])
        try {
            let loop = initializedWith([dir], watches: false)
            let transport = AnsweringTransport(answers: false)
            let client = Client()
            client.connect(Connection(transport, NoHandler(), NoopLogger()))
            let older = loadRequest(loop.state) ?? throw IllegalStateException("the workspace needs a load")
            let current = loadRequest(loop.state) ?? throw IllegalStateException("the workspace needs a load")

            // act: the older load completes after its replacement has started
            load(loop, client, NoopLogger(), older)
            let obsoleteReports = sourceReports(transport)

            // assert
            @Expect(obsoleteReports.isEmpty())

            // act
            load(loop, client, NoopLogger(), current)
            let reports = sourceReports(transport)

            // assert
            @Expect(reports.size, 1)
            @Expect(reports[0].roots.filter {root => root == uriOf(dir.join("lib sources"))}.size, 1)
            @Expect(!reports[0].roots.contains(uriOf(dir.join("dep"))))
        } finally {
            remove(dir, recursive: true)
        }
    }

    @TestCase
    func anEmptyWorkspaceClearsRootsAndInvalidatesOutstandingLoads(): Unit {
        // arrange: a worker is still loading when the last workspace folder is removed
        let dir = workspaceOf([("a.cj", "func f() {}")])
        try {
            let loop = initializedWith([dir], watches: false)
            let transport = AnsweringTransport(answers: false)
            let client = Client()
            client.connect(Connection(transport, NoHandler(), NoopLogger()))
            let stale = loadRequest(loop.state) ?? throw IllegalStateException("the workspace needs a load")
            loop.state.roots.clear()

            // act
            startLoad(loop, client, NoopLogger())
            let cleared = sourceReports(transport)

            // assert
            @Expect(cleared.size, 1)
            @Expect(cleared[0].roots.isEmpty())
            @Expect(!loop.state.loading)

            // act: the invalidated worker cannot restore the roots
            load(loop, client, NoopLogger(), stale)
            let staleReports = sourceReports(transport)

            // assert
            @Expect(staleReports.isEmpty())
        } finally {
            remove(dir, recursive: true)
        }
    }
}
