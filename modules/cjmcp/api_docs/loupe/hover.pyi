class HoverResult:
    """
    
    What hovering a name shows, rust-analyzer's `HoverResult`: the name's range, and what it stands
    for, each candidate of an ambiguity.
    
    """
    def __init__(self, __range: TextRange, __items: list[HoverItem]):
        """
         for type TextRange, see 'ginkgo/text_range.pyi'
        """
        ...
    @property
    def range(self) -> TextRange:
        """
         for type TextRange, see 'ginkgo/text_range.pyi'
        """
        ...
    @property
    def items(self) -> list[HoverItem]:
        ...
    def __eq__(self, __other: HoverResult) -> bool:
        ...
    def __ne__(self, __other: HoverResult) -> bool:
        ...
class HoverItem:
    """
    
    One thing a name stands for, as Cangjie writes it; no markup, which is the server's to choose.
    
    """
    def __init__(self, __code: str, *, path: str | None = ..., doc: str | None = ...):
        ...
    @property
    def code(self) -> str:
        ...
    @property
    def path(self) -> str | None:
        ...
    @property
    def doc(self) -> str | None:
        ...
    def __eq__(self, __other: HoverItem) -> bool:
        ...
    def __ne__(self, __other: HoverItem) -> bool:
        ...
