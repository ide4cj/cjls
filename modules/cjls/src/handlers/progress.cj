package cjls.handlers

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
 * The creation is waited for: never from a handler on the read loop, whose loop the answer comes
 * through.
 */
class WorkDoneProgress {
    private WorkDoneProgress(private let client: Client, private let logger: Logger, private let token: ?ProgressToken) {}

    /**
     * Creates the token `token`, `None` for a client that shows no progress, and begins the work
     * called `title` under it.
     */
    static func begin(client: Client, logger: Logger, token: ?String, title: String): WorkDoneProgress {
        let created = token.flatMap {token => created(client, logger, IntegerOrString.String(token))}
        let progress = WorkDoneProgress(client, logger, created)
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
        try {
            client.notify(ProgressNotificationSpec(), ProgressParams(token: token, value: RawJson.of(value).read<JsonValue>()))
        } catch (e: Exception) {
            logger.debug("the progress was not sent", [("error", e.toString())])
        }
    }
}

/**
 * `token`, once the client created it; `None` if it refused, or could not be asked.
 */
func created(client: Client, logger: Logger, token: ProgressToken): ?ProgressToken {
    try {
        client.request<WorkDoneProgressCreateParams, RawJson>(WorkDoneProgressCreateRequestSpec.METHOD,
            WorkDoneProgressCreateParams(token: token)).await()
        token
    } catch (e: Exception) {
        logger.debug("no progress is shown", [("error", e.toString())])
        None
    }
}
