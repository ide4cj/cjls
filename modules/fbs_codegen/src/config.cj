package fbs_codegen

import std.collection.*
import std.fs.*
import ftoml.*
import stdxx.deriving.*

/**
 * What to generate from a schema, and how. Paths are relative to the file.
 */
@DeriveExt[FromToml]
struct Config {
    Config(
        let schema!: String,
        let output!: String,
        @Serde[rename: "package"] let packageName!: String,
        // enums whose reader takes a value it does not know as `Unknown(value)`; the others throw on one
        @Serde[rename: "open"] let openEnums!: ?Array<String> = None,
        // Cangjie names for declarations (`Generic`) or enum members (`TypeKind.Generic`) of the schema
        @Serde[rename: "rename"] let renames!: ?HashMap<String, String> = None,
        // fields (`Decl.attributes`) read through a hand-written type, whose constructor takes the field's value
        @Serde[rename: "wrap"] let wraps!: ?HashMap<String, String> = None,
        // a `<Name>Data` to write for each declaration but an enum, besides the views
        let write!: ?Bool = None
    ) {}

    prop open: Array<String> {
        get() {
            openEnums ?? []
        }
    }

    prop rename: HashMap<String, String> {
        get() {
            renames ?? HashMap<String, String>()
        }
    }

    prop wrap: HashMap<String, String> {
        get() {
            wraps ?? HashMap<String, String>()
        }
    }

    prop writes: Bool {
        get() {
            write ?? false
        }
    }
}

class ConfigException <: Exception {
    ConfigException(message: String) {
        super(message)
    }

    protected override func getClassName(): String {
        "ConfigException"
    }
}

/**
 * The config at `path` and the schema it names, read.
 */
struct Inputs {
    Inputs(let dir!: Path, let config!: Config, let schema!: Schema) {}

    static func load(path: Path): Inputs {
        let config = fromTomlBytes<Config>(File.readFrom(path))
        let dir = if (path.parent.isEmpty()) {
            Path(".")
        } else {
            path.parent
        }
        let schema = parseSchema(String.fromUtf8(File.readFrom(dir.join(config.schema))))
        Inputs(dir: dir, config: config, schema: schema)
    }
}
