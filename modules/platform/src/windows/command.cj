features {os.windows}
package platform

import std.collection.*
import std.sort.sort

// What `CreateProcessW` is given to start a child, built as text: the command line, the environment block, both
// UTF-16.

/**
 * `s` in UTF-16, as Windows takes text.
 */
func utf16(s: String): Array<UInt16> {
    let units = ArrayList<UInt16>()
    for (r in s.runes()) {
        let c = UInt32(r)
        if (c < 0x10000) {
            units.add(UInt16(c))
        } else {
            let v = c - 0x10000
            units.add(UInt16(0xD800 + (v >> 10)))
            units.add(UInt16(0xDC00 + (v & 0x3FF)))
        }
    }
    units.toArray()
}

/**
 * `arg` as `CommandLineToArgvW` (and the C runtime's `main`) reads it back: in quotes if it has a space, a tab
 * or a quote, a quote escaped, the backslashes before a quote or the closing one doubled.
 */
func quoteWindowsArg(arg: String): String {
    if (!arg.isEmpty() && !arg.contains(" ") && !arg.contains("\t") && !arg.contains("\"")) {
        return arg
    }
    let sb = StringBuilder("\"")
    var backslashes = 0
    for (r in arg.runes()) {
        if (r == r'\\') {
            backslashes++
            continue
        }
        if (r == r'"') {
            sb.append("\\" * (2 * backslashes + 1))
        } else {
            sb.append("\\" * backslashes)
        }
        backslashes = 0
        sb.append(r)
    }
    sb.append("\\" * (2 * backslashes))
    sb.append("\"")
    sb.toString()
}

/**
 * The command line of `args`, the program first, each quoted as `CommandLineToArgvW` reads it back.
 */
func windowsCommandLine(args: Array<String>): String {
    String.join(args.map { a => quoteWindowsArg(a) }, delimiter: " ")
}

/**
 * The environment block of a child: `variables` with `libDir` first on `PATH` (whatever its case), where
 * Windows looks for the DLLs it loads; sorted by name ignoring case, as Windows keeps one; each `name=value`
 * ended by a 0, the block by another.
 */
func windowsEnvironment(variables: Array<(String, String)>, libDir: String): Array<UInt16> {
    let entries = ArrayList<(String, String)>()
    var path: ?String = None
    for ((name, value) in variables) {
        if (name.toAsciiUpper() == "PATH") {
            path = value
        } else if (!name.isEmpty()) {
            entries.add((name, value))
        }
    }
    entries
        .add(
            (
                "PATH",
                match (path) {
                    case Some(p) where !p.isEmpty() => "${libDir};${p}"
                    case _ => libDir
                }
            )
        )
    sort(entries, by: { a, b => a[0].toAsciiUpper().compare(b[0].toAsciiUpper()) }, stable: true)
    let block = ArrayList<UInt16>()
    for ((name, value) in entries) {
        block.add(all: utf16("${name}=${value}"))
        block.add(0)
    }
    block.add(0)
    block.toArray()
}
