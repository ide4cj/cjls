package cjformat

import std.unittest.*
import std.unittest.testmacro.*

@Test
class DocumentTest {
    @TestCase
    func aGroupFitsExactlyOrBreaksWithIndentation(): Unit {
        // arrange
        let doc =
            group(
                concat(
                    [
                        textDoc("call("),
                        indent(concat([softbreak(), textDoc("one,"), softline(), textDoc("two")])),
                        softbreak(),
                        textDoc(")")
                    ]
                )
            )

        // act
        let printed1 = Printer("\n", width: 14).print(doc)
        let printed2 = Printer("\n", width: 13).print(doc)

        // assert
        @Expect(printed1, "call(one, two)")
        @Expect(printed2, "call(\n    one,\n    two\n)")
    }

    @TestCase
    func nestedGroupsDecideIndependentlyAndIfBreakUsesTheEnclosingGroup(): Unit {
        // arrange
        let inner = group(concat([textDoc("b"), softline(), textDoc("c")]))
        let doc =
            group(
                concat(
                    [
                        textDoc("aaaa"),
                        indent(concat([softline(), inner])),
                        ifBreak(textDoc("!"), textDoc("?"))
                    ]
                )
            )

        // act
        let printed1 = Printer("\n", width: 20).print(doc)
        let printed2 = Printer("\n", width: 8).print(doc)

        // assert
        @Expect(printed1, "aaaa b c?")
        @Expect(printed2, "aaaa\n    b c!")
    }

    @TestCase
    func hardlinesAndSuffixesPreventFlatteningAndDropTrailingSpaces(): Unit {
        // arrange
        let doc =
            group(
                concat(
                    [
                        textDoc("a"),
                        lineSuffix(textDoc(" // c")),
                        softline(),
                        textDoc("b"),
                        textDoc(" "),
                        hardline()
                    ]
                )
            )

        // act
        let printed1 = Printer("\r\n", width: 100).print(doc)

        // assert
        @Expect(printed1, "a // c\r\nb\r\n")
    }

    @TestCase
    func fittingAccountsForTheUnbreakableSuffixOutsideAGroup(): Unit {
        // arrange
        let doc =
            concat([group(concat([textDoc("abc"), softline(), textDoc("def")])), textDoc(");")])

        // act
        let printed1 = Printer("\n", width: 8).print(doc)
        let printed2 = Printer("\n", width: 9).print(doc)

        // assert
        @Expect(printed1, "abc\ndef);")
        @Expect(printed2, "abc def);")
    }

    @TestCase
    func multilineLiteralTextResetsTheColumn(): Unit {
        // arrange
        let doc = concat([textDoc("012345\nx"), group(concat([softline(), textDoc("y")]))])

        // act
        let printed1 = Printer("\n", width: 5).print(doc)

        // assert
        @Expect(printed1, "012345\nx y")
    }

    @TestCase
    func scalarValuesCountOnceAndUnbreakableTextMayOverflow(): Unit {
        // arrange
        let doc = group(concat([textDoc("ёж😀"), softline(), textDoc("x")]))

        // act
        let printed1 = Printer("\n", width: 5).print(doc)
        let printed2 = Printer("\n", width: 4).print(doc)
        let printed3 = Printer("\n", width: 2).print(textDoc("abcdef"))

        // assert
        @Expect(printed1, "ёж😀 x")
        @Expect(printed2, "ёж😀\nx")
        @Expect(printed3, "abcdef")
    }
}
