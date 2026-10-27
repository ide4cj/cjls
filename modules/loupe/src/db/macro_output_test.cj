package loupe.db

import std.unittest.*
import std.unittest.testmacro.*
import ginkgo.TextRange

@Test
class MappedTextTest {
    @TestCase
    func aRangeInTextCopiedFromTheSourceIsTheSamePartOfIt() {
        // arrange
        let mapped = MappedText.fromSource("class C {}", 40)

        // act
        let origin = mapped.originOf(TextRange(6, 7))

        // assert
        @Expect(origin, Some(SpanOrigin.FromSource(TextRange(46, 47))))
    }

    @TestCase
    func aRangeInASpanOfAnotherLengthIsAllOfItsOrigin() {
        // arrange
        let mapped =
            MappedText(
                "\"a\" x",
                [
                    MappedSpan(TextRange(0, 3), SpanOrigin.FromSource(TextRange(10, 15))),
                    MappedSpan(TextRange(4, 5), SpanOrigin.FromCall)
                ]
            )

        // act
        let string = mapped.originOf(TextRange(1, 2))
        let written = mapped.originOf(TextRange(4, 5))
        let between = mapped.originOf(TextRange(3, 4))

        // assert
        @Expect(string, Some(SpanOrigin.FromSource(TextRange(10, 15))))
        @Expect(written, Some(SpanOrigin.FromCall))
        @Expect(between, None)
    }

    @TestCase
    func aFailedRunKeepsTheExpansionOfTheLastThatSucceeded() {
        // arrange
        let outputs =
            MacroOutputs()
                .withOutput(
                    MacroCallKey("Class#1/0", 0),
                    MacroOutput(
                        1,
                        MappedText.fromSource("x", 0),
                        [MacroItem("k", MacroItemValue.IntItem(1))],
                        []
                    )
                )
        let failed =
            MacroOutput(2, None, [], [MacroDiagnostic(MacroSeverity.MacroError, None, "no", "")])

        // act
        let after =
            outputs
                .withOutput(MacroCallKey("Class#1/0", 0), failed)
                .get(MacroCallKey("Class#1/0", 0))

        // assert
        @Expect(after?.fingerprint, Some(2))
        @Expect(after?.expansion?.text, Some("x"))
        @Expect(after?.items.size, Some(1))
        @Expect(after?.diagnostics.size, Some(1))
    }

    @TestCase
    func aCallInAnItemIsKeptApartFromTheCallOnItOfTheSameIndex() {
        // arrange
        let onItem = MacroCallKey("Func#1/0", 0)
        let inItem = MacroCallKey("Func#1/0", 0, inBody: "m.M")
        let outputs = MacroOutputs().withOutput(onItem, MacroOutput(1, None, [], []))

        // act
        let found = outputs.get(inItem)

        // assert
        @Expect(found.isNone(), true)
        @Expect(onItem.toString(), "Func#1/0@0")
        @Expect(inItem.toString(), "Func#1/0/@m.M#0")
    }
}
