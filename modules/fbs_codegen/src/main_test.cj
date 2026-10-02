package fbs_codegen

import std.argopt.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
class ParseConfigPathTest {
    @TestCase
    func takesTheConfigFromTheOneArgument() {
        // act
        let sut = parseConfigPath(["cjo_format.toml"])

        // assert
        @Expect("cjo_format.toml", sut.toString())
    }

    @TestCase[args in [[], ["a.toml", "b.toml"], ["   "], ["--help"], ["-h", "cjo_format.toml"]]]
    func anOptionOrAnythingButOneConfigIsRefused(args: Array<String>) {
        // act & assert
        @AssertThrows[ArgumentParseException](parseConfigPath(args))
    }
}
