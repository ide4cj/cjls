package project_model

import std.collection.*
import std.convert.*
import std.fs.*
import std.regex.*
import ftoml.*
import loupe.vfs.VfsPath

/**
 * The entry project's lock owns both ordinary and build-script transitive selections.
 */
class CjpmResolution {
    private var initialized = false
    private var lock: ?CjpmLock = None
    private var cache: ?VfsPath = None
    private var failure: ?String = None

    CjpmResolution(private let loading: Loading, private let root: VfsPath) {}

    func entry(name: String, script!: Bool): (DependencyTable, Int64, VfsPath) {
        if (!initialized) {
            initialized = true
            let file = root.join("cjpm.lock")
            try {
                let parsed = fromTomlBytes<CjpmLock>(File.readFrom(file.filePath.getOrThrow()))
                if (parsed.version != 0 && parsed.version != 1) {
                    throw ProjectException("unsupported lock version ${parsed.version}")
                }
                lock = parsed
                cache = repositoryCache(loading, root)
            } catch (e: Exception) {
                failure = "cannot read resolution for ${file}: ${e.message}"
            }
        }
        if (let Some(message) <- failure) {
            throw ProjectException(message)
        }
        let lock = this.lock.getOrThrow()
        let entries = if (script) { lock.scripts } else { lock.requires }
        let entry =
            entries.flatMap { all => all.get(name) } ?? throw ProjectException("no locked entry")
        (entry, lock.version, cache ?? throw ProjectException("no repository cache location"))
    }
}

class CjpmRegistry {
    private let resolution: CjpmResolution

    CjpmRegistry(private let loading: Loading, private let root: VfsPath) {
        resolution = CjpmResolution(loading, root)
    }

    func resolve(name: String, declared: Dependency, script!: Bool): ?VfsPath {
        try {
            let requirement =
                match (declared) {
                    case Version(text) => text
                    case Table(table) =>
                        table.version ?? throw ProjectException("declaration has no version")
                }
            let (entry, format, cache) = resolution.entry(name, script: script)
            if (entry.git.isSome() || entry.path.isSome()) {
                throw ProjectException("locked entry is not a registry dependency")
            }
            if (format == 1) {
                let source = entry.source ?? ""
                if (!source.startsWith("registry+") || source.size == 9) {
                    throw ProjectException("invalid registry lock source")
                }
                let checksum =
                    entry.checksum ?? throw ProjectException("locked entry has no checksum")
                if (!checksum.isEmpty() && !Regex("^sha256:[0-9a-f]{64}$").matches(checksum)) {
                    throw ProjectException("invalid registry lock checksum")
                }
            }
            let version = entry.version ?? throw ProjectException("locked entry has no version")
            if (!registryVersionMatches(requirement, version)) {
                throw ProjectException(
                    "locked version ${version} does not satisfy `${requirement}`"
                )
            }
            if (!Regex("^(_*[a-zA-Z][_a-zA-Z0-9]*::)?_*[a-zA-Z][_a-zA-Z0-9]*$").matches(name)) {
                throw ProjectException("invalid dependency name `${name}`")
            }
            let parts = name.split("::")
            let org = if (parts.size == 2) { parts[0] } else { "default" }
            let module = parts[parts.size - 1]
            let dir = cache.join("repository/source").join(org).join("${module}-${version}")
            if (!isFile(dir.join("cjpm.toml").filePath.getOrThrow())) {
                throw ProjectException("downloaded sources ${dir} are missing")
            }
            let pkg =
                readManifest(dir.join("cjpm.toml")).pkg ??
                    throw ProjectException("cached manifest has no [package]")
            if (packageName(pkg) != name || pkg.version != Some(version)) {
                throw ProjectException(
                    "cached manifest does not declare `${name}` version ${version}"
                )
            }
            dir
        } catch (e: Exception) {
            let kind = if (script) { "script dependency" } else { "dependency" }
            loading
                .problems
                .add(
                    "Registry ${kind} `${name}` is left out: ${e.message}; run `cjpm update` in ${root}"
                )
            None
        }
    }
}

