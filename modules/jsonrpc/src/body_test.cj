package jsonrpc

import std.unittest.*
import std.unittest.testmacro.*
import fjson.*
import stdxx.{IntegerOrString, UnexpectedVariantException}
import stdxx.serialization.*

func rawJson(json: String): RawJson {
    RawJson(json.toArray())
}

/**
 * The params read into a tree, for a test to look into.
 */
func fieldOf(params: ?RawJson, name: String): AnyValue {
    params.getOrThrow().read<AnyValue>()[name]
}

func bodyOf(json: String): Body {
    fromJsonBytes<Body>(json.toArray())
}

@Test
class BodyCodecTest {
    // The shape is the discriminator, so reading a frame as the wrong variant writes it back
    // with other keys: a round trip pins the variant as well as every field.
    @TestCase[json in [
        ##"{"jsonrpc":"2.0","id":1,"method":"m"}"##,
        ##"{"jsonrpc":"2.0","id":"abc","method":"m"}"##,
        ##"{"jsonrpc":"2.0","id":1,"method":"m","params":{"a":42}}"##,
        ##"{"jsonrpc":"2.0","id":1,"method":"m","params":[1,2]}"##,
        ##"{"jsonrpc":"2.0","method":"m"}"##,
        ##"{"jsonrpc":"2.0","method":"m","params":{"a":"b"}}"##,
        ##"{"jsonrpc":"2.0","id":1,"result":42}"##,
        ##"{"jsonrpc":"2.0","id":1,"result":null}"##,
        ##"{"jsonrpc":"2.0","id":null,"result":42}"##,
        ##"{"jsonrpc":"2.0","id":1,"error":{"code":-32700,"message":"parse error"}}"##,
        ##"{"jsonrpc":"2.0","id":1,"error":{"code":1,"message":"m","data":{"a":[1]}}}"##
    ]]
    func aMessageReadsBackAsItWasWritten(json: String) {
        // act
        let written = String.fromUtf8(toJsonBytes(bodyOf(json)))

        // assert
        @Expect(json, written)
    }

    @TestCase
    func anUnknownFieldIsIgnored() {
        // act
        let body = bodyOf(##"{"jsonrpc":"2.0","id":1,"method":"m","unknown":"x"}"##)

        // assert
        @Expect("m", body.getRequestBodyOrThrow().method)
    }

    @TestCase[json in [
        ##"{"method":"m"}"##,
        ##"{"jsonrpc":"1.0","method":"m"}"##,
        ##"{"jsonrpc":2.0,"method":"m"}"##,
        ##"{"jsonrpc":null,"method":"m"}"##,
        ##"{"jsonrpc":"2.0.0","id":1,"method":"m"}"##
    ]]
    func aWrongProtocolVersionIsAnInvalidRequest(json: String) {
        // act
        let e = @AssertThrows[RpcException](bodyOf(json))

        // assert
        @Expect(ErrorCode.INVALID_REQUEST, e.code)
    }

    @TestCase[json in [
        ##"{"jsonrpc":"2.0","id":1,"method":"m","params":42}"##,
        ##"{"jsonrpc":"2.0","method":"m","params":"x"}"##,
        ##"{"jsonrpc":"2.0","id":null,"method":"m"}"##
    ]]
    func paramsThatAreNotStructuredOrANullRequestIdAreAnInvalidRequest(json: String) {
        // act
        let e = @AssertThrows[RpcException](bodyOf(json))

        // assert
        @Expect(ErrorCode.INVALID_REQUEST, e.code)
    }

    @TestCase
    func nullParamsReadAsNone() {
        // act
        let body = bodyOf(##"{"jsonrpc":"2.0","method":"m","params":null}"##)

        // assert
        @Expect(body.getNotificationBodyOrThrow().params.isNone())
    }

    @TestCase
    func paramsBeforeTheMethodAreKeptAsTheyCame() {
        // act
        let body = bodyOf(##"{"params": {"a" : [1, 2]}, "method":"m", "id": 3, "jsonrpc":"2.0"}"##)

        // assert
        let request = body.getRequestBodyOrThrow()
        @Expect("m", request.method)
        @Expect(##"{"a" : [1, 2]}"##, request.params.getOrThrow().toString())
    }

    @TestCase
    func aResponseWithBothResultAndErrorIsAnInvalidRequest() {
        // arrange
        let json = ##"{"jsonrpc":"2.0","id":1,"result":42,"error":{"code":-32700,"message":"x"}}"##

        // act
        let e = @AssertThrows[RpcException](bodyOf(json))

        // assert
        @Expect(ErrorCode.INVALID_REQUEST, e.code)
    }

    @TestCase
    func aGetterOfTheWrongVariantNamesBoth() {
        // arrange
        let request = RequestBody(Integer(1), "m").enveloped()
        let notification = NotificationBody("m").enveloped()
        let response = ResponseBody(Value(Integer(1)), Result(rawJson("null"))).enveloped()

        // act
        let onRequest = @AssertThrows[UnexpectedVariantException](request.getResponseBodyOrThrow())
        let onNotification = @AssertThrows[UnexpectedVariantException](notification.getRequestBodyOrThrow())
        let onResponse = @AssertThrows[UnexpectedVariantException](response.getNotificationBodyOrThrow())

        // assert
        @Expect("expected `Response` variant, got `Request`", onRequest.message)
        @Expect("expected `Request` variant, got `Notification`", onNotification.message)
        @Expect("expected `Notification` variant, got `Response`", onResponse.message)
    }
}

@Test
class ResultOrErrorTest {
    @TestCase
    func aGetterOfTheWrongVariantNamesBoth() {
        // arrange
        let result = ResultOrError.Result(rawJson("null"))
        let error = ResultOrError.Error(ResponseError(ErrorCode.PARSE_ERROR, "parse error"))

        // act
        let onError = @AssertThrows[UnexpectedVariantException](error.getResultOrThrow())
        let onResult = @AssertThrows[UnexpectedVariantException](result.getErrorOrThrow())

        // assert
        @Expect("expected `Result` variant, got `Error`", onError.message)
        @Expect("expected `Error` variant, got `Result`", onResult.message)
    }
}
