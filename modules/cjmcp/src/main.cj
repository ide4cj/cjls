package cjmcp

import std.collection.ArrayList
import std.env.{getStdErr, getStdOut, getWorkingDirectory}
import std.fs.Path
import loupe.vfs.VfsPath
import platform.{StdinStream, useBinaryStdio}

main(args: Array<String>): Int64 {
    if (args == ["--help"]) {
        getStdOut()
            .write(
                "Usage: cjmcp [--dir <workspace>]\nMCP 2025-11-25 over newline-delimited stdio; runPython over native loupe objects (Linux); no SDK macro expansion.\n"
            )
        return 0
    }
    if (!(args.isEmpty() || (args.size == 2 && args[0] == "--dir"))) {
        getStdErr().write("Usage: cjmcp [--dir <workspace>]\n")
        return 2
    }
    try {
        let written = if (args.isEmpty()) { getWorkingDirectory().toString() } else { args[1] }
        let absolute =
            if (Path(written).isAbsolute()) {
                written
            } else {
                getWorkingDirectory().join(written).toString()
            }
        let server = McpServer(VfsPath.file(absolute))
        serveStdio(server)
        0
    } catch (e: Exception) {
        getStdErr().write("cjmcp: ${e.message}\n")
        1
    } catch (e: Error) {
        getStdErr().write("cjmcp: ${e}\n")
        1
    }
}

/**
 * Read newline-delimited requests and write responses after Python output capture is restored.
 * @throws IllegalArgumentException - if a message exceeds 8 MiB or EOF truncates a message
 */
func serveStdio(server: McpServer): Unit {
    useBinaryStdio()
    let input = StdinStream()
    let output = getStdOut()
    let buffer = Array<Byte>(8192, repeat: 0)
    let line = ArrayList<Byte>()
    while (true) {
        let count = input.read(buffer)
        if (count == 0) {
            break
        }
        for (byte in buffer[..count]) {
            if (byte == 10) {
                if (let Some(response) <- server.handle(line.toArray())) {
                    output.write("${response}\n")
                    output.flush()
                }
                line.clear()
            } else {
                line.add(byte)
                if (line.size > 8 * 1024 * 1024) {
                    throw IllegalArgumentException("MCP message exceeds 8 MiB")
                }
            }
        }
    }
    if (!line.isEmpty()) {
        throw IllegalArgumentException("unterminated MCP message at EOF")
    }
}
