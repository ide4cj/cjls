package loupe

import std.collection.*
import std.deriving.Derive
import loupe.db.{AnalysisDatabase, BinaryModel, Cfg, InactiveSourceFile, Module}
import loupe.hir.*
import loupe.vfs.{FileId, VfsPath}

extend SemanticAnalysis {
    /**
     * The single merged loaded project, or none before project inputs are installed.
     * Original workspace-root grouping is not retained by the merged input.
     */
    public func project(): ?SemanticProject {
        db.unwindIfCancelled()
        db.project().map { _ => SemanticProject(this) }
    }
}

/**
 * Traversal of loaded inputs only. Collections preserve input order and support ordinary
 * Array filtering. All methods use the originating snapshot and cancel after input changes.
 */
public class SemanticProject {
    SemanticProject(let analysis: SemanticAnalysis) {}

    public func modules(): Array<SemanticModule> {
        let db = analysis.db
        db.unwindIfCancelled()
        db.project().getOrThrow().modules(db).map { id => SemanticModule(analysis, id) }
    }

    /**
     * Source, binary and detached attached-source contexts, each identity once.
     */
    public func packages(): Array<SemanticPackage> {
        let db = analysis.db
        db.unwindIfCancelled()
        let project = db.project().getOrThrow()
        let result = ArrayList<SemanticPackage>()
        for (module in modules()) {
            result.add(all: module.packages())
        }
        for (binary in project.binaryPackages(db)) {
            result.add(SemanticPackage(analysis, PackageRef.Binary(binary)))
        }
        for (source in project.binarySources(db)) {
            if (
                let Some(pkg) <- source.context &&
                    !result.iterator().any { one => one.identity == PackageRef.Source(pkg) }
            ) {
                result.add(SemanticPackage(analysis, PackageRef.Source(pkg)))
            }
        }
        result.toArray()
    }

    public func files(): Array<SemanticFile> {
        packages().flatMap { pkg => pkg.files() }
    }

    public func dependencies(): Array<SemanticDependency> {
        modules().flatMap { module => module.dependencies() }
    }

    /** Selected loaded binary models; never enumerates their paths on disk. */
    public func binaries(): Array<BinaryModel> {
        let db = analysis.db
        db.unwindIfCancelled()
        db.project().getOrThrow().binaries(db)
    }

    public func configuration(): SemanticConfiguration {
        let db = analysis.db
        db.unwindIfCancelled()
        SemanticConfiguration(db.project().getOrThrow().cfg(db))
    }
}

/**
 * Effective analysis conditions, not an exact compiler invocation. The loader does not
 * retain profile/feature/flag completeness, selection provenance, source-set names or load
 * diagnostics in database inputs. Unavailable metadata is separate from a known empty result.
 * Missing @When comparison keys remain unknown/active; absent debug/test flags currently
 * follow CfgExpr's false default, not proof that the compiler was invoked without them.
 */
public class SemanticConfiguration {
    SemanticConfiguration(public let cfg: Cfg) {}

    public prop loadingProblems: ?Array<String> {
        get() {
            None
        }
    }
    public prop selectionProvenance: ?String {
        get() {
            None
        }
    }
    public prop selectedSourceSets: ?Array<String> {
        get() {
            None
        }
    }
    public prop completeCompilerInvocation: Bool {
        get() {
            false
        }
    }
}

/** A dependency permission, not evidence of an import statement. */
public class SemanticDependency {
    SemanticDependency(
        public let source: SemanticModule,
        public let name: String,
        public let testOnly: Bool,
        public let implicit: Bool,
        public let modules: Array<SemanticModule>,
        public let binaries: Array<BinaryModel>
    ) {}

    /** False distinguishes a missing selected target from an empty package collection. */
    public prop isResolved: Bool {
        get() {
            !modules.isEmpty() || !binaries.isEmpty()
        }
    }
}

/** Module identity includes its independent resolution scope, including script selections. */
public class SemanticModule {
    SemanticModule(let analysis: SemanticAnalysis, public let identity: Module) {}

    public func name(): String {
        analysis.db.unwindIfCancelled()
        identity.name(analysis.db)
    }

