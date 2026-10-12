package cjls.server

import std.collection.ArrayList
import std.deriving.Derive
import std.fs.Path
import fjson.JsonValue
import loupe.vfs.VfsPath

/**
 * The section of the client's configuration the settings are under (`cjls.linkedProjects`), the one
 * `workspace/configuration` asks for and `didChangeConfiguration` is read in (D79).
 */
public const SETTINGS_SECTION = "cjls"

let LINKED_PROJECTS = Setting<Array<VfsPath>>("linkedProjects",
    "Projects to load, as rust-analyzer's: each an absolute path or a `file:` URI of a `cj-project.json`, or of a directory to find a project in. Under a root without a `cj-project.json`, they replace finding one there; outside every root, they are loaded besides.",
    JsonValue.JsonObject([("type", JsonValue.JsonString("array")),
        ("items", JsonValue.JsonObject([("type", JsonValue.JsonString("string"))])),
        ("default", JsonValue.JsonArray([]))]),
    [], readPaths)

let CANGJIE_HOME = Setting<?String>("cangjieHome",
    "The Cangjie SDK, an absolute path or a `file:` URI: looked for first, before `CANGJIE_HOME`, cjsdk's default toolchain and `cjc` on `PATH`. `std` is taken from it, and `\${CANGJIE_HOME}` in a project's paths expands to it.",
    optionalPathSchema(), Option<String>.None, readOptionalPath)

let CANGJIE_SRC = Setting<?String>("cangjieSrc",
    "The sources of the SDK's version, a directory holding `std/` as `cangjie_runtime`'s `stdlib/libs` does, an absolute path or a `file:` URI: looked for first, before `CANGJIE_SRC` and the SDK's `src`. Go to definition on a declaration of `std` goes there; `cjls fetch-src` puts them in the SDK's `src`.",
    optionalPathSchema(), Option<String>.None, readOptionalPath)

/**
 * What the user sets for the server: what `initializationOptions` holds at first, then the client's
 * section `cjls` each time the server is told it changed (D79). Every setting is optional.
 */
@Derive[Equatable]
public struct Settings {
    public Settings(
        /**
         * The projects to load besides, or instead of, those found under the roots (D33).
         */
        public let linkedProjects!: Array<VfsPath> = LINKED_PROJECTS.default,
        /**
         * The SDK, the first place it is looked for (D40).
         */
        public let cangjieHome!: ?String = CANGJIE_HOME.default,
        /**
         * The sources of the SDK, the first place they are looked for (D65).
         */
        public let cangjieSrc!: ?String = CANGJIE_SRC.default
    ) {}

    /**
     * The settings `json` holds, an object with a member per setting: one absent or `null` is at its
     * default, as is one whose value is not what its schema says, which `problems` is told of; an
     * item of a list that is not is left out, and told of.
     */
    public static func read(json: JsonValue, problems: ArrayList<String>): Settings {
        Settings(
            linkedProjects: LINKED_PROJECTS.read(json, problems),
            cangjieHome: CANGJIE_HOME.read(json, problems),
            cangjieSrc: CANGJIE_SRC.read(json, problems)
        )
    }
}

/**
 * The JSON Schema of the settings (draft-07, which VS Code reads), as `cjls --config-schema`
 * prints it for the editors' clients to generate theirs from (D32): an object with a property per
 * setting, its type, default and description.
 */
public func settingsSchema(): JsonValue {
    let properties = [LINKED_PROJECTS.property(), CANGJIE_HOME.property(), CANGJIE_SRC.property()]
    JsonValue.JsonObject([
        ("$schema", JsonValue.JsonString("http://json-schema.org/draft-07/schema#")),
        ("title", JsonValue.JsonString("cjls")),
        ("description", JsonValue.JsonString(
            "The settings of cjls, the Cangjie language server: its `initializationOptions`, and the section `cjls` of the client's configuration.")),
        ("type", JsonValue.JsonString("object")),
        ("properties", JsonValue.JsonObject(properties))
    ])
}

/**
 * A setting: its key, what it means, its schema but for the description, its default, and how its
 * value is read, `None` for one that is not what the schema says.
 */
class Setting<T> {
    Setting(
        let key: String,
        let description: String,
        let schema: JsonValue,
        let default: T,
        let parse: (String, JsonValue, ArrayList<String>) -> ?T
    ) {}

    func read(json: JsonValue, problems: ArrayList<String>): T {
        match (json.get(key)) {
            case None | Some(JsonValue.JsonNull) => default
            case Some(value) => match (parse(key, value, problems)) {
                case Some(parsed) => parsed
                case None =>
                    problems.add("`${key}` is not ${typeOf()}: ${value}")
                    default
            }
        }
    }

    /**
     * The property of the schema this setting is.
     */
    func property(): (String, JsonValue) {
        (key, JsonValue.JsonObject(schema.asObject().concat([("description", JsonValue.JsonString(description))])))
    }

    private func typeOf(): String {
        match (schema.get("type")) {
            case Some(JsonValue.JsonString("array")) => "a list of absolute paths or `file:` URIs"
            case _ => "an absolute path or a `file:` URI"
        }
    }
}

func optionalPathSchema(): JsonValue {
    JsonValue.JsonObject([("type", JsonValue.JsonArray([JsonValue.JsonString("string"), JsonValue.JsonString("null")])),
        ("default", JsonValue.JsonNull)])
}

/**
 * The path `value` names, an absolute path or a `file:` URI; `None` for anything else.
 */
func readPath(_: String, value: JsonValue, _: ArrayList<String>): ?String {
    match (value) {
        case JsonValue.JsonString(text) where text.startsWith("file:") =>
            VfsPath.fromUri(text).filePath.map {path => path.toString()}
        // `Path("")` throws
        case JsonValue.JsonString(text) where !text.isEmpty() && Path(text).isAbsolute() => text
        case _ => None
    }
}

/**
 * The path `value` names, as `readPath` reads it, for a setting that may be none.
 */
func readOptionalPath(key: String, value: JsonValue, problems: ArrayList<String>): ??String {
    readPath(key, value, problems).map {path => Some(path)}
}

/**
 * The paths a list names, each an absolute path or a `file:` URI; an item that is neither is left
 * out, and `problems` told of it. `None` for anything but a list.
 */
func readPaths(key: String, value: JsonValue, problems: ArrayList<String>): ?Array<VfsPath> {
    let items = match (value) {
        case JsonValue.JsonArray(items) => items
        case _ => return None
    }
    let paths = ArrayList<VfsPath>()
    for (item in items) {
        match (readPath(key, item, problems)) {
            case Some(path) => paths.add(VfsPath.file(path))
            case None => problems.add("an item of `${key}` is not an absolute path or a `file:` URI: ${item}")
        }
    }
    paths.toArray()
}
