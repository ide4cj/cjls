package project_model

import std.collection.*
import std.sort.*
import ftoml.*
import stdxx.deriving.*
import loupe.db.Cfg

/**
 * `[[source-set]]` of a multiplatform module (CJMP, `[profile] experimental = true`): a directory
 * of the module's packages, for the targets whose features include `features` (#318).
 */
@DeriveExt[FromToml]
struct SourceSet {
    SourceSet(
        let name!: ?String = None,
        @Serde[rename: "src-dir"]
        let srcDir!: String,
        // not `features`: cjc 1.3.0-alpha.20261002 drops a field of that name from `@DeriveExt`'s input (a CJMP keyword)
        @Serde[rename: "features"]
        let featureNames!: ?Array<String> = None
    ) {}

    /**
     * Its name, or its directory for one of none.
     */
    prop label: String {
        get() {
            name ?? srcDir
        }
    }
}

/**
 * `[[feature]]`: a feature declared, `name`, and those it enables, `mapping` (`os.linux` mapping
 * `user.plat.posix`). Its `names` declares several features at once and maps none of them:
 * cjpm 1.3.0-alpha.20261002 ignores the `mapping` beside it, and so do we.
 */
@DeriveExt[FromToml]
struct Feature {
    Feature(let name!: ?String = None, let mapping!: ?Array<String> = None) {}
}

/**
 * The source sets a build takes, in the order of their chain, the common one first and the
 * product last, and those it leaves out, each with why; and what cjpm rejects.
 */
struct SourceSetChain {
    SourceSetChain(
        let chain: Array<SourceSet>,
        let left: Array<(SourceSet, String)>,
        let problems: Array<String>
    ) {}
}

/**
 * The feature of the target `cfg` builds for that cjpm deduces: `os.linux`, `os.darwin` or
 * `os.windows`, `None` for another.
 */
func hostFeature(cfg: Cfg): ?String {
    match (cfg.get("os")) {
        case Some("Linux") => "os.linux"
        case Some("macOS") => "os.darwin"
        case Some("Windows") => "os.windows"
        case _ => None
    }
}

/**
 * The features the target `cfg` builds for enables: its own (`hostFeature`) and the module's
 * `always` (`[package] always-enabled-features`), and those `features` maps each enabled one to,
 * in turn; in the order of their names.
 */
func enabledFeatures(
    features: Array<Feature>,
    cfg: Cfg,
    always!: Array<String> = []
): Array<String> {
    let enabled = HashSet<String>(always)
    if (let Some(host) <- hostFeature(cfg)) {
        enabled.add(host)
    }
    var grown = true
    while (grown) {
        grown = false
        for (
            feature in features where feature.name.map { name => enabled.contains(name) } ?? false
        ) {
            for (mapped in feature.mapping ?? [] where enabled.add(mapped)) {
                grown = true
            }
        }
    }
    let sorted = enabled.toArray()
    sort(sorted)
    sorted
}

/**
 * The chain of `sets` a build for `cfg` takes, as cjpm picks it: those whose features the target
 * and `always` enable (`enabledFeatures`), from the fewest features to the most, each of a set's features
 * those of the one before it and more. A set the target enables that is not on the chain is left
 * out, and told: cjpm rejects a build of it.
 */
func sourceSetChain(
    sets: Array<SourceSet>,
    features: Array<Feature>,
    cfg: Cfg,
    always!: Array<String> = []
): SourceSetChain {
    let enabled = enabledFeatures(features, cfg, always: always)
    let taken = ArrayList<SourceSet>()
    let left = ArrayList<(SourceSet, String)>()
    for (set in sets) {
        let missing = (set.featureNames ?? []).filter { feature => !enabled.contains(feature) }
        if (missing.isEmpty()) {
            taken.add(set)
        } else {
            let target =
                if (enabled.isEmpty()) {
                    "none"
                } else {
                    String.join(enabled, delimiter: ", ")
                }
            left
                .add(
                    (
                        set,
                        "source set `${set.label}` needs ${String.join(missing, delimiter: ", ")}, which the target does not enable (it enables ${target})"
                    )
                )
        }
    }
    let ordered = taken.toArray()
    sort(
        ordered,
        stable: true,
        by: {
            a: SourceSet, b: SourceSet =>
            (a.featureNames ?? []).size.compare((b.featureNames ?? []).size)
        }
    )
    let chain = ArrayList<SourceSet>()
    let problems = ArrayList<String>()
    for (set in ordered) {
        let own = set.featureNames ?? []
        let extends =
            if (chain.isEmpty()) {
                true
            } else {
                let parent = chain[chain.size - 1].featureNames ?? []
                own.size > parent.size && parent.iterator().all { feature => own.contains(feature) }
            }
        if (extends) {
            chain.add(set)
        } else {
            let names =
                String.join(chain.toArray().map { one => "`${one.label}`" }, delimiter: ", ")
            left
                .add(
                    (
                        set,
                        "source set `${set.label}` is not on the chain of ${names} the target takes"
                    )
                )
            problems
                .add(
                    "source set `${set.label}` is left out: cjpm cannot compile multiple source sets without common parent source set"
                )
        }
    }
    SourceSetChain(chain.toArray(), left.toArray(), problems.toArray())
}