    public func root(): VfsPath {
        analysis.db.unwindIfCancelled()
        identity.root(analysis.db)
    }

    public func resolutionScope(): String {
        analysis.db.unwindIfCancelled()
        identity.resolutionScope(analysis.db)
    }

    public func isWorkspaceMember(): Bool {
        analysis.db.unwindIfCancelled()
        identity.member(analysis.db)
    }

    public func packages(): Array<SemanticPackage> {
        analysis.db.unwindIfCancelled()
        identity
            .packages(analysis.db)
            .map { pkg => SemanticPackage(analysis, PackageRef.Source(pkg)) }
    }

    public func configuration(): SemanticConfiguration {
        let db = analysis.db
        db.unwindIfCancelled()
        SemanticConfiguration(identity.cfg(db) ?? db.project().getOrThrow().cfg(db))
    }

    /** Source-set exclusions retained by the loader, even when their text was not loaded. */
    public func inactiveFiles(): Array<InactiveSourceFile> {
        analysis.db.unwindIfCancelled()
        identity.inactive(analysis.db)
    }

    /**
     * Direct ordinary and additional test-only edges, plus implicit std. Script edges retain
     * their module's resolutionScope; downstream modules do not inherit test-only permissions.
     */
    public func dependencies(): Array<SemanticDependency> {
        let db = analysis.db
        db.unwindIfCancelled()
        let project = analysis.project().getOrThrow()
        let modules = project.modules()
        let binaries = project.binaries()
        let result = ArrayList<SemanticDependency>()
        func add(name: String, testOnly: Bool, implicit: Bool): Unit {
            result.add(
                SemanticDependency(
                    this,
                    name,
                    testOnly,
                    implicit,
                    modules
                        .filter {
                            one =>
                            one.name() == name &&
                                (
                                    one.resolutionScope() == resolutionScope() ||
                                        (name == "std" && one.resolutionScope().isEmpty())
                                )
                        },
                    binaries.filter { one => one.name == name }
                )
            )
        }
        for (name in identity.deps(db)) {
            add(name, false, false)
        }
        for (name in identity.testDeps(db)) {
            add(name, true, false)
        }
        if (!identity.deps(db).contains("std")) {
            add("std", false, true)
        }
        result.toArray()
    }
}

/** Loaded origin, independent of a declaration's navigation source. */
@Derive[Equatable]
public enum SemanticPackageOrigin {
    | WorkspacePackage
    | DependencyPackage
    | BinaryPackageOrigin
    | AttachedPackage
}

/** A contextual package. Attached source retains its detached identity, not its binary's. */
public class SemanticPackage {
    SemanticPackage(let analysis: SemanticAnalysis, public let identity: PackageRef) {}

    public func name(): String {
        analysis.db.unwindIfCancelled()
        nameOf(analysis.db, identity)
    }

    public func object(): SemanticObject {
        analysis.db.unwindIfCancelled()
        analysis.object(SemanticIdentity.NamedIdentity(Definition.PackageDef(identity)))
    }

    public func module(): ?SemanticModule {
        let db = analysis.db
        db.unwindIfCancelled()
        let project = analysis.project() ?? return None
        project
            .modules()
            .iterator()
            .filter {
                one =>
                one
                    .identity
                    .packages(db)
                    .iterator()
                    .any { pkg => identity == PackageRef.Source(pkg) }
            }
            .next()
    }

    public func binary(): ?SemanticPackage {
        let db = analysis.db
        db.unwindIfCancelled()
        match (identity) {
            case Source(pkg) =>
                pkg.binary(db).map { id => SemanticPackage(analysis, PackageRef.Binary(id)) }
            case Binary(_) => this
        }
    }

    public func isWorkspaceMember(): Bool {
        module().map { one => one.isWorkspaceMember() } ?? false
    }

    public func origin(): SemanticPackageOrigin {
        analysis.db.unwindIfCancelled()
        match (identity) {
            case Binary(_) => BinaryPackageOrigin
            case Source(pkg) where pkg.binary(analysis.db).isSome() => AttachedPackage
            case _ => if (isWorkspaceMember()) { WorkspacePackage } else { DependencyPackage }
        }
    }

