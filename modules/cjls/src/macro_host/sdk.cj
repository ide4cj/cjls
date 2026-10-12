package cjls.macro_host

import std.collection.*
import std.env.getVariables
import std.fs.*
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

@When[os == "Windows"]
const EXE = ".exe"

@When[os != "Windows"]
const EXE = ""

/**
 * The SDK's `cjc`, run with its runtime on the library path, as its `envsetup` sets it: what cjc loads a macro
 * library a package uses with, and what a program it built needs.
 */
public class SdkToolchain <: Toolchain {
    public SdkToolchain(private let paths: MacroServerPaths) {}

    public func compile(arguments: Array<String>): (Int64, String) {
        let (code, out, err) = run(paths.cjc.toString(), arguments)
        (code, err + out)
    }

    public func execute(program: Path): ?String {
        let (code, out, _) = run(program.toString(), [])
        if (code == 0) {
            out
        } else {
            None
        }
    }

    /**
     * What `cjc --version` prints, `None` if it does not run.
     */
    public func version(): ?String {
        let (code, out, _) = run(paths.cjc.toString(), ["--version"])
        if (code == 0) {
            out.trimAscii()
        } else {
            None
        }
    }

    private func run(command: String, arguments: Array<String>): (Int64, String, String) {
        let env = HashMap<String, String>(getVariables())
        let lib = paths.runtimeLib.toString()
        env[LIBRARY_PATH] = match (env.get(LIBRARY_PATH)) {
            case Some(old) where !old.isEmpty() => "${lib}${PATH_SEPARATOR}${old}"
            case _ => lib
        }
        try {
            let (code, out, err) = executeWithOutput(command, arguments, environment: env)
            (code, String.fromUtf8(out), String.fromUtf8(err))
        } catch (e: ProcessException) {
            (-1, "", e.message)
        }
    }
}

/**
 * A program printing the name of each token kind by its number, as `std.ast` has them.
 */
const TOKEN_KINDS_PROGRAM = ##"
import std.ast.getTokenKind
import std.collection.HashSet

main(): Int64 {
    let seen = HashSet<String>()
    for (n in 0..256) {
        let name = try {
            getTokenKind(UInt16(n)).toString()
        } catch (_: Exception) {
            break
        }
        // past the last kind it names one again
        if (!seen.add(name)) {
            break
        }
        println(name)
    }
    0
}
"##

/**
 * How the SDK numbers cjc's token kinds (D103): as its `Tokens.inc` lists them, else as `std.ast` names them,
 * printed by a program `toolchain` builds once into `out`, which keeps them. `None` if neither works: no macro is
 * expanded then.
 */
public func tokenNumbersOf(paths: MacroServerPaths, out: Path, toolchain: Toolchain): ?TokenNumbers {
    if (let Some(numbers) <- TokenNumbers.read(paths.tokensInc)) {
        return numbers
    }
    let kept = out.join("token-kinds.txt")
    if (let Some(numbers) <- namesIn(kept).flatMap {names => TokenNumbers.ofNames(names)}) {
        return numbers
    }
    let dir = out.join("token-kinds")
    let source = dir.join("main.cj")
    let program = dir.join("token-kinds${EXE}")
    try {
        Directory.create(dir, recursive: true)
        File.writeTo(source, TOKEN_KINDS_PROGRAM.toArray())
    } catch (_: Exception) {
        return None
    }
    let (code, _) = toolchain.compile([source.toString(), "-o", program.toString()])
    if (code != 0) {
        return None
    }
    let printed = toolchain.execute(program) ?? return None
    let numbers = TokenNumbers.ofNames(namesOf(printed)) ?? return None
    try {
        File.writeTo(kept, printed.toArray())
    } catch (_: Exception) {
        ()
    }
    numbers
}

func namesIn(file: Path): ?Array<String> {
    try {
        namesOf(String.fromUtf8(File.readFrom(file)))
    } catch (_: Exception) {
        None
    }
}

/**
 * The names `text` holds, one a line.
 */
func namesOf(text: String): Array<String> {
    text.lines() |> map {line: String => line.trimAscii()} |> filter {line: String => !line.isEmpty()} |>
        collectArray
}
