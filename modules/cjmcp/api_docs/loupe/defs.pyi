from typing import Literal

class Definition:
    """

    What a name means, rust-analyzer's `Definition`: what go to definition goes to, and what highlighting tells a
    name by.

    """
    def __repr__(self) -> str:
        ...
    def __eq__(self, __other: Definition) -> bool:
        ...
    def __ne__(self, __other: Definition) -> bool:
        ...
    kind: Literal['DeclDef', 'LocalDef', 'MemberParamDef', 'TypeParamDef', 'PackageDef']
    class DeclDef(Definition):
        kind: Literal['DeclDef'] = 'DeclDef'
        def __init__(self, __p1: DefId):
            """
             for type DefId, see 'loupe.hir/def_map.pyi'
            """
            ...
        @property
        def field0(self) -> DefId:
            ...
        __match_args__ = ('field0')
    class LocalDef(Definition):
        kind: Literal['LocalDef'] = 'LocalDef'
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
    class MemberParamDef(Definition):
        kind: Literal['MemberParamDef'] = 'MemberParamDef'
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
    class TypeParamDef(Definition):
        kind: Literal['TypeParamDef'] = 'TypeParamDef'
        def __init__(self, __p1: TypeTarget):
            """
             for type TypeTarget, see 'loupe.hir/type_path.pyi'
            """
            ...
        @property
        def field0(self) -> TypeTarget:
            ...
        __match_args__ = ('field0')
    class PackageDef(Definition):
        kind: Literal['PackageDef'] = 'PackageDef'
        def __init__(self, __p1: PackageRef):
            """
             for type PackageRef, see 'loupe.hir/def_map.pyi'
            """
            ...
        @property
        def field0(self) -> PackageRef:
            ...
        __match_args__ = ('field0')
