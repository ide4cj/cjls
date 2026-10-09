package cjls.handlers

import std.sync.AtomicBool
import stdx.log.Logger
import stdxx.IntegerOrString
import fjson.{JsonValue, RawJson, ToJson}
import cjls.lsp_types.*
import cjls.server.Client

/**
 * Work the client is shown the progress of: `$/progress` under a token the server creates
 * (`window/workDoneProgress/create`), begun, reported and ended. Nothing is sent to a client that
 * does not take it, nor once it answered the token's creation with an error, as LSP asks.
 *
 * The creation is not waited for, as rust-analyzer does not: the work begins under the token at
 * once, the client reading the creation first, so a client slow to answer, or never answering,
 * holds up nothing.
 */
class WorkDoneProgress {
    private WorkDoneProgress(
        private let client: Client,
        private let logger: Logger,
        private let token: ?ProgressToken,
        private let refused: AtomicBool,
        /** the thread waiting for the answer to the token's creation, which ends with it */
        let creation: ?Future<Unit>
    ) {}

    /**
     * Creates the token `token`, `None` for a client that shows no progress, and begins the work
     * called `title` under it.
     */
    static func begin(client: Client, logger: Logger, token: ?String, title: String): WorkDoneProgress {
        let refused = AtomicBool(false)
        let asked = token.map {name => IntegerOrString.String(name)}
        let creation = asked.flatMap {it => create(client, logger, it, refused)}
        let created = if (creation.isSome()) {
            asked
        } else {
            Option<ProgressToken>.None
        }
        let progress = WorkDoneProgress(client, logger, created, refused, creation)
        progress.send(WorkDoneProgressBegin(title: title, percentage: 0))
        progress
    }

    /**
     * `done` of `total` steps done, `message` saying what they are.
     */
    func report(done: Int64, total: Int64, message: String): Unit {
        let percentage = if (total <= 0) {
            100u32
        } else {
            UInt32(done * 100 / total)
        }
        send(WorkDoneProgressReport(message: message, percentage: percentage))
    }

    func end(message: ?String): Unit {
        send(WorkDoneProgressEnd(message: message))
    }

    private func send<T>(value: T): Unit where T <: ToJson {
        let token = token ?? return ()
        if (refused.load()) {
            return
        }
        try {
            client.notify(ProgressNotificationSpec(), ProgressParams(token: token, value: RawJson.of(value).read<JsonValue>()))
        } catch (e: Exception) {
            logger.debug("the progress was not sent", [("error", e.toString())])
        }
    }
}

/**
 * Asks the client to create `token`, and waits for its answer on a thread of its own, which sets
 * `refused` if it is an error; `None` if the client could not be asked.
 */
func create(client: Client, logger: Logger, token: ProgressToken, refused: AtomicBool): ?Future<Unit> {
    let pending = try {
        client.request(WorkDoneProgressCreateRequestSpec(), WorkDoneProgressCreateParams(token: token))
    } catch (e: Exception) {
        logger.debug("no progress is shown", [("error", e.toString())])
        return None
    }
    spawn {
        try {
            pending.await()
        } catch (e: Exception) {
            refused.store(true)
            logger.debug("no more progress is shown", [("error", e.toString())])
        } catch (e: Error) {
            refused.store(true)
            logger.error("no more progress is shown", [("error", e.toString())])
        }
    }
}
