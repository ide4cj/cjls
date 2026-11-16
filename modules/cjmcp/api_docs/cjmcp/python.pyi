from typing import Literal

class Workspace:
    """
    A script-scoped view of the session workspace; reload queues preparation after the script.
    """
    def __init__(self, __directory: str):
        ...
    @property
    def revision(self) -> int:
        """
        The session-local revision prepared for this script.
        """
        ...
    @property
    def root(self) -> str:
        """
        The canonical absolute root directory selected for this workspace session.
        """
        ...
    @property
    def loadDiagnostics(self) -> list[WorkspaceDiagnostic]:
        """
        Structured project, binary and source loading diagnostics for this preparation.
         for type WorkspaceDiagnostic, see 'cjmcp/diagnostics.pyi'
        """
        ...
    @property
    def sdk(self) -> CangjieHome | None:
        """
        The SDK used to prepare this revision, or None when no SDK was found. Reading it never reruns discovery.
         for type CangjieHome, see 'project_model/sdk.pyi'
        """
        ...
    @property
    def macros(self) -> MacroStatus:
        """
        Macro preparation state and diagnostics; settled does not imply success.
         for type MacroStatus, see 'cjmcp/diagnostics.pyi'
        """
        ...
    def files(self) -> list[str]:
        """
        Return loaded source paths, including dependencies.
        """
        ...
    def applyChange(self, __change: SourceChange, __revision: int) -> ApplyChangeResult:
        """
        Apply a source change to disk, checking this script's revision and all expected contents. The running analysis remains unchanged; acquire fresh analysis in the next call.  @throws IllegalStateException - if revision does not match the running script
         for type ApplyChangeResult, see 'cjmcp/source_change.pyi'
         for type SourceChange, see 'source_change/source_change.pyi'
        """
        ...
    def reload(self) -> None:
        """
        Queue preparation after the current script; retained analysis is unchanged during this call.
        """
        ...
    def structure(self, __path: str) -> list[StructureNode]:
        """
        Return source structure nodes for a loaded path.
         for type StructureNode, see 'loupe/structure.pyi'
        """
        ...
    def diagnostics(self, __path: str) -> list[WorkspaceDiagnostic]:
        """
        Return located diagnostics for a loaded path in this revision.
         for type WorkspaceDiagnostic, see 'cjmcp/diagnostics.pyi'
        """
        ...
    def hover(self, __path: str, __offset: int) -> HoverResult | None:
        """
        Return hover information at a UTF-8 byte offset, or None when absent.
         for type HoverResult, see 'loupe/hover.pyi'
        """
        ...
    def definition(self, __path: str, __offset: int) -> list[Location]:
        """
        Return definition targets with UTF-8 declaration and selection ranges.
        """
        ...
    def analysis(self) -> AnalysisRevision:
        """
        Capture this script's revision. Reacquire after a later workspace update.
         for type AnalysisRevision, see 'cjmcp/analysis.pyi'
        """
        ...
class Location:
    """
    A definition target: source path, full declaration range and selection range in UTF-8 bytes.
    """
    def __init__(self, __path: str, __range: TextRange, __selectionRange: TextRange):
        """
         for type TextRange, see 'ginkgo/text_range.pyi'
        """
        ...
    @property
    def path(self) -> str:
        ...
    @property
    def range(self) -> TextRange:
        """
         for type TextRange, see 'ginkgo/text_range.pyi'
        """
        ...
    @property
    def selectionRange(self) -> TextRange:
        """
         for type TextRange, see 'ginkgo/text_range.pyi'
        """
        ...