    /** Detached source contexts attached to this binary; empty without loaded attachments. */
    public func attachedSources(): Array<SemanticPackage> {
        let db = analysis.db
        db.unwindIfCancelled()
        let binary = this.binary() ?? return []
        analysis
            .project()
            .getOrThrow()
            .packages()
            .filter {
                pkg =>
                pkg.identity != binary.identity &&
                    (pkg.binary().map { one => one.identity == binary.identity } ?? false)
            }
    }

    /**
     * Contextual files with loaded text; binaries expose their item-file identities.
     * Attached source enumerates its own files, never the editor-preferred physical context.
     */
    public func files(): Array<SemanticFile> {
        let db = analysis.db
        db.unwindIfCancelled()
        match (identity) {
            case Source(pkg) =>
                pkg.files(db) |> filterMap { id => db.sourceFile(id, context: pkg) } |>
                    map { file => SemanticFile(analysis, ItemFile.Source(file)) } |>
                    collectArray
            case Binary(_) => filesOf(db, identity).map { file => SemanticFile(analysis, file) }
        }
    }

    /** Source identities whose text is not loaded; empty for binaries. */
    public func unavailableFiles(): Array<FileId> {
        let db = analysis.db
        db.unwindIfCancelled()
        match (identity) {
            case Source(pkg) =>
                pkg.files(db).filter { id => db.sourceFile(id, context: pkg).isNone() }
            case Binary(_) => []
        }
    }

    /**
     * Packages permitted in this context, including self and std; these are not written
     * imports. Selection uses the same package index as semantic lookup.
     */
    public func permittedPackages(ofTests!: Bool = false): Array<SemanticPackage> {
        let db = analysis.db
        db.unwindIfCancelled()
        let index = packageIndex(db)
        let result = ArrayList<SemanticPackage>()
        for ((name, _) in index.packages) {
            if (let Some(pkg) <- index.find(name, from: identity, ofTests: ofTests)) {
                result.add(SemanticPackage(analysis, pkg))
            }
        }
        result.toArray()
    }

    /**
     * Conservative candidates allowed to depend on this package, including self and test
     * permissions. No claim about written imports or transitive use is made.
     */
    public func potentialDependents(): Array<SemanticPackage> {
        let db = analysis.db
        db.unwindIfCancelled()
        let canonical =
            match (identity) {
                case Source(pkg) => resolutionPackage(db, pkg)
                case _ => identity
            }
        analysis
            .project()
            .getOrThrow()
            .packages()
            .filter {
                one =>
                one
                    .permittedPackages(ofTests: true)
                    .iterator()
                    .any { pkg => pkg.identity == canonical }
            }
    }

    /**
     * Written paths with this resolved package target, even if a name is inaccessible.
     * Missing binary source import graphs are recorded in unavailablePackages, not
     * treated as no imports. Attached sources contribute only the loaded source evidence.
     */
    public func writtenImporters(stage!: ScopeStage = ScopeStage.Written): SemanticImporters {
        let db = analysis.db
        db.unwindIfCancelled()
        let target = binary().map { pkg => pkg.identity } ?? identity
        let result = ArrayList<SemanticImport>()
        let unavailable = ArrayList<SemanticPackage>()
        for (pkg in analysis.project().getOrThrow().packages()) {
            match (pkg.imports(stage: stage)) {
                case Some(imports) =>
                    if (!pkg.unavailableFiles().isEmpty()) {
                        unavailable.add(pkg)
                    }
                    result.add(
                        all: imports
                            .filter {
                                one =>
                                one.target.map { pkg => pkg.identity == target } ?? false
                            }
                    )
                case None => unavailable.add(pkg)
            }
        }
        SemanticImporters(result.toArray(), unavailable.toArray())
    }

    /**
     * Imports in loaded source text; unavailableFiles reports any omitted source inputs.
     * None for binary syntax, empty for loaded source with no active imports.
     */
    public func imports(stage!: ScopeStage = ScopeStage.Written): ?Array<SemanticImport> {
        analysis.db.unwindIfCancelled()
        if (let Binary(_) <- identity) {
            return None
        }
        Some(files().flatMap { file => file.imports(stage: stage) ?? [] })
    }

