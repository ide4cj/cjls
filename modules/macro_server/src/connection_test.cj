package macro_server

import std.io.*
import std.unittest.*
import std.unittest.testmacro.*

/**
 * A connection whose server has written `answers` already, and what the connection writes to it.
 */
func answered(answers: Array<Array<Byte>>): (MacroConnection, ByteBuffer) {
    let input = ByteBuffer()
    for (a in answers) {
        writeMessage(input, a)
    }
    let output = ByteBuffer()
    (MacroConnection(input, output), output)
}

func resultMessage(status: UInt8): Array<Byte> {
    MacroMsgData(content: MsgContentData.AsMacroResult(MacroResultData(status: status, tks: [TokenData(value: "x")])))
        .toBytes()
}

@Test
class MacroConnectionTest {
    @TestCase
    func aCallIsOneMessageFollowedByAnExitTaskThatKeepsTheServer(): Unit {
        // arrange
        let (sut, output) = answered([resultMessage(MACRO_FAILED)])

        // act
        let result = sut.expand(MacroCallData(methodName: "m"))

        // assert
        @Expect(result.status, MACRO_FAILED)
        @Expect(result.tks[0].value, Some("x"))
        match (MacroMsg.root(readMessage(output).getOrThrow()).content) {
            case Some(MsgContent.AsMultiCalls(m)) => @Expect(m.calls.toArray().map {c => c.methodName}, [Some("m")])
            case _ => @Fail("no multiCalls")
        }
        match (MacroMsg.root(readMessage(output).getOrThrow()).content) {
            case Some(MsgContent.AsExitTask(t)) => @Expect(t.flag, false)
            case _ => @Fail("no exitTask")
        }
    }

    @TestCase
    func aServerThatExitedThrows(): Unit {
        // arrange
        let (sut, _) = answered([])

        // act, assert
        @AssertThrows[MacroServerException](sut.expand(MacroCallData()))
    }

    @TestCase
    func anAnswerThatIsNoResultThrows(): Unit {
        // arrange
        let (sut, _) = answered([exitTask(false)])

        // act, assert
        @AssertThrows[MacroServerException](sut.expand(MacroCallData()))
    }

    @TestCase
    func aBrokenAnswerThrows(): Unit {
        // arrange
        let (sut, _) = answered([[200, 0, 0, 0, 1, 2, 3, 4]])

        // act, assert
        @AssertThrows[MacroServerException](sut.expand(MacroCallData()))
    }

    @TestCase
    func closeAsksTheServerToExit(): Unit {
        // arrange
        let (sut, output) = answered([])

        // act
        sut.close()

        // assert
        match (MacroMsg.root(readMessage(output).getOrThrow()).content) {
            case Some(MsgContent.AsExitTask(t)) => @Expect(t.flag, true)
            case _ => @Fail("no exitTask")
        }
    }
}
