package project_model

import std.collection.*
import fjson.*
import stdxx.deriving.*

/**
 * The name of the file a project is written to: after the language rather than the server, so
 * another server can read it too.
 */
public const PROJECT_JSON = "cj-project.json"

/**
 * `cj-project.json` as the file has it: paths relative to the file, `${VAR}` not expanded,
 * defaults not applied. `lowerProjectJson` makes a project of it, `toProjectJson` writes one.
 */
@DeriveExt[ToJson, FromJson]
@Serde[skipNone]
public struct ProjectJson {
    public ProjectJson(
        /**
         * What `@When` is evaluated against, over the host's.
         */
        public let cfg!: ?HashMap<String, String> = None,
        public let modules!: ?Array<ModuleJson> = None,
        /**
         * Besides `std`, which is there unless a module is named so.
         */
        public let binaries!: ?Array<BinaryJson> = None
    ) {}
}

@DeriveExt[ToJson, FromJson]
@Serde[skipNone]
public struct ModuleJson {
    public ModuleJson(
        /**
         * The name of its root package.
         */
        public let name!: String,
        /**
         * The directory of its root package.
         */
        public let root!: String,
        /**
         * Every package of the module; without them, one per directory under `root` holding a
         * `*.cj`, named `<name>.<path>`, as cjpm names them.
         */
        public let packages!: ?Array<PackageJson> = None,
        /**
         * The modules of the project and the binaries it may import, by name.
         */
        public let deps!: ?Array<String> = None,
        /**
         * `false` for a dependency: analyzed, but reporting nothing.
         */
        public let member!: ?Bool = None,
        /**
         * Over the project's.
         */
        public let cfg!: ?HashMap<String, String> = None
    ) {}
}

@DeriveExt[ToJson, FromJson]
@Serde[skipNone]
public struct PackageJson {
    public PackageJson(
        public let name!: String,
        /**
         * Relative to the file; the directory its name gives under the module's root without it.
         */
        public let dir!: ?String = None,
        /**
         * Relative to `dir`; every `*.cj` in it without them.
         */
        public let files!: ?Array<String> = None,
        public let noPrelude!: ?Bool = None,
        /**
         * Whether it is a `macro package`; read from its files without it.
         */
        public let `macro`!: ?Bool = None
    ) {}
}

/**
 * As cjpm's `bin-dependencies`: `paths` as `path-option`, `packages` as `package-option`.
 */
@DeriveExt[ToJson, FromJson]
@Serde[skipNone]
public struct BinaryJson {
    public BinaryJson(
        public let name!: String,
        public let paths!: ?Array<String> = None,
        public let packages!: ?HashMap<String, String> = None
    ) {}
}

/**
 * `json` as `cj-project.json` holds it, indented by two spaces, a key per line, ending in a line
 * break.
 */
public func prettyProjectJson(json: ProjectJson): String {
    let builder = StringBuilder()
    pretty(fromJsonBytes<JsonValue>(toJsonBytes(json)), 0, builder)
    builder.append("\n")
    builder.toString()
}

private func pretty(value: JsonValue, depth: Int64, out: StringBuilder): Unit {
    let inner = "  " * (depth + 1)
    match (value) {
        case JsonArray(items) where !items.isEmpty() =>
            out.append("[\n")
            for (i in 0..items.size) {
                out.append(inner)
                pretty(items[i], depth + 1, out)
                out.append(if (i + 1 < items.size) { ",\n" } else { "\n" })
            }
            out.append("  " * depth + "]")
        case JsonObject(members) where !members.isEmpty() =>
            out.append("{\n")
            for (i in 0..members.size) {
                out.append(inner)
                out.append(JsonValue.JsonString(members[i][0]).toString())
                out.append(": ")
                pretty(members[i][1], depth + 1, out)
                out.append(if (i + 1 < members.size) { ",\n" } else { "\n" })
            }
            out.append("  " * depth + "}")
        case _ => out.append(value.toString())
    }
}
