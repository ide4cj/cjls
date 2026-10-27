package macro_server

import std.env.{getTempDirectory, getVariable}
import std.fs.{Directory, exists, File, Path, remove}
import std.unittest.*
import std.unittest.testmacro.*
import platform.{hostArch, sharedLibrarySuffix}

/**
 * The tokens of `code` as a call sends them, of file 1, `code` starting at line 1, column `column`.
 */
func tokensOf(code: String, column: Int64): Array<TokenData> {
    macroTokens(code, sdkNumbers(), PositionData(fileId: 1, line: 1, column: Int32(column)))
}

/**
 * The SDK the tests run on, and the directory of its runtime for this host: the one that has std.ast.
 */
func sdkPaths(): MacroServerPaths {
    let home =
        Path(
            getVariable("CANGJIE_HOME") ?? throw IllegalStateException("CANGJIE_HOME names no SDK")
        )
    sdkPaths(
        home,
        Directory
            .readFrom(home.join("runtime").join("lib"))
            .filter { dir => dir.isDirectory() }
            .map { dir => dir.path }
    )
}

/** Selects a runtime with the host architecture and shared-library suffix. */
func sdkPaths(home: Path, runtimes: Array<Path>): MacroServerPaths {
    let targetSuffix = "_${hostArch()}_cjnative"
    let library = "libcangjie-std-ast${sharedLibrarySuffix()}"
    for (dir in runtimes) {
        let name = dir.fileName
        if (name.endsWith(targetSuffix) && exists(dir.join(library))) {
            return MacroServerPaths.inSdk(home, name)
        }
    }
    throw IllegalStateException(
        "no runtime for ${hostArch()} (${sharedLibrarySuffix()}) under ${home}"
    )
}

@Test
class SdkPathsTest {
    @TestCase
    func foreignRuntimesAreIgnoredInEitherOrder(): Unit {
        let home = Directory.createTemp(getTempDirectory())
        try {
            let runtimes =
                ["linux", "darwin", "windows"]
                    .flatMap {
                        os =>
                        ["x86_64", "aarch64"]
                            .map {
                                arch =>
                                let dir =
                                    home.join("runtime").join("lib").join("${os}_${arch}_cjnative")
                                Directory.create(dir, recursive: true)
                                let suffix =
                                    match (os) {
                                        case "linux" => ".so"
                                        case "darwin" => ".dylib"
                                        case _ => ".dll"
                                    }
                                File.writeTo(dir.join("libcangjie-std-ast${suffix}"), [])
                                dir
                            }
                    }
            let reversed = Array(runtimes.size) { i => runtimes[runtimes.size - 1 - i] }
            for (candidates in [runtimes, reversed]) {
                let paths = sdkPaths(home, candidates)
                @Expect(paths.runtimeLib.fileName.endsWith("_${hostArch()}_cjnative"))
                @Expect(exists(paths.runtimeLib.join("libcangjie-std-ast${sharedLibrarySuffix()}")))
                @AssertThrows[IllegalStateException](sdkPaths(home, candidates.filter {dir => dir != paths.runtimeLib}))
            }
        } finally {
            remove(home, recursive: true)
        }
    }
}

func derivingLibrary(paths: MacroServerPaths): String {
    (
        paths.stdMacroLibrary("std.deriving") ??
            throw IllegalStateException("no libcangjie-std-deriving in ${paths.runtimeLib}")
    )
        .toString()
}

/**
 * `@Derive[<attrs>] <decl>` as a call of std's `Derive`, on line 1 of file 1.
 */
func deriveCall(
    paths: MacroServerPaths,
    attrs: String,
    decl: String,
    method!: String = "macroCall_a_Derive_std_deriving"
): MacroCallData {
    let declColumn = "@Derive[".size + attrs.size + "] ".size + 1
    MacroCallData(
        id: IdInfoData(name: "Derive", pos: PositionData(fileId: 1, line: 1, column: 2)),
        hasAttrs: true,
        args: tokensOf(decl, declColumn),
        attrs: tokensOf(attrs, "@Derive[".size + 1),
        methodName: method,
        packageName: "std.deriving",
        libPath: derivingLibrary(paths),
        begin: PositionData(fileId: 1, line: 1, column: 1),
        end: PositionData(fileId: 1, line: 1, column: Int32(declColumn + decl.size))
    )
}

func valuesOf(result: MacroResult): Array<String> {
    result.tks.toArray().map { t => t.value ?? "" }
}

/**
 * The SDK's own server, run on std's `@Derive`: its library ships with the SDK, nothing is built.
 */
@Test
class MacroServerTest {
    @TestCase
    func theLibraryOfAPackageOfStdIsFoundByItsNameAndNoneOfOneWithout(): Unit {
        // arrange
        let paths = sdkPaths()

        // act
        let testmacro = paths.stdMacroLibrary("std.unittest.testmacro")
        let none = paths.stdMacroLibrary("std.nothing")

        // assert
        @Expect(testmacro.map {path => path.fileName.startsWith("libcangjie-std-unittest.testmacro.")}, Some(true))
        @Expect(none.isNone())
    }

    @TestCase
    func aDeriveIsExpandedIntoItsExtend(): Unit {
        // arrange
        let paths = sdkPaths()
        let server = startMacroServer(paths)

        // act
        let result =
            server.connection.expand(deriveCall(paths, "ToString", "class A { let x: Int64 = 1 }"))
        server.close()

        // assert
        @Expect(result.status != MACRO_FAILED)
        let values = valuesOf(result)
        @Expect(values.contains("extend"))
        @Expect(values.contains("ToString"))
        @Expect(values.contains("toString"))
    }

    @TestCase
    func theServerAnswersTheCallsAfterOneThatFailed(): Unit {
        // arrange
        let paths = sdkPaths()
        let server = startMacroServer(paths)

        // act
        let failed = server.connection.expand(deriveCall(paths, "NoSuchInterface", "class A {}"))
        let next =
            server.connection.expand(deriveCall(paths, "Hashable", "struct P { let x: Int64 = 1 }"))
        server.close()

        // assert
        @Expect(failed.status == MACRO_FAILED || failed.diags.size > 0)
        @Expect(next.status != MACRO_FAILED)
        @Expect(next.diags.size, 0)
        @Expect(valuesOf(next).contains("hashCode"))
    }

    @TestCase
    func aSymbolNotFoundEndsTheServer(): Unit {
        // arrange
        let paths = sdkPaths()
        let server = startMacroServer(paths)

        // act, assert
        @AssertThrows[MacroServerException](
            server.connection.expand(deriveCall(paths, "ToString", "class A {}", method: "macroCall_a_NoSuch_std_deriving")))
        server.kill()
    }
}
