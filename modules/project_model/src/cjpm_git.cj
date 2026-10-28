package project_model

import std.collection.*
import std.fs.*
import ftoml.*
import stdxx.deriving.*
import loupe.vfs.VfsPath

/**
 * Reads cjpm's resolution without running commands or changing its shared cache. The entry
 * project's lock owns transitive selections too; a dependency's own lock is not authoritative.
 */
class CjpmGit {
    private let resolution: CjpmResolution

    CjpmGit(private let loading: Loading, private let root: VfsPath) {
        resolution = CjpmResolution(loading, root)
    }

    func resolve(name: String, declared: DependencyTable, script!: Bool): ?VfsPath {
        try {
            let (entry, version, cache) = resolution.entry(name, script: script)
            let selected = gitSelection(entry, version)
            let url = declared.git.getOrThrow()
            if (url.removeSuffix(".git") != selected[0].removeSuffix(".git")) {
                throw ProjectException("the locked Git URL differs from cjpm.toml")
            }
            if (let Some(commit) <- declared.commitId) {
                if (!gitCommit(commit) || !selected[1].startsWith(commit)) {
                    throw ProjectException("the locked commit differs from cjpm.toml")
                }
            } else if (let Some(branch) <- declared.branch) {
                if (selected[2] != Some(branch)) {
                    throw ProjectException("the locked branch differs from cjpm.toml")
                }
            } else if (let Some(tag) <- declared.tag) {
                if (selected[3] != Some(tag)) {
                    throw ProjectException("the locked tag differs from cjpm.toml")
                }
            }
            let safeName = gitCacheName(name)
            let checkout = cache.join("git").join(safeName).join(selected[1])
            if (isFile(checkout.join("cjpm.toml").filePath.getOrThrow())) {
                return packageAt(checkout, name)
            }
            // cjpm names Git workspaces by the URL's Cangjie hash, rather than by a member.
            let workspace =
                cache.join("git").join("workspace-${selected[0].hashCode()}").join(selected[1])
            if (isFile(workspace.join("cjpm.toml").filePath.getOrThrow())) {
                return packageAt(workspace, name)
            }
            // An explicit abbreviated commit may be the cache directory used by cjpm on the
            // first fetch; the resulting lock records the full hash.
            if (let Some(commit) <- declared.commitId) {
                let abbreviated = cache.join("git").join(safeName).join(commit)
                if (isFile(abbreviated.join("cjpm.toml").filePath.getOrThrow())) {
                    return packageAt(abbreviated, name)
                }
            }
            throw ProjectException("checkout ${checkout} is missing")
        } catch (e: Exception) {
            let kind = if (script) { "script dependency" } else { "dependency" }
            loading
                .problems
                .add(
                    "Git ${kind} `${name}` is left out: ${e.message}; run `cjpm update` in ${root}"
                )
            None
        }
    }

    private func packageAt(dir: VfsPath, name: String): VfsPath {
        let manifest = readManifest(dir.join("cjpm.toml"))
        if (let Some(pkg) <- manifest.pkg) {
            let actual = packageName(pkg)
            if (actual != name) {
                throw ProjectException("checkout ${dir} declares `${actual}`, expected `${name}`")
            }
            return dir
        }
        for (member in manifest.workspace.flatMap { it => it.members } ?? []) {
            let path = loading.resolve(dir, member)
            let candidate = readManifest(path.join("cjpm.toml"))
            if (candidate.pkg.map { pkg => packageName(pkg) == name } ?? false) {
                return path
            }
        }
        throw ProjectException("Git workspace ${dir} has no member `${name}`")
    }
}

func packageName(pkg: ManifestPackage): String {
    match (pkg.organization) {
        case Some(org) where !org.trimAscii().isEmpty() => "${org.trimAscii()}::${pkg.name}"
        case _ => pkg.name
    }
}

/**
 * cjpm's `swapOrgName`: `org::module` is stored under `module@org`.
 */
func gitCacheName(name: String): String {
    let parts = name.split("::")
    if (
        parts.isEmpty() || parts.size > 2 ||
            parts
                .iterator()
                .any {
                    part =>
                    part.isEmpty() || part == "." || part == ".." || part.contains("/") ||
                        part.contains("\\")
                }
    ) {
        throw ProjectException("invalid dependency name `${name}`")
    }
    if (parts.size == 2) { "${parts[1]}@${parts[0]}" } else { name }
}

