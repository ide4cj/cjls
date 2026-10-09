package project_model

import std.fs.*

/**
 * A Cangjie SDK found, and where from: `std` is in it, and `${CANGJIE_HOME}` expands to it.
 */
public struct CangjieHome {
    public CangjieHome(
        public let path: String,
        /**
         * What named it, for the log: `initializationOptions.cangjieHome`, `CANGJIE_HOME`, cjsdk's
         * default toolchain, or `cjc` on `PATH`.
         */
        public let source: String
    ) {}
}

/**
 * The SDK, the first of these that is a directory: `option` (`initializationOptions.cangjieHome`,
 * which the editor takes from a setting of its own); `CANGJIE_HOME`; cjsdk's default toolchain,
 * `~/.cjpm/toolchains/default`, a link cjsdk makes; and the directory two up from `cjc` on `PATH`,
 * links followed (`<home>/bin/cjc`), if `std`'s `modules` is in it: cjsdk links `~/.local/bin/cjc` to
 * itself, and `~/.local` is no SDK. `None` if none is: an editor launches the server with the
 * environment of the desktop, which `envsetup.sh` never touched.
 *
 * `env` gives the value of an environment variable.
 */
public func findCangjieHome(option: ?String, env!: (String) -> ?String): ?CangjieHome {
    let home = match (env("HOME")) {
        case Some(home) => home
        case None => env("USERPROFILE")
    }
    let candidates: Array<(?String, String)> = [
        (option, "initializationOptions.cangjieHome"),
        (env("CANGJIE_HOME"), "CANGJIE_HOME"),
        (home.map {it => Path(it).join(".cjpm").join("toolchains").join("default").toString()},
            "the default toolchain of cjsdk"),
        (cjcOnPath(env("PATH") ?? "").flatMap {cjc => cjc.parent.parent.toString()}.flatMap {
            home => if (isDirectory(Path(home).join("modules").toString())) {
                home
            } else {
                None
            }
        }, "cjc on PATH")
    ]
    for ((path, source) in candidates) {
        if (let Some(path) <- path) {
            if (isDirectory(path)) {
                return CangjieHome(path, source)
            }
        }
    }
    None
}

/**
 * `env` with `CANGJIE_HOME` the SDK found, `None` if none is: what `${CANGJIE_HOME}` expands to in a
 * path, and where `std` is taken from, whatever the environment says.
 */
public func withCangjieHome(env: (String) -> ?String, home: ?CangjieHome): (String) -> ?String {
    let path = home.map {it => it.path}
    {
        name: String => if (name == "CANGJIE_HOME") {
            path
        } else {
            env(name)
        }
    }
}

/**
 * The sources of the SDK's version found, and where from: a directory holding `std`'s, laid out as
 * `cangjie_runtime`'s `stdlib/libs` (`std/collection/array_list.cj`).
 */
public struct CangjieSrc {
    public CangjieSrc(
        public let path: String,
        /**
         * What named it, for the log: `initializationOptions.cangjieSrc`, `CANGJIE_SRC`, or the SDK.
         */
        public let source: String
    ) {}
}

/**
 * The sources of the SDK, the first of these that holds a directory `std`: `option`
 * (`initializationOptions.cangjieSrc`, from a setting of the editor's); `CANGJIE_SRC`; `src` in the SDK
 * (`env`'s `CANGJIE_HOME`), where they are put for the SDK they are of. `None` if none does: without
 * them nothing changes but that a declaration of `std` has nowhere to go (D65).
 *
 * `env` gives the value of an environment variable.
 */
public func findCangjieSrc(option: ?String, env!: (String) -> ?String): ?CangjieSrc {
    let candidates: Array<(?String, String)> = [
        (option, "initializationOptions.cangjieSrc"),
        (env("CANGJIE_SRC"), "CANGJIE_SRC"),
        (env("CANGJIE_HOME").map {home => Path(home).join("src").toString()}, "the SDK")
    ]
    for ((path, source) in candidates) {
        if (let Some(path) <- path) {
            if (isDirectory(Path(path).join("std").toString())) {
                return CangjieSrc(path, source)
            }
        }
    }
    None
}

/**
 * `env` with `CANGJIE_SRC` the sources found, `None` if none are: where `std`'s sources are taken
 * from, whatever the environment says.
 */
public func withCangjieSrc(env: (String) -> ?String, src: ?CangjieSrc): (String) -> ?String {
    let path = src.map {it => it.path}
    {
        name: String => if (name == "CANGJIE_SRC") {
            path
        } else {
            env(name)
        }
    }
}

/**
 * `cjc` in the first directory of `path` that has it, its links followed, `None` if none has.
 */
func cjcOnPath(path: String): ?Path {
    let separator = if (HOST_OS == "Windows") {
        ";"
    } else {
        ":"
    }
    let name = if (HOST_OS == "Windows") {
        "cjc.exe"
    } else {
        "cjc"
    }
    for (dir in path.split(separator) where !dir.isEmpty() && Path(dir).isAbsolute()) {
        let cjc = Path(dir).join(name)
        try {
            if (exists(cjc)) {
                return canonicalize(cjc)
            }
        } catch (_: FSException) {
            continue
        }
    }
    None
}

/**
 * Whether `path` is absolute and a directory, its links followed: a `FileInfo` is the link's own.
 */
func isDirectory(path: String): Bool {
    Path(path).isAbsolute() && (try {
        exists(path) && FileInfo(canonicalize(Path(path))).isDirectory()
    } catch (_: FSException) {
        false
    })
}
