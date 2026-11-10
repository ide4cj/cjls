from typing import Literal

class SemanticProject:
    """
    Traversal of loaded inputs only. Collections preserve input order and support ordinary Array filtering. All methods use the originating snapshot and cancel after input changes.
    """
    def modules(self) -> list[SemanticModule]:
        """
        Return loaded source modules, including dependency modules.
        """
        ...
    def packages(self) -> list[SemanticPackage]:
        """
        Source, binary and detached attached-source contexts, each identity once.
        """
        ...
    def files(self) -> list[SemanticFile]:
        """
        Return contextual files of the loaded project.
         for type SemanticFile, see 'loupe/semantic_scope.pyi'
        """
        ...
    def dependencies(self) -> list[SemanticDependency]:
        """
        Return module dependency edges, retaining ordinary and test-only permissions.
        """
        ...
    def binaries(self) -> list[BinaryModel]:
        """
        Selected loaded binary models; never enumerates their paths on disk.
         for type BinaryModel, see 'loupe.db/project.pyi'
        """
        ...
    def configuration(self) -> SemanticConfiguration:
        """
        Return the project configuration retained in the analysis inputs.
        """
        ...
class SemanticConfiguration:
    """
    Effective analysis conditions, not an exact compiler invocation. The loader does not retain profile/feature/flag completeness, selection provenance, source-set names or load diagnostics in database inputs. Unavailable metadata is separate from a known empty result. Missing @When comparison keys remain unknown/active; absent debug/test flags currently follow CfgExpr's false default, not proof that the compiler was invoked without them.
    """
    def __init__(self, __cfg: Cfg):
        """
         for type Cfg, see 'loupe.db/project.pyi'
        """
        ...
    @property
    def cfg(self) -> Cfg:
        """
         for type Cfg, see 'loupe.db/project.pyi'
        """
        ...
    @property
    def loadingProblems(self) -> list[str] | None:
        """
        None: loader problem details are not retained by this semantic view.
        """
        ...
    @property
    def selectionProvenance(self) -> str | None:
        """
        None: configuration-selection provenance is not retained.
        """
        ...
    @property
    def selectedSourceSets(self) -> list[str] | None:
        """
        None: selected source-set names are not retained.
        """
        ...
    @property
    def hasCompleteCompilerInvocation(self) -> bool:
        """
        False: retained analysis configuration is not a complete compiler invocation.
        """
        ...
class SemanticDependency:
    """
    A dependency permission, not evidence of an import statement.
    """
    def __init__(self, __source: SemanticModule, __name: str, __modules: list[SemanticModule], __binaries: list[BinaryModel], *, isTestOnly: bool = ..., isImplicit: bool = ...):
        """
         for type BinaryModel, see 'loupe.db/project.pyi'
        """
        ...
    @property
    def source(self) -> SemanticModule:
        ...
    @property
    def name(self) -> str:
        ...
    @property
    def modules(self) -> list[SemanticModule]:
        ...
    @property
    def binaries(self) -> list[BinaryModel]:
        """
         for type BinaryModel, see 'loupe.db/project.pyi'
        """
        ...
    @property
    def isTestOnly(self) -> bool:
        ...
    @property
    def isImplicit(self) -> bool:
        ...
    @property
    def isResolved(self) -> bool:
        """
        False distinguishes a missing selected target from an empty package collection.
        """
        ...
class SemanticModule:
    """
    Module identity includes its independent resolution scope, including script selections.
    """
    @property
    def identity(self) -> Module:
        """
         for type Module, see 'loupe.db/project.pyi'
        """
        ...
    def name(self) -> str:
        """
        Return the module name from the loaded project.
        """
        ...
    def root(self) -> VfsPath:
        """
        Return the module root as a native VfsPath.
         for type VfsPath, see 'loupe.vfs/path.pyi'
        """
        ...
    def nativeLibraries(self) -> list[NativeLibrary]:
        """
        Return this module's selected native linker names and search directories.
         for type NativeLibrary, see 'loupe.db/project.pyi'
        """
        ...
    def resolutionScope(self) -> str:
        """
        Return its independent dependency-selection scope; empty for the ordinary graph.
        """
        ...
    def isWorkspaceMember(self) -> bool:
        """
        Whether this module belongs to the workspace rather than its dependencies.
        """
        ...
    def packages(self) -> list[SemanticPackage]:
        """
        Return source packages belonging to this module.
        """
        ...
    def configuration(self) -> SemanticConfiguration:
        """
        Return module configuration, falling back to the project configuration.
        """
        ...
    def inactiveFiles(self) -> list[InactiveSourceFile]:
        """
        Source-set exclusions retained by the loader, even when their text was not loaded.
         for type InactiveSourceFile, see 'loupe.db/project.pyi'
        """
        ...
    def dependencies(self) -> list[SemanticDependency]:
        """
        Direct ordinary and additional test-only edges, plus implicit std. Script edges retain their module's resolutionScope; downstream modules do not inherit test-only permissions.
        """
        ...
