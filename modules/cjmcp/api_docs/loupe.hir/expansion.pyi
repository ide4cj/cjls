class CalcaFields_MacroCallId:
    ...
class MacroCallId:
    """
    
    A macro called in a source file, interned: the file and the item, and which of its calls. On the item (#175), the
    macro among those called on it, outermost first (`index` in `Item.macros`), or on one of its parameters, after
    those (`macroCallChainsOf`, D119), `inBody` `None`. In it, in a body or an initializer (D117), the macro's name as
    written (`inBody`) and its ordinal among the calls of that name there (`index`), in the order their `@`s are
    written. What a call on an item adds is `ItemFile.Expansion` of it.
    
    """
    ...
class ExpansionOrigin:
    """
    
    What written in a macro call an item of its expansion comes from, where go to definition goes for it or a member
    of it.
    
    """
    def __eq__(self, __other: ExpansionOrigin) -> bool:
        ...
    def __ne__(self, __other: ExpansionOrigin) -> bool:
        ...
    kind: Literal['OfEntry'] | Literal['OfMacro'] | Literal['OfName'] | Literal['OfOption']
    class OfEntry(ExpansionOrigin):
        kind: Literal['OfEntry'] = 'OfEntry'
        def __init__(self, __p1: int):
            ...
        @readonly
        field0: int
        __match_args__ = ('field0')
    class OfMacro(ExpansionOrigin):
        kind: Literal['OfMacro'] = 'OfMacro'
        def __init__(self):
            ...
    class OfName(ExpansionOrigin):
        kind: Literal['OfName'] = 'OfName'
        def __init__(self):
            ...
    class OfOption(ExpansionOrigin):
        kind: Literal['OfOption'] = 'OfOption'
        def __init__(self):
            ...
class Expansion:
    """
    
    What a macro call adds after its item, as text cjsyntax parses: declarations, signatures alone, each body a comment
    (`stubBody`); for each item of it in order, what written in the call it comes from; and whether it replaces the
    item the call is on, which then declares nothing (`@Strategy`'s function, whose body stays in a lambda of the `let`
    it becomes). One the macro server ran (#176), of the workspace or of std, is its whole output, replacing the item,
    and says where each of its tokens comes from by `spans` instead of `origins`.
    
    """
    def __init__(self, __text: str, __origins: list[ExpansionOrigin], *, replaces: bool = ..., spans: list[MappedSpan] = ...):
        """
         for type MappedSpan, see 'loupe.db/macro_output.pyi'
        """
        ...
    @property
    def text(self) -> str:
        ...
    @property
    def origins(self) -> list[ExpansionOrigin]:
        ...
    @property
    def replaces(self) -> bool:
        ...
    @property
    def spans(self) -> list[MappedSpan]:
        """
         for type MappedSpan, see 'loupe.db/macro_output.pyi'
        """
        ...
    def __eq__(self, __other: Expansion) -> bool:
        ...
    def __ne__(self, __other: Expansion) -> bool:
        ...
class ExpandTo:
    """
    
    What the output of a macro call is parsed as, by where the call stands (D117): rust-analyzer's `ExpandTo`.
    
    """
    def __repr__(self) -> str:
        ...
    def __eq__(self, __other: ExpandTo) -> bool:
        ...
    def __ne__(self, __other: ExpandTo) -> bool:
        ...
    kind: Literal['ToItems'] | Literal['ToExpr'] | Literal['ToStmts']
    class ToItems(ExpandTo):
        kind: Literal['ToItems'] = 'ToItems'
        def __init__(self):
            ...
    class ToExpr(ExpandTo):
        kind: Literal['ToExpr'] = 'ToExpr'
        def __init__(self):
            ...
    class ToStmts(ExpandTo):
        kind: Literal['ToStmts'] = 'ToStmts'
        def __init__(self):
            ...
