package macro_host

import std.collection.HashMap
import std.fs.{FileInfo, Path}
import std.time.{DateTime, MonoTime}

/**
 * Three initial attempts, then at most one failed probe per minute. A successful attempt resets the budget.
 */
class RetryBudget {
    var count = 0
    private var retryAt: ?MonoTime = None

    func isPaused(now: MonoTime): Bool {
        retryAt.map {deadline => now < deadline} ?? false
    }

    func failed(now: MonoTime): Unit {
        count = min(count + 1, 3)
        if (count >= 3) {
            retryAt = now + Duration.minute
        }
    }

    func reset(): Unit {
        count = 0
        retryAt = None
    }
}

/**
 * A library that has answered is loadable; subsequent disconnects belong to individual methods.
 * Timeouts belong to methods: a slow call gives no evidence that its siblings would fail.
 */
class LibraryFailures {
    let loading = RetryBudget()
    var hasAnswered = false
    private let methods = HashMap<String, RetryBudget>()

    LibraryFailures(let stamp: String) {}

    func method(name: String): RetryBudget {
        if (let Some(found) <- methods.get(name)) {
            return found
        }
        let fresh = RetryBudget()
        methods[name] = fresh
        fresh
    }
}

/**
 * Replacement at the same SDK/library path releases its retry history. Workspace builds also call restart.
 * An unreadable or missing file has a stable identity, so stat failures do not release every next call.
 */
func libraryIdentity(path: String): String {
    try {
        let info = FileInfo(Path(path))
        "${info.size}:${(info.lastModificationTime - DateTime.UnixEpoch).toNanoseconds()}"
    } catch (_: Exception) {
        "unavailable"
    }
}
