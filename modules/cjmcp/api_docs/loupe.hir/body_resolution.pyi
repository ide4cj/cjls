from typing import Literal

class ValueTarget:
    """
    What a name used in a body stands for.
    """
    def __repr__(self) -> str:
        ...
    def __eq__(self, __other: ValueTarget) -> bool:
        ...
    def __ne__(self, __other: ValueTarget) -> bool:
        ...
    kind: Literal['LocalOf', 'MemberOf', 'DeclOf', 'TypeParamOf']
    class LocalOf(ValueTarget):
        kind: Literal['LocalOf'] = 'LocalOf'
        def __init__(self, __p1: LocalId):
            """
             for type LocalId, see 'loupe.hir/body.pyi'
            """
            ...
        @property
        def field0(self) -> LocalId:
            ...
        __match_args__ = ('field0',)
    class MemberOf(ValueTarget):
        kind: Literal['MemberOf'] = 'MemberOf'
        def __init__(self, __p1: MemberTarget):
            """
             for type MemberTarget, see 'loupe.hir/members.pyi'
            """
            ...
        @property
        def field0(self) -> MemberTarget:
            ...
        __match_args__ = ('field0',)
    class DeclOf(ValueTarget):
        kind: Literal['DeclOf'] = 'DeclOf'
        def __init__(self, __p1: DefId):
            """
             for type DefId, see 'loupe.hir/def_map.pyi'
            """
            ...
        @property
        def field0(self) -> DefId:
            ...
        __match_args__ = ('field0',)
    class TypeParamOf(ValueTarget):
        kind: Literal['TypeParamOf'] = 'TypeParamOf'
        def __init__(self, __p1: TypeTarget):
            """
             for type TypeTarget, see 'loupe.hir/type_path.pyi'
            """
            ...
        @property
        def field0(self) -> TypeTarget:
            ...
        __match_args__ = ('field0',)
class BodyResolution:
    """
    What a name used in a body means.
    """
    def __repr__(self) -> str:
        ...
    def __eq__(self, __other: BodyResolution) -> bool:
        ...
    def __ne__(self, __other: BodyResolution) -> bool:
        ...
    kind: Literal['Values', 'InFile']
    class Values(BodyResolution):
        kind: Literal['Values'] = 'Values'
        def __init__(self, __p1: list[ValueTarget]):
            ...
        @property
        def field0(self) -> list[ValueTarget]:
            ...
        __match_args__ = ('field0',)
    class InFile(BodyResolution):
        kind: Literal['InFile'] = 'InFile'
        def __init__(self, __p1: Resolution):
            """
             for type Resolution, see 'loupe.hir/scope.pyi'
            """
            ...
        @property
        def field0(self) -> Resolution:
            ...
        __match_args__ = ('field0',)
