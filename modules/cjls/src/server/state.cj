package cjls.server

import std.collection.{ArrayList, HashMap, HashSet}
import rope.{Encoding, Rope}
import loupe.vfs.*
import loupe.db.*

/**
 * The server's state, which a handler given a `Context` changes: the files as the editor and the
 * disk give them, the documents the editor has open, and the analysis, kept in step with the
 * files: a query takes `state.analysis`, the root handle of the analysis database.
 */
public class ServerState <: FromContext<ServerState> {
    public let analysis = AnalysisDatabase()
    private let vfs = Vfs()

    /**
     * The documents the editor has open, and the version of each it last sent: between
     * `didOpen` and `didClose` the editor's buffer is what the file holds, not the disk.
     */
    public let openDocuments = HashMap<VfsPath, Int32>()

    /**
     * What a column counts, as agreed on at `initialize`: UTF-16 until then, as LSP has it.
     */
    public var encoding = Encoding.Utf16

    /**
     * Whether the server pushes diagnostics, as agreed on at `initialize`: only to a client that
     * cannot pull them, so no document has two sources (S8).
     */
    public var pushesDiagnostics = false

    /**
     * Whether the client takes a semantic token spanning lines, as agreed on at `initialize`; one
     * that does not gets it cut at each line's end.
     */
    public var multilineTokens = false

    /**
     * Whether the client takes a definition as `LocationLink`s, as agreed on at `initialize`; one
     * that does not gets `Location`s.
     */
    public var locationLinks = false

    /**
     * Whether the client folds whole lines only, and how many folds of a document it takes at most,
     * as agreed on at `initialize`.
     */
    public var lineFoldingOnly = false
    public var foldingRangeLimit: ?Int64 = None

    /**
     * The roots of the workspace, as `initialize` and `didChangeWorkspaceFolders` give them: the
     * files under them are loaded, and watched.
     */
    public let roots = ArrayList<VfsPath>()

    /**
     * Whether the client watches files for the server, as agreed on at `initialize`: it takes a
     * watcher registered at run time; and one of a pattern relative to a folder.
     */
    public var watchesFiles = false
    public var relativePatterns = false

    /**
     * Whether the client shows the progress of work the server begins, as agreed on at `initialize`.
     */
    public var workDoneProgress = false

    /**
     * The id each root's watcher was registered with, to unregister it by.
     */
    public let watchers = HashMap<VfsPath, String>()

    /**
     * The projects `initializationOptions` names (`linkedProjects`): a `cj-project.json`, or a
     * directory to find one in.
     */
    public let linkedProjects = ArrayList<VfsPath>()

    /**
     * The SDK `initializationOptions` names (`cangjieHome`), the first place it is looked for.
     */
    public var cangjieHome: ?String = None

    /**
     * The files of the project, as last set: made anew each time, for a set built from an array
     * takes a third of the time `clear` and `add(all:)` do.
     */
    private var projectFiles = HashSet<VfsPath>()

    private var filesChanged = false
    private var registrations = 0

    /**
     * The latest load begun, which ends any before it; and the paths set since it began, by
     * anything but itself, whose contents what it read before must not undo: `None` once it ended.
     */
    private var load = 0
    private var setDuringLoad: ?HashSet<VfsPath> = None

    /**
     * The files with contents, for a snapshot to list; `None` once a file was created or deleted
     * since, until the next snapshot lists them again.
     */
    private var files: ?Array<FileId> = Array<FileId>()

    public static func from<P>(ctx: Context<P>): ServerState {
        ctx.state
    }

    /**
     * What the file at `path` holds, `None` if the server knows no such file.
     */
    public func fileContents(path: VfsPath): ?Rope {
        vfs.fileContents(vfs.fileId(path) ?? return None)
    }

    /**
     * Sets what the file at `path` holds, `None` for no file, and brings the analysis in step:
     * what is in flight on the snapshots is cancelled, if anything changed.
     */
    public func setFileContents(path: VfsPath, text: ?Rope): Unit {
        setFilesContents([(path, text)])
    }

    /**
     * Sets what each file holds, as `setFileContents` does, and brings the analysis in step with
     * all of them at once, in one revision.
     */
    public func setFilesContents(files: Array<(VfsPath, ?Rope)>): Unit {
        if (let Some(set) <- setDuringLoad) {
            for ((path, _) in files) {
                set.add(path)
            }
        }
        apply(files)
    }

    /**
     * Begins a load (D58), which ends the one before: from now on, a file set by anything but the
     * load is left as it is set.
     *
     * @return the load's number, which it sets its files with
     */
    public func beginLoad(): Int64 {
        load++
        setDuringLoad = HashSet<VfsPath>()
        load
    }

    /**
     * Whether `load` is the latest begun, and has not ended.
     */
    public func isLoading(load: Int64): Bool {
        this.load == load && setDuringLoad.isSome()
    }

