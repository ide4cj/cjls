from typing import Literal

class ExpandedFile:
    """

    A source file with its macro calls expanded, as cjc's `--debug-macro` writes a `.cj.macrocall`; and where each of
    its pieces comes from.

    """
    def __init__(self, __text: str, __segments: list[ExpandedSegment]):
        ...
    @property
    def text(self) -> str:
        ...
    @property
    def segments(self) -> list[ExpandedSegment]:
        ...
    def placeOf(self, __offset: int) -> ExpandedPlace | None:
        """

        What `offset` is at: the piece it is in, or the one it ends; `None` in what the analysis wrote.

        """
        ...
    def fromSource(self, __range: TextRange) -> TextRange | None:
        """

        Where `range` of the source file is here, if it was copied whole into one piece.

         for type TextRange, see 'ginkgo/text_range.pyi'
        """
        ...
    def fromExpansion(self, __call: MacroCallId, __range: TextRange) -> TextRange | None:
        """

        Where `range` of the text of the expansion of `call` (`expandedMacro`) is here, if the file shows it.

         for type TextRange, see 'ginkgo/text_range.pyi'
         for type MacroCallId, see 'loupe.hir/expansion.pyi'
        """
        ...
    def expansionOf(self, __call: MacroCallId) -> TextRange | None:
        """

        Where the expansion of `call` is here, if the file shows it.

         for type TextRange, see 'ginkgo/text_range.pyi'
         for type MacroCallId, see 'loupe.hir/expansion.pyi'
        """
        ...
class ExpandedOrigin:
    """

    Where a piece of an expanded file (`expandFile`) comes from.

    """
    ...
    kind: Literal['Written', 'Copied', 'Shown']
    class Written(ExpandedOrigin):
        kind: Literal['Written'] = 'Written'
        def __init__(self):
            ...
    class Copied(ExpandedOrigin):
        kind: Literal['Copied'] = 'Copied'
        def __init__(self, __p1: int):
            ...
        @property
        def field0(self) -> int:
            ...
        __match_args__ = ('field0')
    class Shown(ExpandedOrigin):
        kind: Literal['Shown'] = 'Shown'
        def __init__(self, __p1: MacroCallId, __p2: ShownExpansion):
            """
             for type MacroCallId, see 'loupe.hir/expansion.pyi'
            """
            ...
        @property
        def field0(self) -> MacroCallId:
            ...
        @property
        def field1(self) -> ShownExpansion:
            ...
        __match_args__ = ('field0', 'field1')
class ShownExpansion:
    """

    The text of an expansion as a reader is shown it: formatted by cjformat, which changes whitespace only (D150), its
    trailing whitespace left out; as the macro wrote it if it does not format. Its bytes that are not whitespace are
    those of the text the macro wrote (`expandedMacro`), in order: that is how an offset goes from one to the other.

    """
    @staticmethod
    def of(__written: str) -> ShownExpansion:
        """
        Format expansion text only when token correspondence is preserved; otherwise retain trimmed written text.
        """
        ...
    def toWritten(self, __offset: int) -> int:
        """

        The offset of the written text that `offset` of the shown text is at.

        """
        ...
    def fromWritten(self, __offset: int) -> int:
        """

        The offset of the shown text that `offset` of the written text is at.

        """
        ...
    def fromWritten(self, __range: TextRange) -> TextRange:
        """
        Map a UTF-8 offset or range in written expansion text to its displayed text.
         for type TextRange, see 'ginkgo/text_range.pyi'
        """
        ...
class ExpandedSegment:
    """

    A UTF-8 range in expanded text and the source or expansion that contributed it.

    """
    def __init__(self, __range: TextRange, __origin: ExpandedOrigin):
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
    def origin(self) -> ExpandedOrigin:
        ...
class ExpandedPlace:
    """

    What an offset of an expanded file is at: an offset of its source file, or one of the text of an expansion
    (`expandedMacro`).

    """
    ...
    kind: Literal['InSource', 'InExpansion']
    class InSource(ExpandedPlace):
        kind: Literal['InSource'] = 'InSource'
        def __init__(self, __p1: int):
            ...
        @property
        def field0(self) -> int:
            ...
        __match_args__ = ('field0')
    class InExpansion(ExpandedPlace):
        kind: Literal['InExpansion'] = 'InExpansion'
        def __init__(self, __p1: MacroCallId, __p2: int):
            """
             for type MacroCallId, see 'loupe.hir/expansion.pyi'
            """
            ...
        @property
        def field0(self) -> MacroCallId:
            ...
        @property
        def field1(self) -> int:
            ...
        __match_args__ = ('field0', 'field1')
