package macro_server

import std.io.*
import fbs.{readUInt64, writeUInt64}

/**
 * Writes `message` as `LSPMacroServer` reads one: its length as a native `size_t` (8 bytes, little-endian on
 * every target cjls is built for), then its bytes.
 */
func writeMessage(output: OutputStream, message: Array<Byte>): Unit {
    let length = Array<Byte>(8, repeat: 0)
    writeUInt64(length, 0, UInt64(message.size))
    output.write(length)
    output.write(message)
    output.flush()
}

/** The largest message read: what a macro makes of one declaration is far below it. */
const MAX_MESSAGE = 1 << 30

/**
 * The next message `input` holds, as `writeMessage` writes one; `None` if it ends before one starts.
 *
 * @throws MacroServerException - if it ends inside one, or one claims no bytes
 */
func readMessage(input: InputStream): ?Array<Byte> {
    let length = Array<Byte>(8, repeat: 0)
    if (!readFully(input, length)) {
        return None
    }
    let size = readUInt64(length, 0)
    if (size == 0 || size > UInt64(MAX_MESSAGE)) {
        throw MacroServerException("a message of ${size} bytes")
    }
    let message = Array<Byte>(Int64(size), repeat: 0)
    if (!readFully(input, message)) {
        throw MacroServerException("the server's output ends inside a message")
    }
    message
}

/**
 * Fills `buf` from `input`: false if it ends before a byte was read.
 *
 * @throws MacroServerException - if it ends after some
 */
func readFully(input: InputStream, buf: Array<Byte>): Bool {
    var at = 0
    while (at < buf.size) {
        let n = input.read(buf[at..])
        if (n <= 0) {
            if (at == 0) {
                return false
            }
            throw MacroServerException("the server's output ends inside a message")
        }
        at += n
    }
    true
}
