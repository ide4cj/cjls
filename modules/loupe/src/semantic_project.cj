package loupe

import std.collection.{ArrayList, collectArray, filterMap, map}
import py_interop.*
import py_interop.internal_macros.DerivePython
import loupe.db.{AnalysisDatabase, BinaryModel, Cfg, InactiveSourceFile, Module, NativeLibrary}
import loupe.hir.{
    DefId,
    ItemFile,
    PackageRef,
    ScopeStage,
    Visibility,
    binaryItemTrees,
    exportsAt,
    filesOf,
    nameOf,
    packageIndex,
    resolutionPackage
}
import loupe.vfs.{FileId, VfsPath}

@DerivePython
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
@DerivePython
public class SemanticProject {
    private let analysis: SemanticAnalysis

    @PyIgnore
    init(analysis: SemanticAnalysis) {
        this.analysis = analysis
    }

    @PyDoc["Return loaded source modules, including dependency modules."]
    public func modules(): Array<SemanticModule> {
        let db = analysis.db
        db.unwindIfCancelled()
        db
            .project()
            .getOrThrow { IllegalStateException("project inputs must be loaded") }
            .modules(db)
            .map { id => SemanticModule(analysis, id) }
    }

    /**
     * Source, binary and detached attached-source contexts, each identity once.
     */
    public func packages(): Array<SemanticPackage> {
        let db = analysis.db
        db.unwindIfCancelled()
        let project =
            db.project().getOrThrow { IllegalStateException("project inputs must be loaded") }
        let result = ArrayList(modules().flatMap { module => module.packages() })
        result.add(
            all: project
                .binaryPackages(db)
                .map { binary => SemanticPackage(analysis, PackageRef.Binary(binary)) }
        )
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

    @PyDoc["Return contextual files of the loaded project."]
    public func files(): Array<SemanticFile> {
        packages().flatMap { pkg => pkg.files() }
    }

    @PyDoc["Return module dependency edges, retaining ordinary and test-only permissions."]
    public func dependencies(): Array<SemanticDependency> {
        modules().flatMap { module => module.dependencies() }
    }

    /**
     * Selected loaded binary models; never enumerates their paths on disk.
     */
    public func binaries(): Array<BinaryModel> {
        let db = analysis.db
        db.unwindIfCancelled()
        db
            .project()
            .getOrThrow { IllegalStateException("project inputs must be loaded") }
            .binaries(db)
    }

    @PyDoc["Return the project configuration retained in the analysis inputs."]
    public func configuration(): SemanticConfiguration {
        let db = analysis.db
        db.unwindIfCancelled()
        SemanticConfiguration(
            db
                .project()
                .getOrThrow { IllegalStateException("project inputs must be loaded") }
                .cfg(db)
        )
    }
}

/**
 * Effective analysis conditions, not an exact compiler invocation. The loader does not
 * retain profile/feature/flag completeness, selection provenance, source-set names or load
 * diagnostics in database inputs. Unavailable metadata is separate from a known empty result.
 * Missing @When comparison keys remain unknown/active; absent debug/test flags currently
 * follow CfgExpr's false default, not proof that the compiler was invoked without them.
 */
@DerivePython
public struct SemanticConfiguration {
    SemanticConfiguration(public let cfg: Cfg) {}

    @PyDoc["None: loader problem details are not retained by this semantic view."]
    public prop loadingProblems: ?Array<String> {
        get() {
            None
        }
    }
    @PyDoc["None: configuration-selection provenance is not retained."]
    public prop selectionProvenance: ?String {
        get() {
            None
        }
    }
    @PyDoc["None: selected source-set names are not retained."]
    public prop selectedSourceSets: ?Array<String> {
        get() {
            None
        }
    }
    @PyDoc["False: retained analysis configuration is not a complete compiler invocation."]
    public prop hasCompleteCompilerInvocation: Bool {
        get() {
            false
        }
    }
}

/**
 * A dependency permission, not evidence of an import statement.
 */
@DerivePython
public struct SemanticDependency {
    SemanticDependency(
        public let source: SemanticModule,
        public let name: String,
        public let modules: Array<SemanticModule>,
        public let binaries: Array<BinaryModel>,
        public let isTestOnly!: Bool = false,
        public let isImplicit!: Bool = false
    ) {}

    /**
     * False distinguishes a missing selected target from an empty package collection.
     */
    public prop isResolved: Bool {
        get() {
            !modules.isEmpty() || !binaries.isEmpty()
        }
    }
}

/**
 * Module identity includes its independent resolution scope, including script selections.
 */
@DerivePython
public class SemanticModule {
    private let analysis: SemanticAnalysis
    public let identity: Module

    @PyIgnore
    init(analysis: SemanticAnalysis, identity: Module) {
        this.analysis = analysis
        this.identity = identity
    }

