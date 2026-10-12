package macro_server

import std.env.getVariable
import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*

/**
 * The tokens of `code` as a call sends them, of file 1, `code` starting at line 1, column `column`.
 */
func tokensOf(code: String, column: Int64): Array<TokenData> {
    macroTokens(code, sdkNumbers(), PositionData(fileId: 1, line: 1, column: Int32(column)))
}

/** What a shared library ends with on each platform. */
let LIBRARY_SUFFIXES = [".so", ".dylib", ".dll"]

/**
 * The SDK the tests run on, and the directory of its runtime for this host: the one that has std.ast.
 */
func sdkPaths(): MacroServerPaths {
    let home = Path(getVariable("CANGJIE_HOME") ?? throw IllegalStateException("CANGJIE_HOME names no SDK"))
    for (dir in Directory.readFrom(home.join("runtime").join("lib")) where dir.isDirectory()) {
        let name = dir.path.fileName
        if (LIBRARY_SUFFIXES.iterator().any {suffix => exists(dir.path.join("libcangjie-std-ast${suffix}"))}) {
            return MacroServerPaths.inSdk(home, name)
        }
    }
    throw IllegalStateException("no runtime under ${home}")
}

func derivingLibrary(paths: MacroServerPaths): String {
    for (suffix in LIBRARY_SUFFIXES) {
        let library = paths.runtimeLib.join("libcangjie-std-deriving${suffix}")
        if (exists(library)) {
            return library.toString()
        }
    }
    throw IllegalStateException("no libcangjie-std-deriving in ${paths.runtimeLib}")
}

/**
 * `@Derive[<attrs>] <decl>` as a call of std's `Derive`, on line 1 of file 1.
 */
func deriveCall(paths: MacroServerPaths, attrs: String, decl: String, method!: String = "macroCall_a_Derive_std_deriving"): MacroCallData {
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
    result.tks.toArray().map {t => t.value ?? ""}
}

/**
 * The SDK's own server, run on std's `@Derive`: its library ships with the SDK, nothing is built.
 */
@Test
class MacroServerTest {
    @TestCase
    func aDeriveIsExpandedIntoItsExtend(): Unit {
        // arrange
        let paths = sdkPaths()
        let server = startMacroServer(paths)

        // act
        let result = server.connection.expand(deriveCall(paths, "ToString", "class A { let x: Int64 = 1 }"))
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
        let next = server.connection.expand(deriveCall(paths, "Hashable", "struct P { let x: Int64 = 1 }"))
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
