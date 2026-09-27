package jsonrpc

import std.collection.*
import std.convert.*
import std.unittest.*
import std.unittest.prop_test.*
import std.unittest.testmacro.*
import fjson.*

/** The messages the fuzzers start from, one of each shape. */
let FUZZ_MESSAGES = [
    ##"{"jsonrpc":"2.0","id":1,"method":"textDocument/hover","params":{"textDocument":{"uri":"file:///a.cj"},"position":{"line":3,"character":14}}}"##,
    ##"{"jsonrpc":"2.0","id":"a-1","method":"shutdown"}"##,
    ##"{"params":[1,-2.5e3,true,null,"\u00e9\ud83d\ude00 é😀"],"method":"m","jsonrpc":"2.0"}"##,
    ##"{"jsonrpc":"2.0","id":7,"result":{"capabilities":{}}}"##,
    ##"{"jsonrpc":"2.0","id":null,"error":{"code":-32700,"message":"parse error","data":{"at":[0]}}}"##
].map {message => message.toArray()}

/** What reading `bytes` as a message threw, unless it read or threw what the read loop answers. */
func readOrAnswer(bytes: Array<Byte>): ?String {
    try {
        fromJsonBytes<Body>(bytes)
        None
    } catch (_: FjException) {
        None
    } catch (_: RpcException) {
        None
    } catch (e: Exception) {
        "${e}"
    }
}

/**
 * Whatever a client sends, reading it throws `FjException` or `RpcException`, which the read loop
 * answers: anything else ends the loop, and the connection with it.
 */
@Test
class BodyFuzzTest {
    let bytesTried: Array<Byte> = [0x00, 0x20, 0x22, 0x2C, 0x2D, 0x30, 0x3A, 0x5B, 0x5C, 0x5D, 0x6E, 0x7B, 0x7D, 0x80, 0xFF]

    func check(bytes: Array<Byte>, failures: ArrayList<String>): Unit {
        if (let Some(e) <- readOrAnswer(bytes)) {
            failures.add("${bytes}: ${e}")
        }
    }

    @TestCase
    func everyTruncationOrByteReplacedOrDroppedIsAnsweredAsAnError() {
        // arrange
        let failures = ArrayList<String>()

        for (bytes in FUZZ_MESSAGES) {
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

/**
 * One of the messages with a few edits: bytes dropped, inserted, replaced, a run of them repeated,
 * or the rest cut off, the draws mutated towards the comparisons the codec makes under `--fuzz` (D24).
 */
struct MutatedMessage <: ToString {
    MutatedMessage(let bytes: Array<Byte>) {}

    public func toString(): String {
        let text = StringBuilder()
        for (b in bytes) {
            if (b >= 0x20 && b < 0x7F && b != 0x5C) {
                text.append(Rune(b))
            } else {
                text.append("\\x${b.format("02x")}")
            }
        }
        text.toString()
    }
}

extend MutatedMessage <: Arbitrary<MutatedMessage> {
    public static func arbitrary(random: RandomSource): Generator<MutatedMessage> {
        Generators.generate {
            let bytes = ArrayList(FUZZ_MESSAGES[random.nextInt64(FUZZ_MESSAGES.size)])
            for (_ in 0..1 + random.nextInt64(4)) {
                let at = random.nextInt64(bytes.size + 1)
                match (random.nextInt64(5)) {
                    case 0 where at < bytes.size => bytes.remove(at: at)
                    case 1 => bytes.add(random.suggestUInt8(), at: at)
                    case 2 where at < bytes.size => bytes[at] = random.suggestUInt8()
                    case 3 where at < bytes.size =>
                        let run = bytes[at..min(bytes.size, at + 1 + random.nextInt64(8))].toArray()
                        bytes.add(all: run, at: at)
                    case 4 => bytes.remove(at..bytes.size)
                    case _ => ()
                }
            }
            MutatedMessage(bytes.toArray())
        }
    }
}

extend MutatedMessage <: Shrink<MutatedMessage> {
    public func shrink(): Iterable<MutatedMessage> {
        bytes.shrink() |> map {b: Array<Byte> => MutatedMessage(b)}
    }
}

@Test
@Configure[randomSeed: 42, coverageGuided: true, generationSteps: 10000]
class BodyCoverageGuidedFuzzTest {
    @TestCase[message in random()]
    func readsAMutatedMessageOrAnswersItAsAnError(message: MutatedMessage) {
        // act
        let thrown = readOrAnswer(message.bytes)

        // assert
        @Expect(thrown, None)
    }
}
