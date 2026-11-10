from typing import Literal

class CompletionResult:
    """

    The completions at a cursor: what the item inserted replaces, the name typed so far before the
    cursor, and the items, the most relevant first.

    """
    def __init__(self, __range: TextRange, __items: list[CompletionItem]):
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
    def items(self) -> list[CompletionItem]:
        ...
    def __eq__(self, __other: CompletionResult) -> bool:
        ...
    def __ne__(self, __other: CompletionResult) -> bool:
        ...
class CompletionItem:
    """

    One completion candidate: label, kind, ranking relevance and source for deferred details.

    """
    def __init__(self, __label: str, __kind: CompletionKind, __relevance: int, __source: CompletionSource):
        ...
    @property
    def label(self) -> str:
        ...
    @property
    def kind(self) -> CompletionKind:
        ...
    @property
    def relevance(self) -> int:
        """

        Higher first: a local before a member before the file's scope before a keyword; the
        client's own match against what was typed comes on top of it.

        """
        ...
    @property
    def source(self) -> CompletionSource:
        ...
    @property
    def overloadCount(self) -> int:
        """

        How many declarations this item offers; counting a group needs no signature query.

        """
        ...
    def __eq__(self, __other: CompletionItem) -> bool:
        ...
    def __ne__(self, __other: CompletionItem) -> bool:
        ...
class CompletionKind:
    """

    What a completion item is, for the client to show it as one.

    """
    def __eq__(self, __other: CompletionKind) -> bool:
        ...
    def __ne__(self, __other: CompletionKind) -> bool:
        ...
    def __repr__(self) -> str:
        ...
    kind: Literal['LocalItem', 'ParamItem', 'FuncItem', 'VarItem', 'PropItem', 'CtorItem', 'ClassItem', 'InterfaceItem', 'StructItem', 'EnumItem', 'TypeAliasItem', 'PkgItem', 'TypeParamItem', 'KeywordItem']
    class LocalItem(CompletionKind):
        kind: Literal['LocalItem'] = 'LocalItem'
        def __init__(self):
            ...
    class ParamItem(CompletionKind):
        kind: Literal['ParamItem'] = 'ParamItem'
        def __init__(self):
            ...
    class FuncItem(CompletionKind):
        kind: Literal['FuncItem'] = 'FuncItem'
        def __init__(self):
            ...
    class VarItem(CompletionKind):
        kind: Literal['VarItem'] = 'VarItem'
        def __init__(self):
            ...
    class PropItem(CompletionKind):
        kind: Literal['PropItem'] = 'PropItem'
        def __init__(self):
            ...
    class CtorItem(CompletionKind):
        kind: Literal['CtorItem'] = 'CtorItem'
        def __init__(self):
            ...
    class ClassItem(CompletionKind):
        kind: Literal['ClassItem'] = 'ClassItem'
        def __init__(self):
            ...
    class InterfaceItem(CompletionKind):
        kind: Literal['InterfaceItem'] = 'InterfaceItem'
        def __init__(self):
            ...
    class StructItem(CompletionKind):
        kind: Literal['StructItem'] = 'StructItem'
        def __init__(self):
            ...
    class EnumItem(CompletionKind):
        kind: Literal['EnumItem'] = 'EnumItem'
        def __init__(self):
            ...
    class TypeAliasItem(CompletionKind):
        kind: Literal['TypeAliasItem'] = 'TypeAliasItem'
        def __init__(self):
            ...
    class PkgItem(CompletionKind):
        kind: Literal['PkgItem'] = 'PkgItem'
        def __init__(self):
            ...
    class TypeParamItem(CompletionKind):
        kind: Literal['TypeParamItem'] = 'TypeParamItem'
        def __init__(self):
            ...
    class KeywordItem(CompletionKind):
        kind: Literal['KeywordItem'] = 'KeywordItem'
        def __init__(self):
            ...
class CompletionSource:
    """

    What a completion item stands for, for its detail and documentation when a client asks for them
    (`completionDetails`): a declaration, as a member of a value of a type if one's; a group of
    overloads with their receiver types; a local of a body; a member parameter of a primary
    constructor; nothing, for a keyword or a package.

    """
    def __eq__(self, __other: CompletionSource) -> bool:
        ...
    def __ne__(self, __other: CompletionSource) -> bool:
        ...
    kind: Literal['DeclSource', 'OverloadSource', 'LocalSource', 'MemberParamSource', 'NoSource']
    class DeclSource(CompletionSource):
        kind: Literal['DeclSource'] = 'DeclSource'
        def __init__(self, __p1: DefId, __p2: Ty | None):
            """
             for type Ty, see 'loupe.hir/ty.pyi'
             for type DefId, see 'loupe.hir/def_map.pyi'
            """
            ...
        @property
        def field0(self) -> DefId:
            ...
        @property
        def field1(self) -> Ty | None:
            ...
        __match_args__ = ('field0', 'field1')
    class OverloadSource(CompletionSource):
        kind: Literal['OverloadSource'] = 'OverloadSource'
        def __init__(self, __p1: list[CompletionOverload]):
            """
             for type CompletionOverload, see 'loupe/completion_overloads.pyi'
            """
            ...
        @property
        def field0(self) -> list[CompletionOverload]:
            ...
        __match_args__ = ('field0')
    class LocalSource(CompletionSource):
        kind: Literal['LocalSource'] = 'LocalSource'
        def __init__(self, __p1: DefId, __p2: LocalId):
            """
             for type LocalId, see 'loupe.hir/body.pyi'
             for type DefId, see 'loupe.hir/def_map.pyi'
            """
            ...
        @property
        def field0(self) -> DefId:
            ...
        @property
        def field1(self) -> LocalId:
            ...
        __match_args__ = ('field0', 'field1')
    class MemberParamSource(CompletionSource):
        kind: Literal['MemberParamSource'] = 'MemberParamSource'
        def __init__(self, __p1: DefId, __p2: LocalId, __p3: Ty | None):
            """
             for type Ty, see 'loupe.hir/ty.pyi'
             for type LocalId, see 'loupe.hir/body.pyi'
             for type DefId, see 'loupe.hir/def_map.pyi'
            """
            ...
        @property
        def field0(self) -> DefId:
            ...
        @property
        def field1(self) -> LocalId:
            ...
        @property
        def field2(self) -> Ty | None:
            ...
        __match_args__ = ('field0', 'field1', 'field2')
    class NoSource(CompletionSource):
        kind: Literal['NoSource'] = 'NoSource'
        def __init__(self):
            ...
