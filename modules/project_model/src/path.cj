package project_model

import std.collection.ArrayList
import std.fs.Path

/**
 * Expands a leading `~` (HOME, else USERPROFILE), `${VAR}` and `$VAR` once using `env`.
 * Missing values remain literal and are reported in `problems`. Other shell syntax is literal.
 * This accepts filesystem paths, not URIs; relative paths stay relative.
 */
public func expandPath(
    text: String,
    env: (String) -> ?String,
    problems: ArrayList<String>
): String {
    let expanded = expandVariables(text, env, problems)
    // Only a tilde written by the user denotes home: variable values are never expanded again.
    if (text == "~" || text.startsWith("~/") || text.startsWith("~\\")) {
        let home =
            match (env("HOME")) {
                case Some(value) => Some(value)
                case None => env("USERPROFILE")
            }
        if (let Some(home) <- home) {
            if (home.isEmpty()) {
                problems.add("home is empty: `${text}` cannot expand `~`")
                return expanded
            }
            return if (text == "~") {
                home
            } else {
                Path(home).join(expanded[2..]).toString()
            }
        }
        problems.add("HOME and USERPROFILE are not set: `${text}` cannot expand `~`")
    }
    expanded
}

/**
 * Inserts environment values once; unresolved names stay literal and are reported.
 */
func expandVariables(text: String, env: (String) -> ?String, problems: ArrayList<String>): String {
    let out = StringBuilder()
    let bytes = text.toArray()
    var offset = 0
    var literalStart = 0
    while (offset < bytes.size) {
        let start = offset
        if (bytes[offset] != b'$' || offset + 1 == bytes.size) {
            offset++
            continue
        }
        offset++
        let braced = bytes[offset] == b'{'
        let nameStart =
            if (braced) {
                offset + 1
            } else {
                offset
            }
        var end = nameStart
        if (braced) {
            while (end < bytes.size && bytes[end] != b'}') {
                end++
            }
            if (end == bytes.size) {
                break
            }
        } else {
            if (!variableStart(bytes[end])) {
                continue
            }
            while (
                end < bytes.size &&
                    (variableStart(bytes[end]) || (bytes[end] >= b'0' && bytes[end] <= b'9'))
            ) {
                end++
            }
        }
        let name = text[nameStart..end]
        offset =
            if (braced) {
                end + 1
            } else {
                end
            }
        out.append(text[literalStart..start])
        match (env(name)) {
            case Some(value) => out.append(value)
            case None =>
                problems.add("`${name}` is not set: `${text}` keeps its reference")
                out.append(text[start..offset])
        }
        literalStart = offset
    }
    out.append(text[literalStart..])
    out.toString()
}

func variableStart(byte: UInt8): Bool {
    byte == b'_' || (byte >= b'A' && byte <= b'Z') || (byte >= b'a' && byte <= b'z')
}
