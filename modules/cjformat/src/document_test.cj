package cjformat

import std.unittest.*
import std.unittest.testmacro.*

@Test
class DocumentTest {
    @TestCase
    func aGroupFitsExactlyOrBreaksWithIndentation(): Unit {
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
        @Expect(Printer(14, "\n").print(doc), "call(one, two)")
        @Expect(Printer(13, "\n").print(doc), "call(\n    one,\n    two\n)")
    }

    @TestCase
    func nestedGroupsDecideIndependentlyAndIfBreakUsesTheEnclosingGroup(): Unit {
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
        @Expect(Printer(20, "\n").print(doc), "aaaa b c?")
        @Expect(Printer(8, "\n").print(doc), "aaaa\n    b c!")
    }

    @TestCase
    func hardlinesAndSuffixesPreventFlatteningAndDropTrailingSpaces(): Unit {
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
        @Expect(Printer(100, "\r\n").print(doc), "a // c\r\nb\r\n")
    }

    @TestCase
    func fittingAccountsForTheUnbreakableSuffixOutsideAGroup(): Unit {
        let doc =
            concat([group(concat([textDoc("abc"), softline(), textDoc("def")])), textDoc(");")])
        @Expect(Printer(8, "\n").print(doc), "abc\ndef);")
        @Expect(Printer(9, "\n").print(doc), "abc def);")
    }

    @TestCase
    func multilineLiteralTextResetsTheColumn(): Unit {
        let doc = concat([textDoc("012345\nx"), group(concat([softline(), textDoc("y")]))])
        @Expect(Printer(5, "\n").print(doc), "012345\nx y")
    }

    @TestCase
    func scalarValuesCountOnceAndUnbreakableTextMayOverflow(): Unit {
        let doc = group(concat([textDoc("ёж😀"), softline(), textDoc("x")]))
        @Expect(Printer(5, "\n").print(doc), "ёж😀 x")
        @Expect(Printer(4, "\n").print(doc), "ёж😀\nx")
        @Expect(Printer(2, "\n").print(textDoc("abcdef")), "abcdef")
    }
}
