package lsp_codegen

import std.env.{getStdErr, getStdOut}
import std.fs.{Directory, File, Path, exists}
import std.io.OutputStream
import fjson.fromJsonBytes
import jian.*

/**
 * Supplies the command's output stream without making it a CLI input.
 */
@JianContext
class CommandContext {
    CommandContext(let output: CommandOutput) {}
}

/**
 * Wraps the output interface because Jian context dependencies must be concrete types.
 */
struct CommandOutput {
    CommandOutput(let out: OutputStream) {}
}

main(args: Array<String>): Int64 {
    runCommand(args)
}

/**
 * Runs the CLI, returning 2 for usage errors and 1 for generation failures.
 */
func runCommand(
    args: Array<String>,
    out!: OutputStream = getStdOut(),
    err!: OutputStream = getStdErr()
): Int64 {
    let app = JianContextApp<CommandContext>(
        name: "lsp_codegen",
        help: "Generate Cangjie protocol types from an LSP meta model.",
        stdout: out,
        stderr: err
    )
        // The unexpanded census cannot see @JianCommand's factory overload (#176).
        .command(generateProtocol)
    try {
        // `app` inherits the unavailable macro-generated factory type in the census (#176).
        app.run(args, context: CommandContext(CommandOutput(out)))
    } catch (e: Exception) {
        err.write("error: ${e.message}\n".toArray())
        err.flush()
        1
    }
}

/**
 * Generates the configured protocol files; read, configuration and emission failures propagate.
 */
@JianCommand[help: "Generate the protocol files selected by the configuration."]
func generateProtocol(
    metaModel!: Path = JianArgument(help: "LSP metaModel.json file.", preprocess: nonblankPath),
    config!: Path = JianOption(
        short: r'c',
        help: "Generator configuration TOML file.",
        preprocess: nonblankPath
    ),
    context!: CommandContext = JianFromContext<CommandContext>()
): Int64 {
    let cfg = Config.load(config)
    let model = fromJsonBytes<MetaModel>(File.readFrom(metaModel))

    let cjFiles = generateCjFiles(cfg, model)
    if (!exists(cfg.outputDir)) {
        Directory.create(cfg.outputDir, recursive: true)
    }
    for (file in cjFiles) {
        File.writeTo(file.path, file.contents.toArray())
    }
    context.output.out.write("info: generated ${cjFiles.size} Cangjie files\n".toArray())
    context.output.out.flush()
    0
}

/**
 * Trims surrounding ASCII whitespace and rejects blank CLI paths as usage errors.
 */
func nonblankPath(raw: String): String {
    // Preserve the CLI's whitespace handling and reject empty paths before filesystem access.
    let path = raw.trimAscii()
    if (path.isEmpty()) {
        throw JianInputException("path must not be blank")
    }
    path
}
