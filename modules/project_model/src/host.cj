package project_model

import std.collection.*
import loupe.db.Cfg

/**
 * The platform the server runs on, as `@When` names it.
 */
@When[os == "Windows"]
const HOST_OS = "Windows"

@When[os == "macOS"]
const HOST_OS = "macOS"

@When[os == "Linux"]
const HOST_OS = "Linux"

@When[arch == "aarch64"]
const HOST_ARCH = "aarch64"

@When[arch == "x86_64"]
const HOST_ARCH = "x86_64"

/**
 * What `@When` is evaluated against when nothing says otherwise: the host's, with cjc's own backend.
 */
public func hostCfg(): Cfg {
    Cfg([("os", HOST_OS), ("arch", HOST_ARCH), ("backend", "cjnative")])
}

/**
 * The target `cfg` builds for as cjpm names it in `[target.<triple>]`, `None` for one it has no
 * name for.
 */
func cjpmTriple(cfg: Cfg): ?String {
    let arch = cfg.get("arch") ?? return None
    match (cfg.get("os")) {
        case Some("macOS") => "${arch}-apple-darwin"
        case Some("Linux") => "${arch}-unknown-linux-gnu"
        case Some("Windows") => "${arch}-w64-mingw32"
        case _ => None
    }
}

/**
 * The directory of the SDK's `modules` for the target `cfg` builds for, `darwin_aarch64_cjnative`,
 * `None` for one it has no name for.
 */
func sdkTarget(cfg: Cfg): ?String {
    let arch = cfg.get("arch") ?? return None
    let os = match (cfg.get("os")) {
        case Some("macOS") => "darwin"
        case Some("Linux") => "linux"
        case Some("Windows") => "windows"
        case _ => return None
    }
    "${os}_${arch}_${cfg.get("backend") ?? "cjnative"}"
}

/**
 * `text` with every `${VAR}` replaced by the variable's value, as cjpm does in its paths; a
 * variable `env` has no value for is left as it is, and told in `problems`.
 */
func expandVariables(text: String, env: (String) -> ?String, problems: ArrayList<String>): String {
    let out = StringBuilder()
    var rest = text
    while (let Some(start) <- rest.indexOf("\${")) {
        let end = rest.indexOf("}", start) ?? break
        let name = rest[start + 2..end]
        out.append(rest[..start])
        match (env(name)) {
            case Some(value) => out.append(value)
            case None =>
                problems.add("`${name}` is not set: `${text}` is taken as it is")
                out.append(rest[start..end + 1])
        }
        rest = rest[end + 1..]
    }
    out.append(rest)
    out.toString()
}
