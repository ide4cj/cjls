package jsonrpc

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import fjson.*

/**
 * Whatever a client sends, reading it throws `FjException` or `RpcException`, which the read loop
 * answers: anything else ends the loop, and the connection with it.
 */
@Test
class BodyFuzzTest {
    let messages = [
        ##"{"jsonrpc":"2.0","id":1,"method":"textDocument/hover","params":{"textDocument":{"uri":"file:///a.cj"},"position":{"line":3,"character":14}}}"##,
        ##"{"jsonrpc":"2.0","id":"a-1","method":"shutdown"}"##,
        ##"{"params":[1,-2.5e3,true,null,"\u00e9\ud83d\ude00 é😀"],"method":"m","jsonrpc":"2.0"}"##,
        ##"{"jsonrpc":"2.0","id":7,"result":{"capabilities":{}}}"##,
        ##"{"jsonrpc":"2.0","id":null,"error":{"code":-32700,"message":"parse error","data":{"at":[0]}}}"##
    ]
    let bytesTried: Array<Byte> = [0x00, 0x20, 0x22, 0x2C, 0x2D, 0x30, 0x3A, 0x5B, 0x5C, 0x5D, 0x6E, 0x7B, 0x7D, 0x80, 0xFF]

    func check(bytes: Array<Byte>, failures: ArrayList<String>): Unit {
        try {
            fromJsonBytes<Body>(bytes)
            ()
        } catch (_: FjException) {
            ()
        } catch (_: RpcException) {
            ()
        } catch (e: Exception) {
            failures.add("${bytes}: ${e}")
        }
    }

    @TestCase
    func everyTruncationOrByteReplacedOrDroppedIsAnsweredAsAnError() {
        // arrange
        let failures = ArrayList<String>()

        for (message in messages) {
            let bytes = message.toArray()
            for (at in 0..bytes.size) {
                // act
                check(bytes[0..at], failures)
                check(bytes[0..at].concat(bytes[at + 1..]), failures)
                for (b in bytesTried) {
                    let replaced = bytes.clone()
                    replaced[at] = b
                    check(replaced, failures)
                }
            }
        }

        // assert
        @Expect(String.join(failures.toArray(), delimiter: "\n"), "")
    }
}
