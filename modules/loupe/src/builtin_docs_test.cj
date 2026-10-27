package loupe

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
class BuiltinDocsTest {
    @TestCase
    func everyBuiltinIsToldOnce() {
        // arrange
        let names = HashSet<String>()

        // act
        let twice =
            builtinDocs() |> filter { doc: BuiltinDoc => !names.add(doc.name) } |>
                map { doc: BuiltinDoc => doc.name } |>
                collectArray

        // assert
        @Expect(twice, Array<String>())
    }
}
