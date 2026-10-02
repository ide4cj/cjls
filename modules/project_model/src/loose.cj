package project_model

import std.collection.*
import std.fs.*
import std.sort.*
import loupe.db.*
import loupe.vfs.{isCangjieFile, isScanned, VfsPath}

/**
 * How much of a file is read for its `package` line: a header comes first, after comments at most.
 */
const HEADER_BYTES = 4096

/**
 * The package of a file with no `package` line, as cjc names it.
 */
const DEFAULT_PACKAGE = "default"

/**
 * The project of the `*.cj` under `root`, as `readRoots` walks them, with no manifest to say how
 * they are built: a package per name the files' `package` lines give (`default` without one), in
 * the directory of its first file, and a module per root package, rooted at `root`, with `std`
 * alone to import. At most `budget` bytes of files are taken, as a load would read no more.
 */
public func looseProject(root: VfsPath, env!: (String) -> ?String, cfg!: Cfg = hostCfg(),
    budget!: Int64 = Int64.Max): ProjectLoad {
    let loading = Loading(env, cfg)
    let walk = LooseWalk(budget)
    walk.walk(root)
    let names = walk.byPackage.keys().toArray()
    sort(names)
    let modules = ArrayList<(String, ArrayList<PackageModel>)>()
    for (name in names) {
        let files = walk.byPackage[name].toArray()
        sort(files, by: {a, b => a.toString().compare(b.toString())})
        let pkg = PackageModel(name, files[0].parent.getOrThrow(), files)
        let module = moduleOf(name)
        match (modules.iterator().filter {it => it[0] == module}.next()) {
            case Some((_, packages)) => packages.add(pkg)
            case None => modules.add((module, ArrayList<PackageModel>([pkg])))
        }
    }
    if (walk.truncated) {
        loading.problems.add("the files under ${root} hold more text than is loaded: the rest is left out")
    }
    let binaries = ArrayList<BinaryModel>()
    if (let Some(std) <- loading.stdBinary()) {
        binaries.add(std)
    }
    let model = ProjectModel(cfg, modules.toArray().map {module => ModuleModel(module[0], root, module[1].toArray())},
        binaries: binaries.toArray())
    ProjectLoad(model, LooseFiles(root), loading.problems.toArray())
}

private class LooseWalk {
    let byPackage = HashMap<String, ArrayList<VfsPath>>()
    var truncated = false

    LooseWalk(private var budget: Int64) {}

    func walk(dir: VfsPath): Unit {
        let path = dir.filePath ?? return ()
        let entries = try {
            Directory.readFrom(path)
        } catch (_: FSException) {
            return
        }
        for (entry in entries where !entry.isSymbolicLink()) {
            if (entry.isDirectory()) {
                if (isScanned(entry.name)) {
                    walk(VfsPath.file(entry.path))
                }
            } else if (entry.isRegular() && isCangjieFile(entry.name)) {
                if (entry.size > budget) {
                    truncated = true
                    continue
                }
                budget -= entry.size
                let file = VfsPath.file(entry.path)
                let name = packageOf(entry.path) ?? DEFAULT_PACKAGE
                if (!byPackage.contains(name)) {
                    byPackage.add(name, ArrayList<VfsPath>())
                }
                byPackage[name].add(file)
            }
        }
    }
}

/**
 * The package the `package` line of the file at `path` names, `None` without one, or if it cannot
 * be read.
 */
func packageOf(path: Path): ?String {
    let header = try {
        let file = File(path, OpenMode.Read)
        try {
            let buffer = Array<Byte>(HEADER_BYTES, repeat: 0)
            var read = 0
            while (read < buffer.size) {
                let n = file.read(buffer[read..])
                if (n == 0) {
                    break
                }
                read += n
            }
            buffer[..read]
        } finally {
            file.close()
        }
    } catch (_: FSException) {
        return None
    }
    packageHeader(header)
}

/**
 * The name the `package` line at the start of `text` gives, after comments, blanks and modifiers
 * (`macro package`, `protected package`); `None` if the file starts with anything else. A name is
 * dotted identifiers, the first maybe with an organization (`org::a.b`); a backquoted one keeps
 * its name.
 */
public func packageHeader(text: Array<Byte>): ?String {
    let scanner = HeaderScanner(text)
    while (true) {
        let word = scanner.word() ?? return None
        match (word) {
            case "macro" | "public" | "protected" | "internal" => continue
            case "package" => return scanner.name()
            case _ => return None
        }
    }
    None
}

private class HeaderScanner {
    private var at = 0

    HeaderScanner(private let text: Array<Byte>) {}

    /**
     * The next identifier after blanks and comments, its backquotes taken off; `None` if
     * something else comes next.
     */
    func word(): ?String {
        skipTrivia()
        if (at < text.size && text[at] == b'`') {
            let start = at + 1
            let end = indexOf(b'`', start) ?? return None
            at = end + 1
            return String.fromUtf8(text[start..end])
        }
        let start = at
        while (at < text.size && isIdentifierByte(text[at], at == start)) {
            at++
        }
        if (at == start) {
            None
        } else {
            String.fromUtf8(text[start..at])
        }
    }

    /**
     * A package name: identifiers joined by `.`, the first maybe after `org::`.
     */
    func name(): ?String {
        let out = StringBuilder(word() ?? return None)
        if (at + 1 < text.size && text[at] == b':' && text[at + 1] == b':') {
            at += 2
            out.append("::")
            out.append(word() ?? return None)
        }
        while (true) {
            skipTrivia()
            if (at < text.size && text[at] == b'.') {
                at++
                out.append(".")
                out.append(word() ?? return None)
            } else {
                break
            }
        }
        out.toString()
    }

    private func skipTrivia(): Unit {
        while (at < text.size) {
            let byte = text[at]
            if (byte == b' ' || byte == b'\t' || byte == b'\n' || byte == b'\r' || byte == b'\f') {
                at++
            } else if (startsWith("//")) {
                at = (indexOf(b'\n', at) ?? text.size)
            } else if (startsWith("/*")) {
                skipBlockComment()
            } else {
                break
            }
        }
    }

    /**
     * A block comment, nested ones in it.
     */
    private func skipBlockComment(): Unit {
        var depth = 0
        while (at < text.size) {
            if (startsWith("/*")) {
                depth++
                at += 2
            } else if (startsWith("*/")) {
                depth--
                at += 2
                if (depth == 0) {
                    return
                }
            } else {
                at++
            }
        }
    }

    private func startsWith(s: String): Bool {
        let bytes = s.toArray()
        at + bytes.size <= text.size && (0..bytes.size).iterator().all {i => text[at + i] == bytes[i]}
    }

    private func indexOf(byte: Byte, from: Int64): ?Int64 {
        for (i in from..text.size where text[i] == byte) {
            return i
        }
        None
    }
}

/**
 * Whether `byte` goes in an identifier: ASCII letters, `_`, digits but first, and any byte of a
 * character beyond ASCII (Cangjie takes Unicode identifiers).
 */
private func isIdentifierByte(byte: Byte, first: Bool): Bool {
    (byte >= b'a' && byte <= b'z') || (byte >= b'A' && byte <= b'Z') || byte == b'_' || byte >= 0x80 ||
        (!first && byte >= b'0' && byte <= b'9')
}
