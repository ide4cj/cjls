package fbs_codegen

import std.env.{getStdErr, getStdOut}
import std.fs.Path
import std.io.OutputStream
import jian.*

/**
 * Supplies command output without retaining streams in the application.
 */
@JianContext
class CommandContext {
    CommandContext(let output: CommandOutput) {}
}

/**
 * Keeps both streams in one dependency because jian resolves context values by type.
 */
struct CommandOutput {
    CommandOutput(let out: OutputStream, let err: OutputStream) {}
}

let FBS_CODEGEN_APP = JianContextApp<CommandContext>(name: "fbs_codegen")

/**
 * Generates views from the config named on the command line.
 */
main(args: Array<String>): Int64 {
    runFbsCodegen(args)
}

/**
 * Runs argv without the executable name; returns 2 for usage errors, 1 for generation failures.
 */
func runFbsCodegen(
    args: Array<String>,
    out!: OutputStream = getStdOut(),
    err!: OutputStream = getStdErr()
): Int64 {
    try {
        FBS_CODEGEN_APP.run(
            args,
            context: CommandContext(CommandOutput(out, err)),
            stdout: out,
            stderr: err
        )
    } catch (e: Exception) {
        err.write("error: ${e.message}\n".toArray())
        err.flush()
        1
    }
}

/**
 * Generates and formats the configured output, reporting its path to stdout.
 */
@JianCommand[FBS_CODEGEN_APP, root: true, help: "Generate Cangjie views of the FlatBuffers schema named by a config."]
func generateCommand(
    config!: Path = JianArgument(
        help: "Generation config in TOML format.",
        preprocess: nonemptyConfig
    ),
    context!: CommandContext = JianFromContext<CommandContext>()
): Int64 {
    let file = generate(config)
    writeFormatted(file.path, file.contents)
    context.output.out.write("info: wrote ${file.path}\n".toArray())
    context.output.out.flush()
    0
}

/**
 * Rejects blank config paths before filesystem access, preserving nonblank input verbatim.
 */
func nonemptyConfig(raw: String): String {
    if (raw.trimAscii().isEmpty()) {
        throw JianInputException("expected a config path")
    }
    raw
}