    /** Exports include re-export visibility. Cycles are explicit, not an empty success. */
    public func exports(stage!: ScopeStage = ScopeStage.Expanded): SemanticExports {
        let db = analysis.db
        db.unwindIfCancelled()
        let exports = exportsAt(db, identity, stage)
        let routes =
            (imports(stage: stage) ?? [])
                .filter { route => route.isReExport && !route.file.isTest() }
        let result = ArrayList<SemanticBinding>()
        for (map in [exports.names, exports.ctors]) {
            for ((name, defs) in map) {
                for (def in defs) {
                    let target = analysis.object(NamedIdentity(Definition.DeclDef(def.id)))
                    let sites =
                        routes
                            .filter {
                                route =>
                                route
                                    .names
                                    .iterator()
                                    .any {
                                        binding =>
                                        binding.name == name &&
                                            binding.target.identity == target.identity
                                    }
                            }
                    if (sites.isEmpty()) {
                        result.add(SemanticBinding(name, target, def.visibility, None, stage))
                    } else {
                        for (route in sites) {
                            result.add(
                                SemanticBinding(name, target, def.visibility, route.site, stage)
                            )
                        }
                    }
                }
            }
        }
        let available =
            match (identity) {
                case Binary(pkg) => !binaryItemTrees(db, pkg).isEmpty()
                case Source(pkg) =>
                    unavailableFiles().isEmpty() &&
                        (
                            pkg
                                .binary(db)
                                .map { binary => !binaryItemTrees(db, binary).isEmpty() } ??
                                true
                        )
            }
        SemanticExports(result.toArray(), exports.cyclic, available)
    }

    public func configuration(): ?SemanticConfiguration {
        let db = analysis.db
        db.unwindIfCancelled()
        match (identity) {
            case Source(pkg) where pkg.binary(db).isSome() =>
                Some(SemanticConfiguration(db.project().getOrThrow().cfg(db)))
            case Source(pkg) =>
                let base =
                    module().map { one => one.configuration().cfg } ??
                        db.project().getOrThrow().cfg(db)
                Some(
                    SemanticConfiguration(pkg.cfg(db).map { own => base.overriddenBy(own) } ?? base)
                )
            case Binary(_) => None
        }
    }
}

/** Reverse written-import evidence with explicit missing-source and binary graph gaps. */
public class SemanticImporters {
    SemanticImporters(
        public let entries: Array<SemanticImport>,
        public let unavailablePackages: Array<SemanticPackage>
    ) {}
}

extend SemanticObject {
    /** Context of the identity itself; never reconstructed through its navigation location. */
    public func contextualPackage(): ?SemanticPackage {
        let db = analysis.db
        db.unwindIfCancelled()
        if (let NamedIdentity(PackageDef(pkg)) <- identity) {
            return SemanticPackage(analysis, pkg)
        }
        let file = semanticIdentityFile(db, identity) ?? return None
        SemanticFile(analysis, file).contextualPackage()
    }
}

extend SemanticOccurrence {
    public func contextualFile(): SemanticFile {
        analysis.db.unwindIfCancelled()
        SemanticFile(analysis, location.file)
    }
}

extend SemanticLocation {
    public func contextualFile(): SemanticFile {
        analysis.db.unwindIfCancelled()
        SemanticFile(analysis, file)
    }
}

func semanticIdentityFile(db: AnalysisDatabase, identity: SemanticIdentity): ?ItemFile {
    match (identity) {
        case NamedIdentity(DeclDef(owner)) => owner.file(db)
        case NamedIdentity(LocalDef(owner, _)) => owner.file(db)
        case NamedIdentity(MemberParamDef(owner, _)) => owner.file(db)
        case NamedIdentity(TypeParamDef(GenericOf(owner, _))) => owner.file(db)
        case NamedIdentity(TypeParamDef(LocalGenericOf(owner, _, _))) => owner.file(db)
        case ExpressionIdentity(owner, _) => owner.file(db)
        case PatternIdentity(owner, _) => owner.file(db)
        case LocalIdentity(owner, _) => owner.file(db)
        case SignatureTypeIdentity(owner, _) => owner.file(db)
        case BodyTypeIdentity(owner, _) => owner.file(db)
        case _ => None
    }
}
