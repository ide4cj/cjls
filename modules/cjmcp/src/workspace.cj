package cjmcp

import std.collection.*
import std.env.getVariable
import std.fs.{canonicalize, exists, FileInfo, Path}
import fjson.*
import ginkgo.TextRange
import loupe.*
import loupe.db.AnalysisDatabase
import loupe.vfs.*
import project_model.*

/** One disk revision; replacing it on reload also discards cached queries for removed files. */
class Workspace {
    let db = AnalysisDatabase()
    let vfs = Vfs()
    let files: Array<VfsPath>
    let problems: Array<String>

    Workspace(let root: VfsPath) {
        if (
            !exists(root.toString()) || !FileInfo(canonicalize(Path(root.toString()))).isDirectory()
        ) {
            throw IllegalArgumentException("workspace directory does not exist: ${root}")
        }
        let found = findCangjieHome(None, env: getVariable)
        let homeEnv = withCangjieHome(getVariable, found)
        let env = withCangjieSrc(homeEnv, findCangjieSrc(None, env: homeEnv))
        let load = findProject(root, env: env)
        let issues = ArrayList<String>(load.problems)
        let model = withPackageCfgs(load.model, issues)
        let binaries = readCjoFiles(model.cjoFiles())
        issues.add(all: binaries.problems)
        db.setProject(model, vfs.paths, binaries: binaries.files)
        files = model.files()
        for (path in files.concat(model.binarySourceFiles())) {
            match (readFile(path)) {
                case Some(text) => vfs.setFileContents(path, text)
                case None => issues.add("could not read ${path}")
            }
        }
        db.applyChanges(vfs, vfs.takeChanges())
        problems = issues.toArray()
    }

    func status(): JsonValue {
        obj(
            [
                ("root", JsonString(root.toString())),
                ("files", JsonArray(files.map { path => JsonString(path.toString()) })),
                ("problems", JsonArray(problems.map { issue => JsonString(issue) })),
                ("macrosExpanded", JsonBool(false))
            ]
        )
    }

    func query(name: String, args: JsonValue): JsonValue {
        let written = args["path"].asString()
        let path =
            if (Path(written).isAbsolute()) { VfsPath.file(written) } else { root.join(written) }
        let id = vfs.fileId(path) ?? throw IllegalArgumentException("file is not loaded: ${path}")
        if (name == "diagnostics") {
            let items = diagnostics(db, id).map { item => diagnosticJson(item) }
            return obj([("diagnostics", JsonArray(items))])
        }
        if (name == "file_structure") {
            let nodes = fileStructure(db, id).map { node => structureJson(node) }
            return obj([("symbols", JsonArray(nodes))])
        }
        let offset = args["offset"].asInteger()
        let text = vfs.fileContents(id).getOrThrow().toString().toArray()
        if (
            offset < 0 || offset > text.size ||
                (offset < text.size && (text[offset] & 0xC0) == 0x80)
        ) {
            throw IllegalArgumentException("offset must be a UTF-8 byte boundary within the file")
        }
        if (name == "hover") {
            let hover = hoverAt(db, id, offset).map { result => hoverJson(result) } ?? JsonNull
            return obj([("hover", hover)])
        }
        let targets =
            definitionAt(db, id, offset).map { target => navigationJson(target, vfs.paths) }
        obj([("targets", JsonArray(targets))])
    }
}

func diagnosticJson(item: Diagnostic): JsonValue {
    let severity =
        match (item.severity) {
            case Severity.Error => "error"
            case Severity.Warning => "warning"
            case Severity.Hint => "hint"
        }
    obj(
        [
            ("range", rangeJson(item.range)),
            ("severity", JsonString(severity)),
            ("message", JsonString(item.message)),
            ("unnecessary", JsonBool(item.unnecessary))
        ]
    )
}

func hoverJson(hover: HoverResult): JsonValue {
    let items =
        hover
            .items
            .map {
                item =>
                obj(
                    [
                        ("code", JsonString(item.code)),
                        ("path", optionalString(item.path)),
                        ("doc", optionalString(item.doc))
                    ]
                )
            }
    obj([("range", rangeJson(hover.range)), ("items", JsonArray(items))])
}

func navigationJson(target: NavigationTarget, paths: PathInterner): JsonValue {
    obj(
        [
            ("path", JsonString(paths.path(target.fileId).toString())),
            ("range", rangeJson(target.fullRange)),
            ("selectionRange", rangeJson(target.focusRange))
        ]
    )
}

func obj(members: Array<(String, JsonValue)>): JsonValue {
    JsonObject(members)
}

func optionalString(value: ?String): JsonValue {
    value.map { text => JsonString(text) } ?? JsonNull
}

func rangeJson(range: TextRange): JsonValue {
    obj([("start", JsonInteger(range.start)), ("end", JsonInteger(range.end))])
}

func structureJson(node: StructureNode): JsonValue {
    obj(
        [
            ("name", JsonString(node.name)),
            ("kind", JsonString(node.kind.toString())),
            ("range", rangeJson(node.range)),
            ("selectionRange", rangeJson(node.selectionRange)),
            ("children", JsonArray(node.children.map { child => structureJson(child) }))
        ]
    )
}
