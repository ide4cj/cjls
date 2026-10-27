package cjformat.config

import std.env.getWorkingDirectory
import std.fs.{FSException, File, Path, exists}
import cjformat.FormatOptions
import ftoml.{FtException, fromTomlString}

/**
 * Reads the nearest `cjformat.toml`, starting at a source file's parent and walking to the
 * filesystem root. A nearer file replaces the parent policy; missing keys use library defaults.
 * `path` need not exist (generators use their output path); relative paths use the working directory.
 * @throws FormatConfigException - if a config cannot be read or contains invalid settings.
 */
public func optionsFor(path: Path): FormatOptions {
    let absolute = if (path.isAbsolute()) { path } else { getWorkingDirectory().join(path) }
    var dir = absolute.normalize().parent
    while (true) {
        let config = dir.join("cjformat.toml")
        if (exists(config)) {
            try {
                return parseOptions(String.fromUtf8(File.readFrom(config)))
            } catch (e: FSException | FtException | IllegalArgumentException) {
                throw FormatConfigException("${config}: ${e.message}")
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

/**
 * Reads the three supported settings through their wire model and validates widths.
 *
 * @throws FtException - if TOML, keys, types or enum values are invalid
 * @throws IllegalArgumentException - if a width is not positive
 */
func parseOptions(text: String): FormatOptions {
    fromTomlString<FormatOptions>(text)
}
