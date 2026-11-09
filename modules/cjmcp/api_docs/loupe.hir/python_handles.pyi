class PythonBodySource:
    """
    
    File-qualified source adapter: the generic syntax pointer stays inside loupe.
    
    """
    @property
    def range(self) -> TextRange:
        """
         for type TextRange, see 'ginkgo/text_range.pyi'
        """
        ...
    @property
    def kind(self) -> str:
        ...
    @property
    def expansion(self) -> MacroCallId | None:
        """
         for type MacroCallId, see 'loupe.hir/expansion.pyi'
        """
        ...
