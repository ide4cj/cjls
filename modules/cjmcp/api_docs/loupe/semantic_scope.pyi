from typing import Literal

class SemanticFile:
    """

    File identity retains ordinary/test/script, attachment and expansion context.

    """
    @property
    def identity(self) -> ItemFile:
        """
         for type ItemFile, see 'loupe.hir/binary.pyi'
        """
        ...
    def contextualPackage(self) -> SemanticPackage | None:
        """
        Return the package used to resolve names in this file, or None when unavailable.
         for type SemanticPackage, see 'loupe/semantic_project.pyi'
        """
        ...
    def at(self, __offset: int) -> SemanticOccurrence | None:
        """
        Find a semantic occurrence at a UTF-8 byte offset in this contextual file.
         for type SemanticOccurrence, see 'loupe/semantic.pyi'
        """
        ...
    def isTest(self) -> bool:
        """
        Whether this file is analyzed with its package test-import permissions.
        """
        ...
    def configuration(self) -> SemanticConfiguration | None:
        """
        Return this source context configuration, or None when unavailable.
         for type SemanticConfiguration, see 'loupe/semantic_project.pyi'
        """
        ...
    def imports(self, *, stage: ScopeStage = ...) -> list[SemanticImport] | None:
        """

        Written-stage reads this file only; expanded-stage also includes its expansion imports.
        Target resolution reads exports at the requested stage. Unresolved paths retain errors.
        Binary source syntax is unavailable even if its compiled item tree has no imports.

         for type ScopeStage, see 'loupe.hir/def_map.pyi'
        """
        ...
    def implicitImports(self) -> list[SemanticImplicitImport] | None:
        """
        Return prelude and test imports; None means the source context is unavailable.
        """
        ...
    def visibleNames(self, *, stage: ScopeStage = ...) -> list[SemanticBinding] | None:
        """

        Package/file scope candidates, excluding lexical locals and members. Separate entries
        preserve competing import routes; lookup(name, namespace) applies semantic precedence.

         for type ScopeStage, see 'loupe.hir/def_map.pyi'
        """
        ...
    def lookup(self, __name: str, __namespace: Namespace) -> Resolution | None:
        """

        Exact package/file lookup, preserving ambiguity through the existing Resolution value.

         for type Resolution, see 'loupe.hir/scope.pyi'
         for type Namespace, see 'loupe.hir/scope.pyi'
        """
        ...
    def conditions(self) -> list[SemanticCondition] | None:
        """

        All written @When conditions, including nested and unknown ones, with revision text.

        """
        ...
    def whenStatus(self) -> WhenDiagnostics | None:
        """

        Outermost inactive ranges and invalid-condition diagnostics; none without source text.

         for type WhenDiagnostics, see 'loupe.hir/when.pyi'
        """
        ...
class SemanticCondition:
    """

    Condition evidence includes unknown evaluations independently of loaded-active filtering.

    """
    def __init__(self, __location: SemanticLocation, __expression: CfgExpr, __evaluation: bool | None, __reasons: list[str]):
        """
         for type CfgExpr, see 'loupe.hir/when.pyi'
         for type SemanticLocation, see 'loupe/semantic.pyi'
        """
        ...
    @property
    def location(self) -> SemanticLocation:
        """
         for type SemanticLocation, see 'loupe/semantic.pyi'
        """
        ...
    @property
    def expression(self) -> CfgExpr:
        """
         for type CfgExpr, see 'loupe.hir/when.pyi'
        """
        ...
    @property
    def evaluation(self) -> bool | None:
        ...
    @property
    def reasons(self) -> list[str]:
        ...
class SemanticExports:
    """

    Export cycles are distinct from a known empty exported-name collection.

    """
    def __init__(self, __names: list[SemanticBinding], *, isCyclic: bool, isAvailable: bool):
        ...
    @property
    def names(self) -> list[SemanticBinding]:
        ...
    @property
    def isCyclic(self) -> bool:
        ...
    @property
    def isAvailable(self) -> bool:
        """

        False for unloaded source inputs or an unreadable binary; names may be partial.

        """
        ...
