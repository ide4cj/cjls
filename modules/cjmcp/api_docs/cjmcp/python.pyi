class Workspace:
    """
    
    A script-scoped view of the session workspace; reload queues preparation after the script.
    
    """
    def __init__(self, __directory: str):
        ...
    @property
    def revision(self) -> int:
        ...
    @property
    def root(self) -> str:
        ...
    @property
    def loadDiagnostics(self) -> list[WorkspaceDiagnostic]:
        """
         for type WorkspaceDiagnostic, see 'cjmcp/diagnostics.pyi'
        """
        ...
    @property
    def macros(self) -> MacroStatus:
        """
         for type MacroStatus, see 'cjmcp/diagnostics.pyi'
        """
        ...
    def files(self) -> list[str]:
        ...
    def applyChange(self, __change: SourceChange, __revision: int) -> ApplyChangeResult:
        """
        
        Apply a source change to disk, checking this script's revision and all expected contents.
        The running analysis remains unchanged; acquire fresh analysis in the next call.
        
        @throws IllegalStateException - if revision does not match the running script
        
         for type ApplyChangeResult, see 'cjmcp/source_change.pyi'
         for type SourceChange, see 'source_change/source_change.pyi'
        """
        ...
    def reload(self) -> None:
        ...
    def structure(self, __path: str) -> list[StructureNode]:
        """
         for type StructureNode, see 'loupe/structure.pyi'
        """
        ...
    def diagnostics(self, __path: str) -> list[WorkspaceDiagnostic]:
        """
         for type WorkspaceDiagnostic, see 'cjmcp/diagnostics.pyi'
        """
        ...
    def hover(self, __path: str, __offset: int) -> HoverResult | None:
        """
         for type HoverResult, see 'loupe/hover.pyi'
        """
        ...
    def definition(self, __path: str, __offset: int) -> list[PythonLocation]:
        ...
    def analysis(self) -> AnalysisRevision:
        """
        
        Capture this script's revision. Reacquire after a later workspace update.
        
         for type AnalysisRevision, see 'cjmcp/analysis.pyi'
        """
        ...
class PythonLocation:
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
