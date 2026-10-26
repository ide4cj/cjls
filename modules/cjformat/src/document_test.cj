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
        let printed1 = Printer(14, "\n").print(doc)
        let printed2 = Printer(13, "\n").print(doc)

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
        let printed1 = Printer(20, "\n").print(doc)
        let printed2 = Printer(8, "\n").print(doc)

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
        let printed1 = Printer(100, "\r\n").print(doc)

        // assert
        @Expect(printed1, "a // c\r\nb\r\n")
    }

    @TestCase
    func fittingAccountsForTheUnbreakableSuffixOutsideAGroup(): Unit {
        // arrange
        let doc =
            concat([group(concat([textDoc("abc"), softline(), textDoc("def")])), textDoc(");")])

        // act
        let printed1 = Printer(8, "\n").print(doc)
        let printed2 = Printer(9, "\n").print(doc)

        // assert
        @Expect(printed1, "abc\ndef);")
        @Expect(printed2, "abc def);")
    }

    @TestCase
    func multilineLiteralTextResetsTheColumn(): Unit {
        // arrange
        let doc = concat([textDoc("012345\nx"), group(concat([softline(), textDoc("y")]))])

        // act
        let printed1 = Printer(5, "\n").print(doc)

        // assert
        @Expect(printed1, "012345\nx y")
    }

    @TestCase
    func scalarValuesCountOnceAndUnbreakableTextMayOverflow(): Unit {
        // arrange
        let doc = group(concat([textDoc("ёж😀"), softline(), textDoc("x")]))

        // act
        let printed1 = Printer(5, "\n").print(doc)
        let printed2 = Printer(4, "\n").print(doc)
        let printed3 = Printer(2, "\n").print(textDoc("abcdef"))

        // assert
        @Expect(printed1, "ёж😀 x")
        @Expect(printed2, "ёж😀\nx")
        @Expect(printed3, "abcdef")
    }
}
