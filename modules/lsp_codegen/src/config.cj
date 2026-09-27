package lsp_codegen

import std.collection.fold
import std.fs.*
import ftoml.*
import stdxx.deriving.*

struct Config {
    let outputDir: Path

    Config(
        let srcDir!: Path,
        let outputPackage!: String,
        let imports!: Collection<String> = [],
        let typeMap!: TypeMap = TypeMap()
    ) {
        // cjpm names a subpackage `<root>.<path under src-dir>`: the root is no directory
        outputDir = outputPackage.split(".")[1..] |> fold(srcDir) {dir: Path, part: String => dir.join(part)}
    }

    static func load(cfgPath: Path): Config {
        let cfgDir = parentDirOf(cfgPath)
        let cfgFile = fromTomlBytes<ConfigFile>(File.readFrom(cfgPath))
        let general = cfgFile.general
        let manifest = CjpmManifest.load(cfgDir)

        let subPackage = general.outputSubpackage.trimAscii()
        if (subPackage.isEmpty()) {
            throw ConfigException("`output-subpackage` must not be empty")
        }

        let srcDir = nonBlankPath(general.srcDir) ?? manifest.flatMap {it: CjpmManifest => nonBlankPath(it.`package`.srcDir)} ??
            Path("src")
        let rootPackage = manifest.map {it: CjpmManifest => it.`package`.name}.getOrThrow {
            => ConfigException("cannot tell the root package of `${subPackage}`")
        }

        Config(
            imports: general.imports ?? [],
            srcDir: srcDir.resolveAgainst(cfgDir),
            outputPackage: "${rootPackage}.${subPackage}",
            typeMap: cfgFile.types ?? TypeMap(),
        )
    }
}

/**
 * cjpm writes `""` for an unset `src-dir`, so a blank one falls through to the next source.
 */
private func nonBlankPath(raw: ?String): ?Path {
    let value = raw.map {it: String => it.trimAscii()} ?? ""
    if (value.isEmpty()) {
        None
    } else {
        Path(value)
    }
}

/**
 * The directory a config path lives in - `Path.parent` is empty for a bare filename, and every
 * `join`/`normalize` on an empty path throws.
 */
func parentDirOf(cfgPath: Path): Path {
    let parent = cfgPath.parent
    if (parent.isEmpty()) {
        Path("./")
    } else {
        parent
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

@DeriveExt[FromToml]
struct ConfigFile {
    ConfigFile(let general!: GeneralSection, let types!: ?TypeMap = None) {}
}

@DeriveExt[FromToml]
struct GeneralSection {
    GeneralSection(
        @Serde[rename: "src-dir"] let srcDir!: ?String = None,
        @Serde[rename: "output-subpackage"] let outputSubpackage!: String,
        let imports!: ?Array<String> = None
    ) {}
}

/** What the generator needs of the `cjpm.toml` beside its config; the rest is skipped. */
@DeriveExt[FromToml]
struct CjpmManifest {
    CjpmManifest(let `package`!: CjpmPackage) {}

    static func load(cfgDir: Path): ?CjpmManifest {
        let manifestPath = cfgDir.join("cjpm.toml")
        if (!exists(manifestPath)) {
            return None
        }

        fromTomlBytes<CjpmManifest>(File.readFrom(manifestPath))
    }
}

@DeriveExt[FromToml]
struct CjpmPackage {
    CjpmPackage(let name!: String, @Serde[rename: "src-dir"] let srcDir!: ?String = None) {}
}

extend Path {
    func resolveAgainst(base: Path): Path {
        if (isAbsolute()) {
            normalize()
        } else {
            base.join(this).normalize()
        }
    }
}
