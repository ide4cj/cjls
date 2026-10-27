package cjformat.config

import std.env.getWorkingDirectory
import std.fs.{File, Path, exists}
import cjformat.{FormatOptions, SimpleIf}
import ftoml.parseToml

/**
 * Reads the nearest `cjformat.toml`, starting at a source file's parent and walking to the
 * filesystem root. A nearer file replaces the parent policy; missing keys use library defaults.
 * `path` need not exist (generators use their output path); relative paths use the working directory.
 * Throws on unreadable files, invalid TOML, unknown keys or invalid values.
 */
public func optionsFor(path: Path): FormatOptions {
    let absolute =
        if (path.isAbsolute()) {
            path
        } else {
            getWorkingDirectory().join(path)
        }
    var dir = absolute.normalize().parent
    while (true) {
        let config = dir.join("cjformat.toml")
        if (exists(config)) {
            try {
                return parseOptions(String.fromUtf8(File.readFrom(config)))
            } catch (e: Exception) {
                throw IllegalArgumentException("${config}: ${e.message}")
            }
        }
        let parent = dir.parent
        if (parent == dir || parent.isEmpty()) {
            break
        }
        dir = parent
    }
    FormatOptions()
}

/** Parses the three supported project settings, rejecting unknown keys and invalid values. */
public func parseOptions(text: String): FormatOptions {
    var lineWidth = 100
    var indentWidth = 4
    var simpleIf = SimpleIf.Multiline
    for ((key, value) in parseToml(text).table) {
        match (key) {
            case "line_width" => lineWidth = value.asInteger()
            case "indent_width" => indentWidth = value.asInteger()
            case "simple_if" =>
                simpleIf =
                    match (value.asString()) {
                        case "compact" => SimpleIf.Compact
                        case "multiline" => SimpleIf.Multiline
                        case _ => throw value.error("simple_if must be compact or multiline")
                    }
            case _ => throw value.error("unknown formatter setting: ${key}")
        }
    }
    FormatOptions(lineWidth: lineWidth, indentWidth: indentWidth, simpleIf: simpleIf)
}
