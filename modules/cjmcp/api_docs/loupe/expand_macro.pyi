class ExpandedMacro:
    """
    
    What a macro call expands to, as the analysis reads it.
    
    """
    def __init__(self, __name: str, __range: TextRange, __text: str, __kind: ExpansionKind, *, declaration: str | None = ...):
        """
         for type TextRange, see 'ginkgo/text_range.pyi'
        """
        ...
    @property
    def name(self) -> str:
        ...
    @property
    def range(self) -> TextRange:
        """
         for type TextRange, see 'ginkgo/text_range.pyi'
        """
        ...
    @property
    def text(self) -> str:
        ...
    @property
    def kind(self) -> ExpansionKind:
        ...
    @property
    def declaration(self) -> str | None:
        ...
    def __eq__(self, __other: ExpandedMacro) -> bool:
        ...
    def __ne__(self, __other: ExpandedMacro) -> bool:
        ...
class MacroCallAt:
    """
    
    The macro call at a position (`macroCallAt`): the call whose expansion shows it, and where the call at the position
    is.
    
    """
    def __init__(self, __call: MacroCallId, __range: TextRange, *, focus: TextRange | None = ...):
        """
         for type TextRange, see 'ginkgo/text_range.pyi'
         for type MacroCallId, see 'loupe.hir/expansion.pyi'
        """
        ...
    @property
    def call(self) -> MacroCallId:
        """
         for type MacroCallId, see 'loupe.hir/expansion.pyi'
        """
        ...
    @property
    def range(self) -> TextRange:
        """
         for type TextRange, see 'ginkgo/text_range.pyi'
        """
        ...
    @property
    def focus(self) -> TextRange | None:
        """
         for type TextRange, see 'ginkgo/text_range.pyi'
        """
        ...
    def __eq__(self, __other: MacroCallAt) -> bool:
        ...
    def __ne__(self, __other: MacroCallAt) -> bool:
        ...
class ExpansionKind:
    """
    
    Who wrote an expansion.
    
    """
    def __repr__(self) -> str:
        ...
    def __eq__(self, __other: ExpansionKind) -> bool:
        ...
    def __ne__(self, __other: ExpansionKind) -> bool:
        ...
    kind: Literal['ServerExpansion'] | Literal['OwnExpansion']
    class ServerExpansion(ExpansionKind):
        kind: Literal['ServerExpansion'] = 'ServerExpansion'
        def __init__(self):
            ...
    class OwnExpansion(ExpansionKind):
        kind: Literal['OwnExpansion'] = 'OwnExpansion'
        def __init__(self):
            ...
