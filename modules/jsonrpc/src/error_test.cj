package jsonrpc

import std.unittest.*
import std.unittest.testmacro.*
import std.unittest.prop_test.*
import fjson.*

@Test
class ResponseErrorTest {
    func errorOf(json: String): ResponseError {
        fromJsonBytes<ResponseError>(json.toArray())
    }

    @TestCase[json in [
        ##"{"code":-32700,"message":"parse error"}"##,
        ##"{"code":-32700,"message":"parse error","data":"extra"}"##,
        ##"{"code":1,"message":"m","data":{"a":[1,null]}}"##
    ]]
    func anErrorReadsBackAsItWasWritten(json: String) {
        // act
        let written = String.fromUtf8(toJsonBytes(errorOf(json)))

        // assert
        @Expect(json, written)
    }

    @TestCase[json in [ "42", "\"boom\"", "[-32700]", "null", ##"{"message":"m"}"##, ##"{"code":-32700}"## ]]
    func anErrorWithoutCodeAndMessageDoesNotRead(json: String) {
        // act & assert
        @AssertThrows[FjException](errorOf(json))
    }
}

@Test
@Configure[randomSeed: 100500]
class ErrorCodeTest {
    @TestCase[value in random()]
    func anyCodeSurvivesARoundTrip(value: Int32) {
        // arrange - the codes are open, so one this side has no constant for is kept as is
        let code = ErrorCode(value)

        // act
        let written = String.fromUtf8(toJsonBytes(code))

        // assert
        @Expect(code, fromJsonBytes<ErrorCode>(written.toArray()))
        @Expect(value.toString(), written)
        @Expect(value.toString(), code.toString())
    }

    @TestCase
    func aCodeThatIsNoInt32DoesNotRead() {
        // act & assert
        @AssertThrows[FjException](fromJsonBytes<ErrorCode>(#""-32700""#.toArray()))
        @AssertThrows[FjException](fromJsonBytes<ErrorCode>("9999999999".toArray()))
    }
}
