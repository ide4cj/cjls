features {os.windows}
package platform

import std.unittest.*
import std.unittest.testmacro.*

func text(units: Array<UInt16>): String {
    String(units.map { u => Rune(UInt32(u)) })
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
    func theCommandLineIsEachArgumentQuoted(): Unit {
        // act
        let line =
            windowsCommandLine(
                ["C:\\Cangjie SDK\\LSPMacroServer.exe", "520", "524", "0", "C:\\sdk\\cjc.exe"]
            )

        // assert
        @Expect(line, "\"C:\\Cangjie SDK\\LSPMacroServer.exe\" 520 524 0 C:\\sdk\\cjc.exe")
    }

    @TestCase
    func theLibraryDirectoryGoesFirstOnPathWhateverItsCase(): Unit {
        // act
        let block =
            text(windowsEnvironment([("b", "2"), ("Path", "C:\\bin"), ("A", "1")], "C:\\rt"))

        // assert
        @Expect(block, "A=1\u{0}b=2\u{0}PATH=C:\\rt;C:\\bin\u{0}\u{0}")
    }

    @TestCase
    func withNoPathTheLibraryDirectoryIsAllOfIt(): Unit {
        // act
        let block = text(windowsEnvironment([("X", "1")], "C:\\rt"))

        // assert
        @Expect(block, "PATH=C:\\rt\u{0}X=1\u{0}\u{0}")
    }
}
