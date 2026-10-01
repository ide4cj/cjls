package cjls

import std.env.{getStdOut, getVariable, getWorkingDirectory}
import std.fs.Path
import stdx.log.Logger
import loupe.vfs.VfsPath
import project_model.*

const USAGE = """
Usage: cjls [command]

Commands:
  (none)           serve LSP over stdio, as an editor starts it
  project [dir]    print the project found for dir (the current one by default) as cj-project.json
  help             print this
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
    | Help
}

class UsageException <: Exception {
    UsageException(message: String) {
        super(message)
    }

    protected override func getClassName(): String {
        "UsageException"
    }
}

/**
 * The command `args` give, the program's name not among them: no arguments is `Serve`, as an
 * editor starts the server.
 *
 * @throws UsageException - for a command not known, or not given what it takes
 */
func parseCommand(args: Array<String>): Command {
    if (args.isEmpty()) {
        return Serve
    }
    match (args[0]) {
        case "project" where args.size == 1 => PrintProject(getWorkingDirectory())
        case "project" where args.size == 2 =>
            let dir = Path(args[1])
            if (dir.isAbsolute()) {
                PrintProject(dir)
            } else {
                PrintProject(getWorkingDirectory().join(dir))
            }
        case "project" => throw UsageException("`project` takes one directory at most")
        case "help" | "--help" | "-h" => Help
        case other => throw UsageException("no command `${other}`")
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
    let load = findProject(root, env: {name => getVariable(name)})
    logger.info("found a project", [("source", load.source.toString())])
    for (problem in load.problems) {
        logger.warn(problem)
    }
    getStdOut().write(prettyProjectJson(toProjectJson(load.model, root)))
    getStdOut().flush()
    0
}
