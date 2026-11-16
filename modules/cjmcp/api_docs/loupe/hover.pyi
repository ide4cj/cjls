from typing import Literal

class HoverResult:
    """
    What hovering a name shows, rust-analyzer's `HoverResult`: the name's range, and what it stands for, each candidate of an ambiguity.
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
        """
        Its declaration as one line of Cangjie, no body: `public func get(index: Int64): ?Int64`, `let x: Int64`, `x: Int64` for a parameter; its types as inference gives them (D54, D55), a member's as a member of the value it is used on (`T` an argument of the value's type).
        """
        ...
    @property
    def path(self) -> str | None:
        """
        Where it is declared: its package, and the type it is a member of (`std.collection.ArrayList`); `None` for a local.
        """
        ...
    @property
    def doc(self) -> str | None:
        """
        Its doc comment, its text as written, the comment's own markers taken off (`docText`); of what the language builds in, our words of it (`BuiltinDoc`).
        """
        ...
    def __eq__(self, __other: HoverItem) -> bool:
        ...
    def __ne__(self, __other: HoverItem) -> bool:
        ...