    @PyDoc["Return the module name from the loaded project."]
    public func name(): String {
        analysis.db.unwindIfCancelled()
        identity.name(analysis.db)
    }

    @PyDoc["Return the module root as a native VfsPath."]
    public func root(): VfsPath {
        analysis.db.unwindIfCancelled()
        identity.root(analysis.db)
    }

    /**
     * Native linker inputs selected for this module; these are separate from Cangjie dependencies.
     */
    public func nativeLibraries(): Array<NativeLibrary> {
        analysis.db.unwindIfCancelled()
        identity.nativeLibraries(analysis.db)
    }

    @PyDoc["Return its independent dependency-selection scope; empty for the ordinary graph."]
    public func resolutionScope(): String {
        analysis.db.unwindIfCancelled()
        identity.resolutionScope(analysis.db)
    }

    @PyDoc["Whether this module belongs to the workspace rather than its dependencies."]
    public func isWorkspaceMember(): Bool {
        analysis.db.unwindIfCancelled()
        identity.member(analysis.db)
    }

    @PyDoc["Return source packages belonging to this module."]
    public func packages(): Array<SemanticPackage> {
        analysis.db.unwindIfCancelled()
        identity
            .packages(analysis.db)
            .map { pkg => SemanticPackage(analysis, PackageRef.Source(pkg)) }
    }

    @PyDoc["Return module configuration, falling back to the project configuration."]
    public func configuration(): SemanticConfiguration {
        let db = analysis.db
        db.unwindIfCancelled()
        SemanticConfiguration(
            identity.cfg(db) ??
                db
                    .project()
                    .getOrThrow { IllegalStateException("project inputs must be loaded") }
                    .cfg(db)
        )
    }

    /**
     * Source-set exclusions retained by the loader, even when their text was not loaded.
     */
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
        let project =
            analysis.project().getOrThrow { IllegalStateException("project inputs must be loaded") }
        let modules = project.modules()
        let binaries = project.binaries()
        func dependency(
            name: String,
            isTestOnly!: Bool = false,
            isImplicit!: Bool = false
        ): SemanticDependency {
            SemanticDependency(
                this,
                name,
                modules
                    .filter {
                        one =>
                        one.name() == name &&
                            (
                                one.resolutionScope() == resolutionScope() ||
                                    (name == "std" && one.resolutionScope().isEmpty())
                            )
                    },
                binaries.filter { one => one.name == name },
                isTestOnly: isTestOnly,
                isImplicit: isImplicit
            )
        }
        let ordinary = identity.deps(db)
        let declared = ordinary
            .map { name => dependency(name) }
            .concat(identity.testDeps(db).map { name => dependency(name, isTestOnly: true) })
        if (ordinary.contains("std")) {
            declared
        } else {
            declared.concat([dependency("std", isImplicit: true)])
        }
    }
}

/**
 * Loaded origin, independent of a declaration's navigation source.
 */
@DerivePython
public enum SemanticPackageOrigin <: Equatable<SemanticPackageOrigin> {
    | WorkspacePackage
    | DependencyPackage
    | BinaryPackageOrigin
    | AttachedPackage

    public operator func ==(other: SemanticPackageOrigin): Bool {
        match ((this, other)) {
            case (SemanticPackageOrigin.WorkspacePackage, SemanticPackageOrigin.WorkspacePackage) =>
                true
            case (
                    SemanticPackageOrigin.DependencyPackage,
                    SemanticPackageOrigin.DependencyPackage
                ) => true
            case (
                    SemanticPackageOrigin.BinaryPackageOrigin,
                    SemanticPackageOrigin.BinaryPackageOrigin
                ) => true
            case (SemanticPackageOrigin.AttachedPackage, SemanticPackageOrigin.AttachedPackage) =>
                true
            case _ => false
        }
    }

    public operator func !=(other: SemanticPackageOrigin): Bool {
        !(this == other)
    }
}

/**
 * A contextual package. Attached source retains its detached identity, not its binary's.
 */
@DerivePython
public class SemanticPackage {
    @PyIgnore
    let analysis: SemanticAnalysis
    public let identity: PackageRef

    @PyIgnore
    init(analysis: SemanticAnalysis, identity: PackageRef) {
        this.analysis = analysis
        this.identity = identity
    }

    @PyDoc["Return the full package name in this lookup context."]
    public func name(): String {
        analysis.db.unwindIfCancelled()
        nameOf(analysis.db, identity)
    }

    @PyDoc["Return the semantic object representing this package."]
    public func object(): SemanticObject {
        analysis.db.unwindIfCancelled()
        analysis.object(SemanticIdentity.NamedIdentity(Definition.PackageDef(identity)))
    }

    @PyDoc["Return the owning source module, or None for a binary package."]
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

