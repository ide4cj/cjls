package syntax_codegen

import std.argopt.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
class ParseKindsFileTest {
    @TestCase
    func takesTheKindsFileFromTheOneArgument() {
        // act
        let sut = parseKindsFile(["syntax_kinds.toml"])

        // assert
        @Expect("syntax_kinds.toml", sut.toString())
    }

    @TestCase[args in [[], ["a.toml", "b.toml"], ["   "], ["--help"], ["-h", "syntax_kinds.toml"]]]
    func anOptionOrAnythingButOneFileIsRefused(args: Array<String>) {
        // act & assert
        @AssertThrows[ArgumentParseException](parseKindsFile(args))
    }
}
