package cjls.macro_host

import std.collection.*
import std.env.getVariables
import std.process.{ProcessException, executeWithOutput}
import macro_server.{MacroServerPaths, TokenNumbers}

@When[os == "Windows"]
const LIBRARY_PATH = "PATH"

@When[os == "macOS"]
const LIBRARY_PATH = "DYLD_LIBRARY_PATH"

@When[os != "Windows" && os != "macOS"]
const LIBRARY_PATH = "LD_LIBRARY_PATH"

@When[os == "Windows"]
const PATH_SEPARATOR = ";"

@When[os != "Windows"]
const PATH_SEPARATOR = ":"

/**
 * The SDK's `cjc`, run with its runtime on the library path, as its `envsetup` sets it: what cjc loads a macro
 * library a package uses with.
 */
public class SdkToolchain <: Toolchain {
    public SdkToolchain(private let paths: MacroServerPaths) {}

    public func compile(arguments: Array<String>): (Int64, String) {
        let (code, out, err) = run(arguments)
        (code, err + out)
    }

    /**
     * What `cjc --version` prints, `None` if it does not run.
     */
    public func version(): ?String {
        let (code, out, _) = run(["--version"])
        if (code == 0) {
            out.trimAscii()
        } else {
            None
        }
    }

    private func run(arguments: Array<String>): (Int64, String, String) {
        let env = HashMap<String, String>(getVariables())
        let lib = paths.runtimeLib.toString()
        env[LIBRARY_PATH] = match (env.get(LIBRARY_PATH)) {
            case Some(old) where !old.isEmpty() => "${lib}${PATH_SEPARATOR}${old}"
            case _ => lib
        }
        try {
            let (code, out, err) = executeWithOutput(paths.cjc.toString(), arguments, environment: env)
            (code, String.fromUtf8(out), String.fromUtf8(err))
        } catch (e: ProcessException) {
            (-1, "", e.message)
        }
    }
}

/**
 * How the SDK whose `cjc --version` printed `version` numbers cjc's token kinds (D104): as its `Tokens.inc` lists
 * them, else as cjls's own table does for its version. `None` if neither can: no macro is expanded then.
 */
public func tokenNumbersOf(paths: MacroServerPaths, version: String): ?TokenNumbers {
    TokenNumbers.read(paths.tokensInc) ?? TokenNumbers.builtin(version)
}
