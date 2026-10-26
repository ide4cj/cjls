package cjls.server

import std.collection.{ArrayList, HashMap, HashSet}
import std.env.getVariable
import std.runtime.getMaxHeapSize
import stdx.log.Logger
import loupe.newFilePackageLine
import loupe.db.*
import loupe.hir.setMacroOutputsByKey
import loupe.vfs.*
import rope.{Encoding, Rope}

/**
 * The `.cjo` of a project's binaries (D38), as an event reports them: every one in the
 * directories of theirs, each directory come or gone too, and those named one by one; and the id
 * of the registration the client watches them by, to unregister it by, `None` if it does not.
 */
public struct BinaryWatch {
    public BinaryWatch(
        public let id: ?String,
        public let dirs: Array<VfsPath>,
        public let files: Array<VfsPath>
    ) {}

    /**
     * Whether an event at `path` is of what is watched: a `.cjo` in one of `dirs`, one of `files`,
     * or one of `dirs` itself, come or gone as a whole.
     */
    public func covers(path: VfsPath): Bool {
        if (files.contains(path) || dirs.contains(path)) {
            return true
        }
        let parent = path.parent ?? return false
        path.name.endsWith(".cjo") && dirs.contains(parent)
    }
}

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
     * How many times a document was opened: a diagnostic report's `resultId` from before an
     * opening never matches after it (#51).
     */
    public var openings = 0

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
     * Whether the client lays semantic tokens over a highlighting of its own, as agreed on at
     * `initialize`: it gets no token its grammar names as well (D105).
     */
    public var augmentsSyntaxTokens = false

    /**
     * Whether the client asks for the semantic tokens of its documents again when told to, as agreed
     * on at `initialize`: it is, after a change of the files, which may change any document's (D72).
     */
    public var refreshesSemanticTokens = false

    /**
     * Whether the client pulls the diagnostics of its documents again when told to, as agreed on at
     * `initialize`: it is, after a change of the files, which may change any document's (D100).
     */
    public var refreshesDiagnostics = false

    /**
     * Whether the client takes a definition as `LocationLink`s, as agreed on at `initialize`; one
     * that does not gets `Location`s.
     */
    public var locationLinks = false

    /**
     * Whether the client takes a hover's content as Markdown, as agreed on at `initialize`; one that
     * does not gets plain text.
     */
    public var hoverMarkdown = false

    /**
     * Whether the client takes a completion item's documentation as Markdown, as agreed on at
     * `initialize`; one that does not gets plain text.
     */
    public var completionMarkdown = false

    /**
     * Whether the client renders completion label details, as agreed on at `initialize`.
     */
    public var completionLabelDetails = false

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
     * Whether the client shows a document the server asks it to (`window/showDocument`), and takes a
     * code action as a literal rather than a bare command, as agreed on at `initialize`.
     */
    public var showsDocuments = false
    public var codeActionLiterals = false

    /**
     * What runs the workspace's macros, once the workspace is loaded the first time (D104); woken after every
     * write that changes the files.
     */
    public var macroWork: ?MacroWork = None

    /**
     * What starts `macroWork` (D141): the server's runs `cjls.macro_host`'s `MacroHost`; `None`, as a state is made,
     * runs no macros, so a test's thread holds no state to the end of the process.
     */
    public var startsMacros: ?(Loop, Logger) -> MacroWork = None

    /**
     * The server's directories beside the projects (D106), each set in order the first time it is opened.
     */
    public let cacheDirs = CacheDirs({name => getVariable(name)})

    /**
     * The id each root's watcher was registered with, to unregister it by.
     */
    public let watchers = HashMap<VfsPath, String>()

    /**
     * The `.cjo` of the binaries of the last project set, and how the client watches them; `None`
     * before a project is.
     */
    public var binaryWatch: ?BinaryWatch = None

    /**
     * What the user set, as `initialize` and then the client's configuration give it (D79).
     */
    public var settings = Settings()

    /**
     * Whether the client answers `workspace/configuration`, as agreed on at `initialize`: it is asked
     * for the settings rather than read from what it pushes; and whether it takes a registration for
     * `didChangeConfiguration`, without which it may never send one.
     */
    public var pullsSettings = false
    public var registersSettings = false

    // the last time the settings were asked for: an older answer is not taken
    private var settingsPull = 0

    /**
     * How much a load reads at most, in bytes, the `.cjo` of the binaries first and the text of the
     * sources then: a sixteenth of the heap (D31). On the runtime's default of 256 MiB, 16 MiB of
     * text was loaded and searched and 32 MiB ran out of memory (D30); a root far wider than a
     * project (a home directory, a test suite of a hundred thousand files) would fill any heap with
     * text alone.
     */
    public var loadBudget = getMaxHeapSize() / 16

    /**
     * The roots of loose files the last project set left files out of, past the load budget: a
     * document opened there may be none of the project's, and the project is found again for it
     * (D80).
     */
    public var partialRoots: Array<VfsPath> = []

    /**
     * The directories of the projects found from a document opened in no package (#265): loaded
     * with the roots' from then on, until the last root they are under is removed.
     */
    public var foundProjects: Array<VfsPath> = []

    /**
     * Whether `initialized` came: before it no project is looked for, and a document opened in no
     * package is compiled alone by none (#293).
     */
    public var initialized = false

    /**
     * The files of the project, as last set: made anew each time, for a set built from an array
     * takes a third of the time `clear` and `add(all:)` do.
     */
    private var projectFiles = HashSet<VfsPath>()

    /**
     * The files of the sources of the binaries, as last set: read, but no file of the workspace.
     */
    private var binarySourceFiles = HashSet<VfsPath>()

    /**
     * The project, as last set: what names the package of a file new.
     */
    private var model = ProjectModel(Cfg([]), [])

    /**
     * Whether the client applies a `workspace/applyEdit`, and takes an edit of a document with the
     * version it was made for (`documentChanges`), as agreed on at `initialize`.
     */
    public var appliesEdits = false
    public var versionedEdits = false

    /**
     * The blank documents opened while a load ran, and the version each was opened at: one still at
     * it is given its `package` line once the load ends, with the project that names its package (#294).
     */
    public let blankDuringLoad = HashMap<VfsPath, Int32>()

    private var filesChanged = false
    private var registrations = 0

    /**
     * The latest load begun, which ends any before it; and the paths set since it began, by
     * anything but itself, whose contents what it read before must not undo: `None` once it ended.
     */
    private var load = 0
    private var setDuringLoad: ?HashSet<VfsPath> = None

    /**
     * The files of the folders removed, which go with the next project set, in its revision (S12):
     * until then the workspace is the old project with all its files. A file set meanwhile is no
     * longer among them.
     */
    private var goneWithProject = HashSet<VfsPath>()

    /**
     * The files with contents but for the sources of the binaries, for a snapshot to list; `None`
     * once a file was created or deleted, or the project set, since, until the next snapshot lists
     * them again.
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
        for ((path, _) in files) {
            setDuringLoad?.add(path)
            goneWithProject.remove(path)
        }
        apply(files)
    }

    /**
     * Makes the files at `paths` go with the next project set, in its revision, but for those under
     * a root then: a folder removed takes its files with the project it leaves.
     */
    public func dropWithProject(paths: Array<VfsPath>): Unit {
        goneWithProject.add(all: paths)
    }

    /**
     * Drops at once, in a revision of their own, the files `dropWithProject` left for a project no
     * load is to set.
     */
    public func dropGone(): Unit {
        apply(takeGone())
    }

    private func takeGone(): Array<(VfsPath, ?Rope)> {
        let rootsNow = roots.toArray()
        let gone = goneWithProject.toArray().filter {path => !isWorkspaceFile(path, rootsNow)}.map {
            path => (path, Option<Rope>.None)
        }
        goneWithProject = HashSet<VfsPath>()
        gone
    }

    /**
     * Begins a load (D61), which ends the one before: from now on, a file set by anything but the
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
     * Whether a load is running: one begun has not ended.
     */
    public prop loading: Bool {
        get() {
            setDuringLoad.isSome()
        }
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
     * packages of its binaries that were read. The files `dropWithProject` left go in the same
     * revision.
     */
    public func setProject(model: ProjectModel, binaries!: Array<CjoFileRead> = []): Unit {
        let gone = takeGone()
        analysis.batch {
            analysis.setProject(model, vfs.paths, binaries: binaries)
            // after the project: a file gone takes the durability the new project gives it
            apply(gone)
        }
        this.model = model
        projectFiles = HashSet<VfsPath>(model.files())
        binarySourceFiles = HashSet<VfsPath>(model.binarySourceFiles())
        files = None
    }

    /**
     * The stamp of the `.cjo` `file` when it was last set, `None` if it never was: one that still
     * has it is not read again.
     */
    public func binaryStamp(file: CjoFile): ?FileStamp {
        analysis.binaryStamp(file)
    }

    /**
     * The package header for a new file, from the project last set and the current file contents;
     * `None` if the project names none (`newFilePackageLine`).
     */
    protected func packageLineOfNewFile(path: VfsPath): ?String {
        newFilePackageLine(model, path) {file => fileContents(file)}
    }

    /**
     * Whether the file at `path` is one of the project's.
     */
    public func inProject(path: VfsPath): Bool {
        projectFiles.contains(path)
    }

    /**
     * Whether the Cangjie file at `path` is under a root the last project left files out of, and
     * none of its own: a document open there is analyzed once the project is found again (D80).
     */
    public func leftOut(path: VfsPath): Bool {
        !inProject(path) && isWorkspaceFile(path, partialRoots)
    }

    /**
     * Whether the Cangjie file at `path` is nothing of the project last set: of no package, of no
     * binary's sources, and none a module's build leaves out. A document open there finds the
     * project again (D80, D88), or is compiled alone (#293).
     */
    public func inNoPackage(path: VfsPath): Bool {
        isCangjieFile(path.name) && !projectFiles.contains(path) && !binarySourceFiles.contains(path) &&
            !model.modules.iterator().any {module => module.inactive.iterator().any {file => file.path == path}}
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
     * Sets the stamp of each macro package's library cjls built (D104): every call of its macros is asked again.
     * Changes what the files say, as an edit does.
     */
    public func setMacroLibraries(stamps: Array<(Package, Int64)>): Unit {
        // read before the batch, which reads nothing
        let changed = stamps.filter {one => one[0].macroLibrary(analysis) != one[1]}
        analysis.batch {
            for ((pkg, stamp) in changed) {
                pkg.setMacroLibrary(analysis).to(stamp)
            }
        }
        filesChanged = true
    }

    /**
     * Sets what the macro server answered for calls of the files, in one revision (D98). Changes what the files
     * say, as an edit does.
     */
    public func setMacroOutputs(answers: Array<(SourceFile, MacroCallKey, MacroOutput)>): Unit {
        setMacroOutputsByKey(analysis, answers)
        filesChanged = true
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
        // an expanded file the editor opened is no file of the workspace
        let files = this.files ?? vfs.files().filter {
            id =>
            let path = vfs.filePath(id)
            !binarySourceFiles.contains(path) && !isExpandedFile(path)
        }
        this.files = files
        ServerSnapshot(analysis.snapshot(cancelledBy: cancelledBy), vfs.paths, files, encoding, multilineTokens,
            augmentsSyntaxTokens, locationLinks, lineFoldingOnly, foldingRangeLimit, hoverMarkdown, completionMarkdown,
            completionLabelDetails, roots.toArray(), showsDocuments, codeActionLiterals, cacheDirs, openings)
    }

    /**
     * An id for a registration with the client, unique for the connection.
     */
    public func registrationId(): String {
        registrations++
        "cjls-${registrations}"
    }

    /**
     * Begins asking the client for the settings, which ends the asking before: its number.
     */
    public func beginSettingsPull(): Int64 {
        settingsPull++
        settingsPull
    }

    /**
     * Whether `pull` is the last time the settings were asked for, the one whose answer is taken.
     */
    public func isLastSettingsPull(pull: Int64): Bool {
        pull == settingsPull
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
        public let augmentsSyntaxTokens: Bool, public let locationLinks: Bool, public let lineFoldingOnly: Bool,
        public let foldingRangeLimit: ?Int64, public let hoverMarkdown: Bool, public let completionMarkdown: Bool,
        public let completionLabelDetails: Bool,
        /**
         * The roots of the workspace, as the state had them.
         */
        public let roots: Array<VfsPath>, public let showsDocuments: Bool, public let codeActionLiterals: Bool,
        public let cacheDirs: CacheDirs,
        /**
         * How many times a document was opened, as the state had it.
         */
        public let openings: Int64) {}

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