    /**
     * Sets the files `load` read, in one revision, as `setFilesContents` does, but for the documents
     * open and the files set since it began: those the editor or a newer read of the disk gave.
     *
     * @return whether `load` is the latest begun, and has not ended: nothing is set otherwise
     */
    public func setLoadedFiles(load: Int64, files: Array<(VfsPath, Rope)>): Bool {
        let set = setDuringLoad ?? return false
        if (this.load != load) {
            return false
        }
        apply(files.filter {file => !openDocuments.contains(file[0]) && !set.contains(file[0])}.map {
            file => (file[0], Some(file[1]))
        })
        true
    }

    /**
     * Ends `load`, if it is the latest begun.
     *
     * @return whether it was, and had not ended
     */
    public func endLoad(load: Int64): Bool {
        if (!isLoading(load)) {
            return false
        }
        setDuringLoad = None
        true
    }

    private func apply(files: Array<(VfsPath, ?Rope)>): Unit {
        for ((path, text) in files) {
            vfs.setFileContents(path, text)
        }
        let changes = vfs.takeChanges()
        if (changes.isEmpty()) {
            return
        }
        analysis.applyChanges(vfs, changes)
        filesChanged = true
        if (changes.iterator().any {change => change.kind != ChangeKind.Modify}) {
            this.files = None
        }
    }

    /**
     * Sets the project the analysis sees: its modules and packages, and the files of each; and the
     * packages of its binaries that were read.
     */
    public func setProject(model: ProjectModel, binaries!: Array<CjoFileRead> = []): Unit {
        analysis.setProject(model, vfs.paths, binaries: binaries)
        projectFiles = HashSet<VfsPath>(model.files())
    }

    /**
     * The stamp of the `.cjo` `file` when it was last set, `None` if it never was: one that still
     * has it is not read again.
     */
    public func binaryStamp(file: CjoFile): ?FileStamp {
        analysis.binaryStamp(file)
    }

    /**
     * Whether the file at `path` is one of the project's.
     */
    public func inProject(path: VfsPath): Bool {
        projectFiles.contains(path)
    }

    /**
     * Whether the server knows what the file at `path` holds.
     */
    public func knows(path: VfsPath): Bool {
        vfs.fileId(path).isSome()
    }

    /**
     * The files with contents under `dir`, `dir` itself included.
     */
    public func filesUnder(dir: VfsPath): Array<VfsPath> {
        vfs.files().map {id => vfs.filePath(id)}.filter {path => path.isUnder(dir)}
    }

    /**
     * Whether the files changed since it was last asked; the server asks after every handler that
     * could change them.
     */
    func takeFilesChanged(): Bool {
        let changed = filesChanged
        filesChanged = false
        changed
    }

    /**
     * The state as it is now, for a handler running on a thread of its own. Its queries stop,
     * `CancelledException`, once `cancelledBy` gives `true`: the client cancelled the request.
     */
    public func snapshot(cancelledBy!: () -> Bool = {=> false}): ServerSnapshot {
        let files = this.files ?? vfs.files()
        this.files = files
        ServerSnapshot(analysis.snapshot(cancelledBy: cancelledBy), vfs.paths, files, encoding, multilineTokens,
            locationLinks, lineFoldingOnly, foldingRangeLimit)
    }

    /**
     * An id for a registration with the client, unique for the connection.
     */
    public func registrationId(): String {
        registrations++
        "cjls-${registrations}"
    }
}

/**
 * The state as it was when a message arrived, for its handler to read on a thread of its own. Once
 * the files change after it, a query on `analysis`, a snapshot of the analysis database, throws
 * `CancelledException`, which the server answers with `ContentModified`.
 */
public class ServerSnapshot <: FromReadOnlyContext<ServerSnapshot> {
    ServerSnapshot(public let analysis: AnalysisDatabase, private let paths: PathInterner,
        /**
         * Every file with contents, in the order of their ids.
         */
        public let files: Array<FileId>, public let encoding: Encoding, public let multilineTokens: Bool,
        public let locationLinks: Bool, public let lineFoldingOnly: Bool, public let foldingRangeLimit: ?Int64) {}

    public static func from<P>(ctx: ReadOnlyContext<P>): ServerSnapshot {
        ctx.snapshot
    }

    /**
     * The input of the file at `path`, `None` if the server never knew such a file.
     */
    public func sourceFile(path: VfsPath): ?SourceFile {
        analysis.sourceFile(paths.lookup(path) ?? return None)
    }

    /**
     * The path of a file of the snapshot.
     *
     * @throws IndexOutOfBoundsException - if the id was not given by the server
     */
    public func path(fileId: FileId): VfsPath {
        paths.path(fileId)
    }
}