func gitCommit(commit: String): Bool {
    !commit.isEmpty() && commit.size <= 64 &&
        commit
            .toArray()
            .iterator()
            .all { byte => (byte >= b'0' && byte <= b'9') || (byte >= b'a' && byte <= b'f') }
}

/**
 * URL, resolved commit, branch and tag from legacy v0 fields or the v1 source string.
 */
func gitSelection(entry: DependencyTable, version: Int64): (String, String, ?String, ?String) {
    if (version == 0) {
        let url = entry.git ?? throw ProjectException("locked entry is not a Git dependency")
        let commit = entry.commitId ?? throw ProjectException("locked entry has no commitId")
        if (!gitCommit(commit)) {
            throw ProjectException("invalid locked commit")
        }
        return (url, commit, entry.branch, entry.tag)
    }
    let source = entry.source ?? throw ProjectException("locked entry has no source")
    if (!source.startsWith("git+")) {
        throw ProjectException("locked entry is not a Git dependency")
    }
    let parts = source[4..].split("#")
    if (parts.size != 2 || !gitCommit(parts[1]) || (parts[1].size != 40 && parts[1].size != 64)) {
        throw ProjectException("invalid Git lock source")
    }
    let url = parts[0].split("?")
    if (url[0].isEmpty() || url.size > 2) {
        throw ProjectException("invalid Git lock URL")
    }
    var branch: ?String = None
    var tag: ?String = None
    if (url.size == 2) {
        if (url[1].startsWith("branch=")) {
            branch = gitDecodeSelector(url[1][7..])
        } else if (url[1].startsWith("tag=")) {
            tag = gitDecodeSelector(url[1][4..])
        } else {
            throw ProjectException("invalid Git lock selector")
        }
    }
    (url[0], parts[1], branch, tag)
}

private func gitDecodeSelector(text: String): String {
    let out = ArrayList<Byte>()
    let bytes = text.toArray()
    var i = 0
    while (i < bytes.size) {
        if (bytes[i] == b'%') {
            if (i + 2 >= bytes.size) {
                throw ProjectException("invalid escaped Git selector")
            }
            let high = gitHex(bytes[i + 1])
            let low = gitHex(bytes[i + 2])
            out.add(high * 16 + low)
            i += 3
        } else {
            out.add(bytes[i])
            i++
        }
    }
    String.fromUtf8(out.toArray())
}

private func gitHex(byte: Byte): Byte {
    if (byte >= b'0' && byte <= b'9') {
        return byte - b'0'
    }
    if (byte >= b'a' && byte <= b'f') {
        return byte - b'a' + 10
    }
    if (byte >= b'A' && byte <= b'F') {
        return byte - b'A' + 10
    }
    throw ProjectException("invalid escaped Git selector")
}

func repositoryCache(loading: Loading, root: VfsPath): ?VfsPath {
    let homeText =
        match (loading.env("HOME")) {
            case Some(text) => Some(text)
            case None => loading.env("USERPROFILE")
        }
    let home = homeText.map { text => loading.resolve(root, text) }
    let sdk = loading.env("CANGJIE_HOME").map { text => loading.resolve(root, text) }
    let candidates =
        [
            Some(root.join("cangjie-repo.toml")),
            home.map { it => it.join(".cjpm/cangjie-repo.toml") },
            sdk.map { it => it.join("tools/config/cangjie-repo.toml") }
        ]
    for (candidate in candidates) {
        if (let Some(file) <- candidate) {
            if (!isFile(file.filePath.getOrThrow())) {
                continue
            }
            let config =
                fromTomlBytes<CjpmRepositoryConfig>(File.readFrom(file.filePath.getOrThrow()))
            let path = config.repository.flatMap { it => it.cache }.flatMap { it => it.path } ?? ""
            if (!path.isEmpty()) {
                return loading.resolve(file.parent.getOrThrow(), path)
            }
            return home.map { it => it.join(".cjpm") }
        }
    }
    home.map { it => it.join(".cjpm") }
}

@DeriveExt[FromToml]
struct CjpmLock {
    CjpmLock(
        let version!: Int64,
        let requires!: ?HashMap<String, DependencyTable> = None,
        let scripts!: ?HashMap<String, DependencyTable> = None
    ) {}
}

@DeriveExt[FromToml]
struct CjpmRepositoryConfig {
    CjpmRepositoryConfig(let repository!: ?CjpmRepository = None) {}
}

@DeriveExt[FromToml]
struct CjpmRepository {
    CjpmRepository(let cache!: ?CjpmCache = None) {}
}

@DeriveExt[FromToml]
struct CjpmCache {
    CjpmCache(let path!: ?String = None) {}
}