class SemanticPackageOrigin:
    """
    Loaded origin, independent of a declaration's navigation source.
    """
    def __eq__(self, __other: SemanticPackageOrigin) -> bool:
        ...
    def __ne__(self, __other: SemanticPackageOrigin) -> bool:
        ...
    kind: Literal['WorkspacePackage', 'DependencyPackage', 'BinaryPackageOrigin', 'AttachedPackage']
    class WorkspacePackage(SemanticPackageOrigin):
        kind: Literal['WorkspacePackage'] = 'WorkspacePackage'
        def __init__(self):
            ...
    class DependencyPackage(SemanticPackageOrigin):
        kind: Literal['DependencyPackage'] = 'DependencyPackage'
        def __init__(self):
            ...
    class BinaryPackageOrigin(SemanticPackageOrigin):
        kind: Literal['BinaryPackageOrigin'] = 'BinaryPackageOrigin'
        def __init__(self):
            ...
    class AttachedPackage(SemanticPackageOrigin):
        kind: Literal['AttachedPackage'] = 'AttachedPackage'
        def __init__(self):
            ...
class SemanticPackage:
    """
    A contextual package. Attached source retains its detached identity, not its binary's.
    """
    @property
    def identity(self) -> PackageRef:
        """
         for type PackageRef, see 'loupe.hir/def_map.pyi'
        """
        ...
    def name(self) -> str:
        """
        Return the full package name in this lookup context.
        """
        ...
    def object(self) -> SemanticObject:
        """
        Return the semantic object representing this package.
         for type SemanticObject, see 'loupe/semantic.pyi'
        """
        ...
    def module(self) -> SemanticModule | None:
        """
        Return the owning source module, or None for a binary package.
        """
        ...
    def binary(self) -> SemanticPackage | None:
        """
        Return binary package metadata, or None for a source package.
        """
        ...
    def isWorkspaceMember(self) -> bool:
        """
        Whether this is a package of a workspace member module.
        """
        ...
    def origin(self) -> SemanticPackageOrigin:
        """
        Return the source, dependency, binary or built-in origin of this package.
        """
        ...
    def attachedSources(self) -> list[SemanticPackage]:
        """
        Detached source contexts attached to this binary; empty without loaded attachments.
        """
        ...
    def files(self) -> list[SemanticFile]:
        """
        Contextual files with loaded text; binaries expose their item-file identities. Attached source enumerates its own files, never the editor-preferred physical context.
         for type SemanticFile, see 'loupe/semantic_scope.pyi'
        """
        ...
    def unavailableFiles(self) -> list[FileId]:
        """
        Source identities whose text is not loaded; empty for binaries.
         for type FileId, see 'loupe.vfs/vfs.pyi'
        """
        ...
    def permittedPackages(self, *, ofTests: bool = ...) -> list[SemanticPackage]:
        """
        Packages permitted in this context, including self and std; these are not written imports. Selection uses the same package index as semantic lookup.
        """
        ...
    def potentialDependents(self) -> list[SemanticPackage]:
        """
        Conservative candidates allowed to depend on this package, including self and test permissions. No claim about written imports or transitive use is made.
        """
        ...
    def writtenImporters(self, *, stage: ScopeStage = ...) -> SemanticImporters:
        """
        Written paths with this resolved package target, even if a name is inaccessible. Missing binary source import graphs are recorded in unavailablePackages, not treated as no imports. Attached sources contribute only the loaded source evidence.
         for type ScopeStage, see 'loupe.hir/def_map.pyi'
        """
        ...
    def imports(self, *, stage: ScopeStage = ...) -> list[SemanticImport] | None:
        """
        Imports in loaded source text; unavailableFiles reports any omitted source inputs. None for binary syntax, empty for loaded source with no active imports.
         for type SemanticImport, see 'loupe/semantic_scope.pyi'
         for type ScopeStage, see 'loupe.hir/def_map.pyi'
        """
        ...
    def exports(self, *, stage: ScopeStage = ...) -> SemanticExports:
        """
        Exports include re-export visibility. Cycles are explicit, not an empty success.
         for type SemanticExports, see 'loupe/semantic_scope.pyi'
         for type ScopeStage, see 'loupe.hir/def_map.pyi'
        """
        ...
    def configuration(self) -> SemanticConfiguration | None:
        """
        Return the configuration available for this package, or None when unavailable.
        """
        ...
class SemanticImporters:
    """
    Reverse written-import evidence with explicit missing-source and binary graph gaps.
    """
    def __init__(self, __entries: list[SemanticImport], __unavailablePackages: list[SemanticPackage]):
        """
         for type SemanticImport, see 'loupe/semantic_scope.pyi'
        """
        ...
    @property
    def entries(self) -> list[SemanticImport]:
        """
         for type SemanticImport, see 'loupe/semantic_scope.pyi'
        """
        ...
    @property
    def unavailablePackages(self) -> list[SemanticPackage]:
        ...
