package macro_host

import std.collection.*
import std.env.getVariables
import std.fs.Path
import std.process.{ProcessException, executeWithOutput}
import macro_server.{MacroServerPaths, TokenNumbers}
import platform.sdkToolEnvironment
import project_model.{hostCfg, sdkTarget}

/**
 * What the host needs of the SDK: where its server is, how it numbers tokens, its `cjc` and its version.
 */
public class MacroSdk {
    public MacroSdk(
        public let paths: MacroServerPaths,
        public let numbers: TokenNumbers,
        public let toolchain: SdkToolchain,
        public let version: String
    ) {}

    // the library of each package of std asked for, `None` for one the SDK has none of
    private let stdLibraries = HashMap<String, ?String>()

    /**
     * The library of the macros of std's package `pkg` the SDK ships, if it does.
     */
    public func stdLibrary(pkg: String): ?String {
        if (let Some(found) <- stdLibraries.get(pkg)) {
            return found
        }
        let found = paths.stdMacroLibrary(pkg).map { path => path.toString() }
        stdLibraries[pkg] = found
        found
    }
}

/**
 * The SDK at a directory, as the macros need it: the one there, or why it cannot run them.
 */
public enum MacroSdkLookup {
    | Usable(MacroSdk)
    | Unusable(String)
}

/**
 * The SDK at `home` for the macros of this host: `Unusable` if it has no target for the host, its `cjc` does not
 * run, or it numbers its token kinds in a way cjls does not know.
 */
public func macroSdkIn(home: Path): MacroSdkLookup {
    let target = sdkTarget(hostCfg()) ?? return Unusable("no SDK target for this host")
    let paths = MacroServerPaths.inSdk(home, target)
    let toolchain = SdkToolchain(paths)
    let version =
        toolchain.version() ??
            return Unusable("the SDK's cjc does not run: macros are not expanded")
    let numbers =
        tokenNumbersOf(paths, version) ??
            return Unusable(
                "the SDK numbers its token kinds in a way cjls does not know: macros are not expanded"
            )
    Usable(MacroSdk(paths, numbers, toolchain, version))
}

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
            let (code, out, err) =
                executeWithOutput(paths.cjc.toString(), arguments, environment: environment)
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
