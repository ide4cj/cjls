package project_model

import loupe.db.Cfg
import platform.{hostArch, hostEnv, hostOs}

/**
 * What `@When` is evaluated against when nothing says otherwise: the host's, with cjc's own backend,
 * and `test` set, for a package's tests are among its files (#149, as R1's `cfg.setTest`).
 */
public func hostCfg(): Cfg {
    Cfg(
        [
            ("os", hostOs()),
            ("arch", hostArch()),
            ("env", hostEnv()),
            ("backend", "cjnative"),
            ("test", "true")
        ]
    )
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
public func sdkTarget(cfg: Cfg): ?String {
    let arch = cfg.get("arch") ?? return None
    let os =
        match (cfg.get("os")) {
            case Some("macOS") => "darwin"
            case Some("Linux") => "linux"
            case Some("Windows") => "windows"
            case _ => return None
        }
    "${os}_${arch}_${cfg.get("backend") ?? "cjnative"}"
}
