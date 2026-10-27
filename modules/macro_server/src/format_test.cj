package macro_server

import std.unittest.*
import std.unittest.testmacro.*

func position(line: Int32, column: Int32): PositionData {
    PositionData(fileId: 1, line: line, column: column)
}

@Test
class FormatTest {
    @TestCase
    func aCallIsReadBackAsItWasWritten(): Unit {
        // arrange
        let call =
            MacroCallData(
                id: IdInfoData(name: "Derive", pos: position(1, 2)),
                hasAttrs: true,
                args: [TokenData(kind: 7, value: "x", begin: position(2, 1), end: position(2, 2))],
                attrs: [TokenData(kind: 8, value: "ToString", delimiterNum: 1)],
                parentNames: ["Outer"],
                childMsges: [
                    ChildMsgData(
                        childName: "Inner",
                        items: [
                            ItemInfoData(
                                key: "n",
                                value: OptionValueData.AsIValue(IntValueData(val: -5))
                            ),
                            ItemInfoData(key: "s", value: OptionValueData.AsSValue("text"))
                        ]
                    )
                ],
                methodName: "macroCall_a_Derive_std_deriving",
                packageName: "std.deriving",
                libPath: "/sdk/libcangjie-std-deriving.so",
                begin: position(1, 1),
                end: position(3, 2)
            )
        let bytes =
            MacroMsgData(content: MsgContentData.AsMultiCalls(MultiMacroCallsData(calls: [call])))
                .toBytes()

        // act
        let read =
            match (MacroMsg.root(bytes).content) {
                case Some(MsgContent.AsMultiCalls(m)) => m.calls[0]
                case _ => throw IllegalStateException("no multiCalls")
            }

        // assert
        @Expect(read.id?.name, Some("Derive"))
        @Expect(read.id?.pos?.column, Some(2i32))
        @Expect(read.hasAttrs, true)
        @Expect(read.args[0].value, Some("x"))
        @Expect(read.args[0].end?.column, Some(2i32))
        @Expect(read.attrs[0].kind, 8u8)
        @Expect(read.attrs[0].delimiterNum, 1u32)
        @Expect(read.parentNames.toArray(), ["Outer"])
        @Expect(read.childMsges[0].childName, Some("Inner"))
        match (read.childMsges[0].items[0].value) {
            case Some(OptionValue.AsIValue(v)) => @Expect(v.val, -5)
            case _ => @Fail("no iValue")
        }
        match (read.childMsges[0].items[1].value) {
            case Some(OptionValue.AsSValue(v)) => @Expect(v, "text")
            case _ => @Fail("no sValue")
        }
        @Expect(read.methodName, Some("macroCall_a_Derive_std_deriving"))
        @Expect(read.libPath, Some("/sdk/libcangjie-std-deriving.so"))
        @Expect(read.end?.line, Some(3i32))
    }

    @TestCase
    func anExitTaskIsAStructAlone(): Unit {
        // act
        let content = MacroMsg.root(exitTask(true)).content

        // assert
        match (content) {
            case Some(MsgContent.AsExitTask(t)) => @Expect(t.flag, true)
            case _ => @Fail("no exitTask")
        }
    }

    @TestCase
    func aDefaultScalarIsNotStoredAndReadsAsItsDefault(): Unit {
        // arrange
        let bytes =
            MacroMsgData(
                content: MsgContentData
                    .AsMultiCalls(
                        MultiMacroCallsData(
                            calls: [MacroCallData(args: [TokenData(delimiterNum: 1)])]
                        )
                    )
            )
                .toBytes()

        // act
        let token =
            match (MacroMsg.root(bytes).content) {
                case Some(MsgContent.AsMultiCalls(m)) => m.calls[0].args[0]
                case _ => throw IllegalStateException("no multiCalls")
            }

        // assert
        @Expect(token.fb.offset(4), 0)
        @Expect(token.delimiterNum, 1u32)
    }
}
