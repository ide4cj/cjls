from typing import Literal

class MacroDiagnostic:
    """
    What a macro reported running a call: where in its input (`None` for no token of it), and what.
    """
    def __init__(self, __severity: MacroSeverity, __origin: SpanOrigin | None, __message: str, __hint: str):
        ...
    @property
    def severity(self) -> MacroSeverity:
        ...
    @property
    def origin(self) -> SpanOrigin | None:
        ...
    @property
    def message(self) -> str:
        ...
    @property
    def hint(self) -> str:
        ...
    def __eq__(self, __other: MacroDiagnostic) -> bool:
        ...
    def __ne__(self, __other: MacroDiagnostic) -> bool:
        ...
class MacroSeverity:
    """
    How bad what a macro reports is (`diagReport`'s `DiagReportLevel`).
    """
    def __eq__(self, __other: MacroSeverity) -> bool:
        ...
    def __ne__(self, __other: MacroSeverity) -> bool:
        ...
    kind: Literal['MacroError', 'MacroWarning']
    class MacroError(MacroSeverity):
        kind: Literal['MacroError'] = 'MacroError'
        def __init__(self):
            ...
    class MacroWarning(MacroSeverity):
        kind: Literal['MacroWarning'] = 'MacroWarning'
        def __init__(self):
            ...
class MacroItem:
    """
    One `setItem` of a macro call: its key and value.
    """
    def __init__(self, __key: str, __value: MacroItemValue):
        ...
    @property
    def key(self) -> str:
        ...
    @property
    def value(self) -> MacroItemValue:
        ...
    def __repr__(self) -> str:
        ...
    def __eq__(self, __other: MacroItem) -> bool:
        ...
    def __ne__(self, __other: MacroItem) -> bool:
        ...
class MappedSpan:
    """
    A range of a `MappedText` and where it comes from.
    """
    def __init__(self, __range: TextRange, __origin: SpanOrigin):
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
    def origin(self) -> SpanOrigin:
        ...
    def __repr__(self) -> str:
        ...
    def __eq__(self, __other: MappedSpan) -> bool:
        ...
    def __ne__(self, __other: MappedSpan) -> bool:
        ...
class SpanOrigin:
    """
    Where a piece of a macro call's input or output comes from (#176).
    """
    def __repr__(self) -> str:
        ...
    def __eq__(self, __other: SpanOrigin) -> bool:
        ...
    def __ne__(self, __other: SpanOrigin) -> bool:
        ...
    kind: Literal['FromSource', 'FromCall']
    class FromSource(SpanOrigin):
        kind: Literal['FromSource'] = 'FromSource'
        def __init__(self, __p1: TextRange):
            """
             for type TextRange, see 'ginkgo/text_range.pyi'
            """
            ...
        @property
        def field0(self) -> TextRange:
            ...
        __match_args__ = ('field0')
    class FromCall(SpanOrigin):
        kind: Literal['FromCall'] = 'FromCall'
        def __init__(self):
            ...
class MappedText:
    """
    Text a macro call reads or writes, and where its pieces come from: spans in order, not overlapping; text in none of them (the spaces between printed tokens) comes from nowhere.
    """
    def __init__(self, __text: str, __spans: list[MappedSpan]):
        ...
    @property
    def text(self) -> str:
        ...
    @property
    def spans(self) -> list[MappedSpan]:
        ...
    @staticmethod
    def fromSource(__text: str, __origin: int) -> MappedText:
        """
        Text all of which comes from the source at `origin`, relative to the top-level item, as one span.
        """
        ...
    def originOf(self, __range: TextRange) -> SpanOrigin | None:
        """
        Where `range` of the text comes from: the origin of the span its start is in; within a span as long as its origin (text copied from the source), the same part of it. `None` for text in no span.
         for type TextRange, see 'ginkgo/text_range.pyi'
        """
        ...
    def __eq__(self, __other: MappedText) -> bool:
        ...
    def __ne__(self, __other: MappedText) -> bool:
        ...
class MacroItemValue:
    """
    A value a macro gives the macro calls around it (`setItem`, which they read with `getChildMessages`).
    """
    def __repr__(self) -> str:
        ...
    def __eq__(self, __other: MacroItemValue) -> bool:
        ...
    def __ne__(self, __other: MacroItemValue) -> bool:
        ...
    kind: Literal['StringItem', 'IntItem', 'BoolItem', 'TokensItem']
    class StringItem(MacroItemValue):
        kind: Literal['StringItem'] = 'StringItem'
        def __init__(self, __p1: str):
            ...
        @property
        def field0(self) -> str:
            ...
        __match_args__ = ('field0')
    class IntItem(MacroItemValue):
        kind: Literal['IntItem'] = 'IntItem'
        def __init__(self, __p1: int):
            ...
        @property
        def field0(self) -> int:
            ...
        __match_args__ = ('field0')
    class BoolItem(MacroItemValue):
        kind: Literal['BoolItem'] = 'BoolItem'
        def __init__(self, __p1: bool):
            ...
        @property
        def field0(self) -> bool:
            ...
        __match_args__ = ('field0')
    class TokensItem(MacroItemValue):
        kind: Literal['TokensItem'] = 'TokensItem'
        def __init__(self, __p1: MappedText):
            ...
        @property
        def field0(self) -> MappedText:
            ...
        __match_args__ = ('field0')
