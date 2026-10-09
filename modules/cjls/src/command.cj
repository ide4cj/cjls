package cjls

import std.argopt.*
import std.env.{getStdOut, getVariable, getWorkingDirectory}
import std.fs.Path
import std.io.OutputStream
import stdx.log.Logger
import loupe.vfs.VfsPath
import project_model.*

const USAGE = """
Usage: cjls [command]

Commands:
  (none)                 serve LSP over stdio, as an editor starts it
  project [--dir <dir>]  print the project found for <dir>, the current directory by default,
                         as cj-project.json
  fmt [--check] <path>...
                         format the Cangjie files at <path>, a directory's as the server reads
                         them; with --check, change nothing and fail if a file would change
  fetch-src [--dir <dir>]
                         download the sources of std of the SDK found, at the commit its nightly's
                         release notes name, into <dir>, the SDK's src by default
  help                   print this
"""

/**
 * What the server was started to do.
 */
enum Command {
    | Serve
    /**
     * Print the project of this directory, as `cj-project.json`.
     */
    | PrintProject(Path)
    /**
     * Format the files at these paths, or with `check` only say which would change.
     */
    | Format(Array<Path>, Bool)
    /**
     * Fetch the sources of `std` of the SDK into this directory, the SDK's `src` without one.
     */
    | FetchSrc(?Path)
    | Help
}

/**
 * The command `args` give, the program's name not among them: no arguments is `Serve`, as an
 * editor starts the server.
 *
 * @throws ArgumentParseException - for a command not known, or not given what it takes
 */
func parseCommand(args: Array<String>): Command {
    if (args.isEmpty()) {
        return Serve
    }
    match (args[0]) {
        case "project" => PrintProject(projectDir(args[1..]))
        case "fmt" => formatCommand(args[1..])
        case "fetch-src" => FetchSrc(fetchSrcDir(args[1..]))
        case "help" | "--help" | "-h" => Help
        case other => throw ArgumentParseException("no command `${other}`")
    }
}

/**
 * Prints the project found for `dir` to stdout as `cj-project.json`, with every default written
 * out, paths relative to `dir`; what was wrong on the way goes to the log.
 *
 * @return the exit code
 */
func printProject(dir: Path, logger: Logger): Int64 {
    let root = VfsPath.file(dir)
    let env = {name: String => getVariable(name)}
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
 * Fetches the sources of `std` of the SDK found as the server finds it (D40) into `dir`, `src` in the
 * SDK without one, where the server looks for them (D65, D67).
 *
 * @return the exit code
 */
func fetchSrcCommand(dir: ?Path, out: OutputStream, err: OutputStream): Int64 {
    let env = {name: String => getVariable(name)}
    let home = match (findCangjieHome(None, env: env)) {
        case Some(home) => Path(home.path)
        case None =>
            err.write("no SDK found: set CANGJIE_HOME\n".toArray())
            err.flush()
            return 1
    }
    fetchSrc(home, dir ?? home.join("src"), SystemSrcHost(), out, err)
}

/**
 * The directory `fetch-src`'s options name, `--dir <dir>` (`-d <dir>`) or `--dir=<dir>`, relative to
 * the working one; `None` without them.
 *
 * @throws ArgumentParseException - for an option not known, an argument, or `--dir` without a value
 */
func fetchSrcDir(options: Array<String>): ?Path {
    let parsed = parseArguments(options, [Full("dir", r'd', RequiredValue)])
    if (let Some(argument) <- parsed.nonOptions.first) {
        throw ArgumentParseException("`fetch-src` takes no `${argument}`")
    }
    let dir = parsed.options.get("dir") ?? return None
    if (dir.isEmpty()) {
        throw ArgumentParseException("`--dir` takes a directory")
    }
    absolute(Path(dir))
}

/**
 * The directory `project`'s options name, `--dir <dir>` (`-d <dir>`) or `--dir=<dir>`, relative to
 * the working one; the working one without them.
 *
 * the working one; the working one without them. Given twice, the last counts.
 *
 * @throws ArgumentParseException - for an option not known, an argument, or `--dir` without a value
 */
func projectDir(options: Array<String>): Path {
    let parsed = parseArguments(options, [Full("dir", r'd', RequiredValue)])
    if (let Some(argument) <- parsed.nonOptions.first) {
        throw ArgumentParseException("`project` takes no `${argument}`")
    }
    let dir = parsed.options.get("dir") ?? return getWorkingDirectory()
    // `--dir=` is a value to argopt, and `Path("")` throws on every join
    if (dir.isEmpty()) {
        throw ArgumentParseException("`--dir` takes a directory")
    }
    absolute(Path(dir))
}

/**
 * What `fmt`'s arguments say: `--check` (`-c`) and at least one path, relative to the working
 * directory.
 *
 * @throws ArgumentParseException - for an option not known, or no path
 */
func formatCommand(arguments: Array<String>): Command {
    let parsed = parseArguments(arguments, [Full("check", r'c', NoValue)])
    if (parsed.nonOptions.isEmpty()) {
        throw ArgumentParseException("`fmt` takes the paths to format")
    }
    let paths = parsed.nonOptions.map {argument => absolute(Path(argument))}
    Format(paths, parsed.options.contains("check"))
}

func absolute(path: Path): Path {
    if (path.isAbsolute()) {
        path
    } else {
        getWorkingDirectory().join(path)
    }
}
