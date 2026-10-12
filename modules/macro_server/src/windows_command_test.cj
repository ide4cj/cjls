package macro_server

import std.fs.Path
import std.unittest.*
import std.unittest.testmacro.*

func text(units: Array<UInt16>): String {
    String(units.map {u => Rune(UInt32(u))})
}

@Test
class WindowsCommandTest {
    @TestCase
    func aRuneBeyondTheBasicPlaneIsASurrogatePair(): Unit {
        // act
        let units = utf16("a😀")

        // assert
        @Expect(units, [0x61u16, 0xD83Du16, 0xDE00u16])
    }

    @TestCase
    func anArgumentIsQuotedAsCommandLineToArgvWReadsIt(): Unit {
        // act, assert
        @Expect(quoteWindowsArg("plain"), "plain")
        @Expect(quoteWindowsArg(""), "\"\"")
        @Expect(quoteWindowsArg("C:\\Program Files\\cj"), "\"C:\\Program Files\\cj\"")
        @Expect(quoteWindowsArg("a \"b\""), "\"a \\\"b\\\"\"")
        @Expect(quoteWindowsArg("dir with\\"), "\"dir with\\\\\"")
        @Expect(quoteWindowsArg("x\\\" y"), "\"x\\\\\\\" y\"")
    }

    @TestCase
    func theCommandLineIsTheServerItsTwoHandlesSerialAndCjc(): Unit {
        // arrange
        let paths = MacroServerPaths.inSdk(Path("C:\\Cangjie SDK"), "windows_x86_64_cjnative")

        // act
        let line = windowsCommandLine(paths, 520, 524)

        // assert
        @Expect(line, "\"${paths.server}\" 520 524 0 \"${paths.cjc}\"")
        @Expect(paths.server.toString().endsWith("LSPMacroServer.exe"))
    }

    @TestCase
    func theRuntimeGoesFirstOnPathWhateverItsCase(): Unit {
        // act
        let block = text(windowsEnvironment([("b", "2"), ("Path", "C:\\bin"), ("A", "1")], "C:\\rt"))

        // assert
        @Expect(block, "A=1\u{0}b=2\u{0}PATH=C:\\rt;C:\\bin\u{0}\u{0}")
    }

    @TestCase
    func withNoPathTheRuntimeIsAllOfIt(): Unit {
        // act
        let block = text(windowsEnvironment([("X", "1")], "C:\\rt"))

        // assert
        @Expect(block, "PATH=C:\\rt\u{0}X=1\u{0}\u{0}")
    }
}
