package cjls.server

import std.collection.*
import std.sync.Mutex
import stdx.log.Logger
import jsonrpc.ErrorLogValue
import loupe.vfs.VfsPath

/**
 * The read loop, as work a handler leaves to a thread of its own sees it (D61): `write` changes
 * the state between two messages, as a `Context` handler does, and is followed by the work a write
 * calls for (S7). The server runs every `Context` handler through it and takes every snapshot under
 * it, so a write from a thread of its own is one more message, in no message's middle.
 */
public class Loop <: FromContext<Loop> {
    private let lock = Mutex()
    private let tasksLock = Mutex()
    // guarded by `tasksLock`: the threads `start` started that may not have ended yet
    private let tasks = ArrayList<Future<Unit>>()

    /**
     * A loop over `state` that runs nothing after a write: a test's, which looks at the state itself.
     */
    public init(state: ServerState) {
        this(state, Option<DiagnosticsPush>.None)
    }

    Loop(public let state: ServerState, private let push: ?DiagnosticsPush) {}

    /**
     * A handler on the loop holds the state already: it calls `start`, never `write`.
     */
    public static func from<P>(ctx: Context<P>): Loop {
        ctx.loop
    }

    /**
     * Runs `change` on the state once no message is being handled, and nothing else meanwhile;
     * then, even if it threw, the work its changes call for: a client that cannot pull is pushed nothing for the
     * documents just closed, at once, and the diagnostics of every open document, from a snapshot
     * taken here, once the files changed or a document opened.
     *
     * @note never from a handler on the loop, nor while holding what such a handler waits for
     */
    public func write<T>(change: (ServerState) -> T): T {
        synchronized(lock) {
            let openBefore = HashSet<VfsPath>(state.openDocuments.keys())
            try {
                change(state)
            } finally {
                afterWrite(openBefore)
            }
        }
    }

    /**
     * The state as it is between two messages, for a handler running on a thread of its own.
     */
    func snapshot(cancelledBy!: () -> Bool = {=> false}): ServerSnapshot {
        synchronized(lock) {
            state.snapshot(cancelledBy: cancelledBy)
        }
    }

    /**
     * Runs `task` on a thread of its own, which changes the state through `write` alone; a failure
     * is an `ERROR` of `logger`, an `Error` as well (S13).
     */
    public func start(logger: Logger, task: () -> Unit): Unit {
        let future = spawn {
            try {
                task()
            } catch (e: Exception) {
                logger.error("failed", [("cause", e)])
            } catch (e: Error) {
                logger.error("failed", [("cause", ErrorLogValue(e))])
            }
        }
        synchronized(tasksLock) {
            tasks.removeIf {task => task.tryGet().isSome()}
            tasks.add(future)
        }
    }

    /**
     * Waits until every thread `start` started has ended, those they started included.
     *
     * @note never from a handler on the loop, nor inside `write`: the threads may be waiting for it
     */
    public func join(): Unit {
        while (true) {
            let running = synchronized(tasksLock) {
                let running = tasks.toArray()
                tasks.clear()
                running
            }
            if (running.isEmpty()) {
                return
            }
            for (task in running) {
                task.get()
            }
        }
    }

    private func afterWrite(openBefore: HashSet<VfsPath>): Unit {
        let filesChanged = state.takeFilesChanged()
        let push = push ?? return ()
        if (!state.pushesDiagnostics) {
            return
        }
        for (path in openBefore where !state.openDocuments.contains(path)) {
            push.clear(path)
        }
        let opened = state.openDocuments.keys().iterator().any {path => !openBefore.contains(path)}
        if (filesChanged || opened) {
            let documents = collectArray(state.openDocuments)
            push.schedule(state.snapshot(), documents)
        }
    }
}
