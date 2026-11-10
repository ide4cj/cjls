from typing import Literal

class ExtendedType:
    """
    A type an `extend` extends: one declared, or a type of the language by its keyword (`Int64`).
    """
    def __repr__(self) -> str:
        ...
    def __eq__(self, __other: ExtendedType) -> bool:
        ...
    def __ne__(self, __other: ExtendedType) -> bool:
        ...
    def __hash__(self) -> int:
        ...
    kind: Literal['DeclType', 'PrimType', 'BuiltInHead']
    class DeclType(ExtendedType):
        kind: Literal['DeclType'] = 'DeclType'
        def __init__(self, __p1: DefId):
            """
             for type DefId, see 'loupe.hir/def_map.pyi'
            """
            ...
        @property
        def field0(self) -> DefId:
            ...
        __match_args__ = ('field0')
    class PrimType(ExtendedType):
        kind: Literal['PrimType'] = 'PrimType'
        def __init__(self, __p1: str):
            ...
        @property
        def field0(self) -> str:
            ...
        __match_args__ = ('field0')
    class BuiltInHead(ExtendedType):
        kind: Literal['BuiltInHead'] = 'BuiltInHead'
        def __init__(self, __p1: CompilerType):
            """
             for type CompilerType, see 'loupe.hir/compiler_types.pyi'
            """
            ...
        @property
        def field0(self) -> CompilerType:
            ...
        __match_args__ = ('field0')
class MemberTarget:
    """
    What a name of the type a body is in stands for: a declaration among its members, or a member parameter of its primary constructor (N69).
    """
    def __repr__(self) -> str:
        ...
    def __eq__(self, __other: MemberTarget) -> bool:
        ...
    def __ne__(self, __other: MemberTarget) -> bool:
        ...
    def __hash__(self) -> int:
        ...
    kind: Literal['MemberDecl', 'MemberParam']
    class MemberDecl(MemberTarget):
        kind: Literal['MemberDecl'] = 'MemberDecl'
        def __init__(self, __p1: DefId):
            """
             for type DefId, see 'loupe.hir/def_map.pyi'
            """
            ...
        @property
        def field0(self) -> DefId:
            ...
        __match_args__ = ('field0')
    class MemberParam(MemberTarget):
        kind: Literal['MemberParam'] = 'MemberParam'
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
