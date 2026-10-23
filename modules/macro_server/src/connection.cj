package macro_server

import std.io.*
import fbs.FbException

/**
 * The server failed a call: it exited, or answered with what is not an answer. The calls after it need a new
 * server.
 */
public class MacroServerException <: Exception {
    public init(message: String) {
        super(message)
    }

    protected override func getClassName(): String {
        "MacroServerException"
    }
}

/**
 * `MacroResult.status` of a call that failed: `MacroEvalStatus.FAIL` of cjc's `include/cangjie/Macro/MacroCall.h`.
 * Any other status is an expansion: `SUCCESS` is what cjc's own client sets once it has one.
 */
public const MACRO_FAILED: UInt8 = 4

/**
 * Talks to `LSPMacroServer` over `input` (what it writes) and `output` (what it reads), as D87 says: one call a
 * message, each followed by `exitTask(false)`, so that no diagnostic of a call reaches the next. Its calls are
 * made one at a time: the server answers in order.
 */
public class MacroConnection {
    public MacroConnection(let input: InputStream, let output: OutputStream) {}

    /**
     * Expands `call`: what the server answers. A macro that throws is an answer, `MACRO_FAILED` with an
     * `ILLEGAL` token; the server lives on.
     *
     * @throws MacroServerException - if the server exits (a symbol not found, a library it cannot open) or
     *     answers with what is not a `MacroResult`
     * @throws IOException - if writing to it fails
     */
    public func expand(call: MacroCallData): MacroResult {
        writeMessage(
            output,
            MacroMsgData(content: MsgContentData.AsMultiCalls(MultiMacroCallsData(calls: [call])))
                .toBytes()
        )
        let answer = readMessage(input) ?? throw MacroServerException("the server exited")
        let result =
            try {
                match (MacroMsg.root(answer).content) {
                    case Some(MsgContent.AsMacroResult(r)) => r
                    case _ => throw MacroServerException("the server answered with no MacroResult")
                }
            } catch (e: FbException | IndexOutOfBoundsException) {
                throw MacroServerException("the server's answer is broken: ${e.message}")
            }
        writeMessage(output, exitTask(false))
        result
    }

    /**
     * Asks the server to exit.
     */
    public func close(): Unit {
        writeMessage(output, exitTask(true))
    }
}

/**
 * `exitTask(flag)`: `false` ends a call, its diagnostics forgotten; `true` ends the server.
 */
func exitTask(flag: Bool): Array<Byte> {
    MacroMsgData(content: MsgContentData.AsExitTask(ExitTaskData(flag: flag))).toBytes()
}