/**
 * Whether the selected version satisfies cjpm's exact versions or union of intervals.
 *
 * @throws ProjectException - if the requirement or selected version is malformed
 * @throws IllegalArgumentException - if a numeric component exceeds Int64
 */
func registryVersionMatches(requirement: String, selected: String): Bool {
    let version = registryVersion(selected)
    let pieces = requirement.split(",")
    var i = 0
    var matched = false
    var hasRange = false
    while (i < pieces.size) {
        let first = pieces[i].trimAscii()
        if (first.startsWith("[") || first.startsWith("(")) {
            if (i + 1 == pieces.size) {
                throw ProjectException("invalid registry version requirement `${requirement}`")
            }
            let last = pieces[i + 1].trimAscii()
            if (!last.endsWith("]") && !last.endsWith(")")) {
                throw ProjectException("invalid registry version requirement `${requirement}`")
            }
            let low = first[1..].trimAscii()
            let high = last[..last.size - 1].trimAscii()
            if ((low.isEmpty() && first != "(") || (high.isEmpty() && last != ")")) {
                throw ProjectException("unbounded registry interval must be open")
            }
            let lower =
                if (low.isEmpty()) {
                    (0, 0, 0)
                } else {
                    let bound = registryVersion(low)
                    if (first.startsWith("(")) {
                        adjacentRegistryVersion(bound, up: true)
                    } else {
                        bound
                    }
                }
            let upper =
                if (high.isEmpty()) {
                    (Int64.Max, Int64.Max, Int64.Max)
                } else {
                    let bound = registryVersion(high)
                    if (last.endsWith(")")) {
                        adjacentRegistryVersion(bound, up: false)
                    } else {
                        bound
                    }
                }
            if (compareRegistryVersions(lower, upper) != Ordering.GT) {
                hasRange = true
                matched ||= compareRegistryVersions(version, lower) != Ordering.LT &&
                        compareRegistryVersions(version, upper) != Ordering.GT
            }
            i += 2
        } else {
            let exact = registryVersion(first)
            hasRange = true
            matched ||= version == exact
            i++
        }
    }
    if (!hasRange) {
        throw ProjectException("registry version requirement has no valid interval")
    }
    matched
}

/**
 * A validated cjpm version as integer components.
 *
 * @throws ProjectException - if the version is not a numeric triplet
 * @throws IllegalArgumentException - if a component exceeds Int64
 */
private func registryVersion(text: String): (Int64, Int64, Int64) {
    if (!Regex("^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$").matches(text)) {
        throw ProjectException("invalid registry version `${text}`")
    }
    let parts = text.split(".")
    (Int64.parse(parts[0]), Int64.parse(parts[1]), Int64.parse(parts[2]))
}

/**
 * Numeric lexicographic ordering of cjpm version components.
 */
private func compareRegistryVersions(a: (Int64, Int64, Int64), b: (Int64, Int64, Int64)): Ordering {
    if (a[0] != b[0]) {
        return a[0].compare(b[0])
    }
    if (a[1] != b[1]) {
        return a[1].compare(b[1])
    }
    a[2].compare(b[2])
}

/**
 * Converts an open bound to cjpm's inclusive bound, carrying between components and saturating
 * at the minimum or maximum version.
 */
private func adjacentRegistryVersion(
    version: (Int64, Int64, Int64),
    up!: Bool
): (Int64, Int64, Int64) {
    let edge = if (up) { Int64.Max } else { 0 }
    let reset = if (up) { 0 } else { Int64.Max }
    let step = if (up) { 1 } else { -1 }
    if (version[2] != edge) {
        return (version[0], version[1], version[2] + step)
    }
    if (version[1] != edge) {
        return (version[0], version[1] + step, reset)
    }
    if (version[0] != edge) {
        return (version[0] + step, reset, reset)
    }
    version
}
