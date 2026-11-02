package cjls

import std.env.{getStdErr, getStdOut, getVariable, getWorkingDirectory}
import std.fs.Path
import std.io.OutputStream
import stdx.log.Logger
import fjson.JsonValue
import jian.*
import loupe.vfs.VfsPath
import project_model.*
import cjls.server.settingsSchema

@JianContext
class CommandContext {
    CommandContext(let logger: Logger) {}
}

func commandApp(
    out!: OutputStream = getStdOut(),
    err!: OutputStream = getStdErr()
): JianContextApp<CommandContext> {
    JianContextApp<CommandContext>(
        name: "cjls",
        help: "Cangjie language server.",
        stdout: out,
        stderr: err
    )
        .callback(configureCommand)
        .add(printProject)
        .add(formatCommand)
        .add(downloadSources)
}

@JianCallback[help: "Serve LSP over stdio when no command is given."]
func configureCommand(
    invocation!: JianInvocation = JianCurrentInvocation(),
    logger!: Logger = JianFromContext<CommandContext>(),
    configSchema!: Bool = JianOption(
        help: "Print the JSON Schema of the server's settings and exit.",
        default: false
    )
): JianCallbackResult {
    if (configSchema) {
        // Schema generation is a standalone invocation, as editor clients expect.
        if (invocation.requestedSubcommand.isSome()) {
            throw JianUsageException("--config-schema takes no command")
        }
        return JianCallbackResult.Exit(printConfigSchema(getStdOut()))
    }
    if (invocation.requestedSubcommand.isNone()) {
        return JianCallbackResult.Exit(runServer(logger))
    }
    JianCallbackResult.Continue
}

@JianCommand[name: "fmt", help: "Format Cangjie files or directories using their project settings."]
func formatCommand(
    paths: Array<Path>,
    check!: Bool = JianOption(
        short: r'c',
        help: "Report files that would change without writing them.",
        default: false
    )
): Int64 {
    formatPaths(paths.map { path => absolute(path) }, check, getStdOut(), getStdErr())
}

@JianCommand[name: "fetch-src", help: "Download std sources for the detected SDK into its src directory."]
func downloadSources(
    dir!: ?Path = JianOption(
        short: r'd',
        help: "Destination directory instead of the SDK's src.",
        preprocess: nonemptyDirectory,
        normalize: absoluteDirectory
    )
): Int64 {
    fetchSrcCommand(dir, getStdOut(), getStdErr())
}

/**
 * Prints the project found for `dir` to stdout as `cj-project.json`, with every default written
 * out, paths relative to `dir`; what was wrong on the way goes to the log.
 *
 * @return the exit code
 */
@JianCommand[name: "project", help: "Print the detected project as cj-project.json."]
func printProject(
    dir!: Path = JianOption(
        short: r'd',
        help: "Project directory, the working directory by default.",
        default: getWorkingDirectory(),
        preprocess: nonemptyDirectory,
        normalize: absolute
    ),
    logger!: Logger = JianFromContext<CommandContext>()
): Int64 {
    let root = VfsPath.file(dir)
    let env = { name: String => getVariable(name) }
    let withHome = withCangjieHome(env, findCangjieHome(None, env: env))
    let load = findProject(root, env: withCangjieSrc(withHome, findCangjieSrc(None, env: withHome)))
    logger.info("found a project", [("source", load.source.toString())])
    for (problem in load.problems) {
        logger.warn(problem)
    }
    getStdOut().write(prettyProjectJson(toProjectJson(load.model, root)))
    getStdOut().flush()
    0
}

/**
 * Prints the JSON Schema of the settings to `out`, as the editors' clients generate theirs from
 * (D32, D79).
 *
 * @return the exit code
 */
func printConfigSchema(out: OutputStream): Int64 {
    out.write((settingsSchema().toPrettyString() + "\n").toArray())
    out.flush()
    0
}

/**
 * Fetches the sources of `std` of the SDK found as the server finds it (D40) into `dir`, `src` in the
 * SDK without one, where the server looks for them (D65, D69).
 *
 * @return the exit code
 */
func fetchSrcCommand(dir: ?Path, out: OutputStream, err: OutputStream): Int64 {
    let env = { name: String => getVariable(name) }
    let home =
        match (findCangjieHome(None, env: env)) {
            case Some(home) => Path(home.path)
            case None =>
                err.write("no SDK found: set CANGJIE_HOME\n".toArray())
                err.flush()
                return 1
        }
    fetchSrc(home, dir ?? home.join("src"), SystemSrcHost(), out, err)
}

func nonemptyDirectory(raw: String): String {
    // Path("") cannot be joined; report invalid CLI input before project or SDK discovery.
    if (raw.isEmpty()) {
        throw JianInputException("expected a directory")
    }
    raw
}

func absoluteDirectory(dir: ?Path): ?Path {
    dir.map { path => absolute(path) }
}

func absolute(path: Path): Path {
    if (path.isAbsolute()) { path } else { getWorkingDirectory().join(path) }
}