class SemanticBinding:
    """

    A name and its semantic target; site retains the available immediate import provenance.

    """
    def __init__(self, __name: str, __target: SemanticObject, __visibility: Visibility, __site: ImportSite | None, __stage: ScopeStage, *, implicitImport: SemanticImplicitImport | None = ...):
        """
         for type ScopeStage, see 'loupe.hir/def_map.pyi'
         for type Visibility, see 'loupe.hir/def_map.pyi'
         for type ImportSite, see 'loupe.hir/scope.pyi'
         for type SemanticObject, see 'loupe/semantic.pyi'
        """
        ...
    @property
    def name(self) -> str:
        ...
    @property
    def target(self) -> SemanticObject:
        """
         for type SemanticObject, see 'loupe/semantic.pyi'
        """
        ...
    @property
    def visibility(self) -> Visibility:
        """
         for type Visibility, see 'loupe.hir/def_map.pyi'
        """
        ...
    @property
    def site(self) -> ImportSite | None:
        """
         for type ImportSite, see 'loupe.hir/scope.pyi'
        """
        ...
    @property
    def stage(self) -> ScopeStage:
        """
         for type ScopeStage, see 'loupe.hir/def_map.pyi'
        """
        ...
    @property
    def implicitImport(self) -> SemanticImplicitImport | None:
        ...
class SemanticImport:
    """

    One active import path, its alias/glob, visibility, stage and contextual syntax site.

    """
    def __init__(self, __file: SemanticFile, __path: ImportPath, __site: ImportSite, __stage: ScopeStage, __target: SemanticPackage | None, __names: list[SemanticBinding], __error: ImportError | None):
        """
         for type ImportError, see 'loupe.hir/imports.pyi'
         for type ScopeStage, see 'loupe.hir/def_map.pyi'
         for type ImportSite, see 'loupe.hir/scope.pyi'
         for type SemanticPackage, see 'loupe/semantic_project.pyi'
         for type ImportPath, see 'loupe.hir/item_tree.pyi'
        """
        ...
    @property
    def file(self) -> SemanticFile:
        ...
    @property
    def path(self) -> ImportPath:
        """
         for type ImportPath, see 'loupe.hir/item_tree.pyi'
        """
        ...
    @property
    def site(self) -> ImportSite:
        """
         for type ImportSite, see 'loupe.hir/scope.pyi'
        """
        ...
    @property
    def stage(self) -> ScopeStage:
        """
         for type ScopeStage, see 'loupe.hir/def_map.pyi'
        """
        ...
    @property
    def target(self) -> SemanticPackage | None:
        """
         for type SemanticPackage, see 'loupe/semantic_project.pyi'
        """
        ...
    @property
    def names(self) -> list[SemanticBinding]:
        ...
    @property
    def error(self) -> ImportError | None:
        """
         for type ImportError, see 'loupe.hir/imports.pyi'
        """
        ...
    @property
    def isReExport(self) -> bool:
        """
        Whether this written import re-exports its targets.
        """
        ...
    def location(self) -> SemanticLocation | None:
        """

        Exact import declaration when syntax is available; site.path indexes grouped paths.

         for type SemanticLocation, see 'loupe/semantic.pyi'
        """
        ...
class SemanticImplicitImport:
    """

    An implicit glob kept separate from written imports and dependency permissions.

    """
    def __init__(self, __target: SemanticPackage, *, isTestImport: bool):
        """
         for type SemanticPackage, see 'loupe/semantic_project.pyi'
        """
        ...
    @property
    def target(self) -> SemanticPackage:
        """
         for type SemanticPackage, see 'loupe/semantic_project.pyi'
        """
        ...
    @property
    def isTestImport(self) -> bool:
        ...