    @PyDoc["Return binary package metadata, or None for a source package."]
    public func binary(): ?SemanticPackage {
        let db = analysis.db
        db.unwindIfCancelled()
        match (identity) {
            case Source(pkg) =>
                pkg.binary(db).map { id => SemanticPackage(analysis, PackageRef.Binary(id)) }
            case Binary(_) => this
        }
    }

    @PyDoc["Whether this is a package of a workspace member module."]
    public func isWorkspaceMember(): Bool {
        module()?.isWorkspaceMember() ?? false
    }

    @PyDoc["Return the source, dependency, binary or built-in origin of this package."]
    public func origin(): SemanticPackageOrigin {
        analysis.db.unwindIfCancelled()
        match (identity) {
            case Binary(_) => BinaryPackageOrigin
            case Source(pkg) where pkg.binary(analysis.db).isSome() => AttachedPackage
            case _ => if (isWorkspaceMember()) { WorkspacePackage } else { DependencyPackage }
        }
    }

    /**
     * Detached source contexts attached to this binary; empty without loaded attachments.
     */
    public func attachedSources(): Array<SemanticPackage> {
        let db = analysis.db
        db.unwindIfCancelled()
        let binary = binary() ?? return []
        analysis
            .project()
            .getOrThrow { IllegalStateException("project inputs must be loaded") }
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

    /**
     * Source identities whose text is not loaded; empty for binaries.
     */
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
        index.packages |>
            filterMap { entry => index.find(entry[0], from: identity, ofTests: ofTests) } |>
            map { pkg => SemanticPackage(analysis, pkg) } |>
            collectArray
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
            .getOrThrow { IllegalStateException("project inputs must be loaded") }
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
        for (
            pkg in analysis
                .project()
                .getOrThrow { IllegalStateException("project inputs must be loaded") }
                .packages()
        ) {
            match (pkg.imports(stage: stage)) {
                case Some(imports) =>
                    if (!pkg.unavailableFiles().isEmpty()) {
                        unavailable.add(pkg)
                    }
                    result.add(all: imports.filter { one => one.target?.identity == Some(target) })
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

    /**
     * Exports include re-export visibility. Cycles are explicit, not an empty success.
     */
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
                    result.add(all: exportedBindings(name, def.id, def.visibility, routes, stage))
                }
            }
        }
        let isAvailable =
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
        SemanticExports(result.toArray(), isCyclic: exports.cyclic, isAvailable: isAvailable)
    }

    private func exportedBindings(
        name: String,
        id: DefId,
        visibility: Visibility,
        routes: Array<SemanticImport>,
        stage: ScopeStage
    ): Array<SemanticBinding> {
        let target = analysis.object(NamedIdentity(Definition.DeclDef(id)))
        let sites =
            routes
                .filter {
                    route =>
                    route
                        .names
                        .any {
                            binding =>
                            binding.name == name && binding.target.identity == target.identity
                        }
                }
        if (sites.isEmpty()) {
            [SemanticBinding(name, target, visibility, None, stage)]
        } else {
            sites.map { route => SemanticBinding(name, target, visibility, route.site, stage) }
        }
    }

    @PyDoc["Return the configuration available for this package, or None when unavailable."]
    public func configuration(): ?SemanticConfiguration {
        let db = analysis.db
        db.unwindIfCancelled()
        match (identity) {
            case Source(pkg) where pkg.binary(db).isSome() =>
                Some(
                    SemanticConfiguration(
                        db
                            .project()
                            .getOrThrow { IllegalStateException("project inputs must be loaded") }
                            .cfg(db)
                    )
                )
            case Source(pkg) =>
                let base =
                    module()?.configuration().cfg ??
                        db
                            .project()
                            .getOrThrow { IllegalStateException("project inputs must be loaded") }
                            .cfg(db)
                Some(
                    SemanticConfiguration(pkg.cfg(db).map { own => base.overriddenBy(own) } ?? base)
                )
            case Binary(_) => None
        }
    }
}

/**
 * Reverse written-import evidence with explicit missing-source and binary graph gaps.
 */
@DerivePython
public struct SemanticImporters {
    SemanticImporters(
        public let entries: Array<SemanticImport>,
        public let unavailablePackages: Array<SemanticPackage>
    ) {}
}

@DerivePython
extend SemanticObject {
    /**
     * Context of the identity itself; never reconstructed through its navigation location.
     */
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

@DerivePython
extend SemanticOccurrence {
    @PyDoc["Return the file with the lookup context of this occurrence."]
    public func contextualFile(): SemanticFile {
        analysis.db.unwindIfCancelled()
        SemanticFile(analysis, location.file)
    }
}

@DerivePython
extend SemanticLocation {
    @PyDoc["Return the file with the lookup context retained by this location."]
    public func contextualFile(): SemanticFile {
        analysis.db.unwindIfCancelled()
        SemanticFile(analysis, file)
    }
}

/**
 * The contextual item file owning an identity, absent for packages and built-ins.
 */
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
