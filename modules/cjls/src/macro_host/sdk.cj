package cjls.macro_host

import std.collection.*
import std.env.getVariables
import std.process.{ProcessException, executeWithOutput}
import macro_server.{MacroServerPaths, TokenNumbers}
import platform.sdkToolEnvironment

/**
 * The SDK's `cjc`, run under the environment its `envsetup` sets (`sdkToolEnvironment`): its runtime on the
 * library path, what cjc loads a macro library a package uses with, and on macOS `SDKROOT`, which it links one
 * against.
 */
public class SdkToolchain <: Toolchain {
    private let paths: MacroServerPaths
    private let environment: HashMap<String, String>

    /**
     * The `cjc` of `paths`, run under `variables` and what `envsetup` would add to them.
     */
    public init(paths: MacroServerPaths, variables!: Array<(String, String)> = getVariables()) {
        this.paths = paths
        this.environment = sdkToolEnvironment(variables, paths.runtimeLib)
    }

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
        try {
            let (code, out, err) = executeWithOutput(paths.cjc.toString(), arguments, environment: environment)
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
