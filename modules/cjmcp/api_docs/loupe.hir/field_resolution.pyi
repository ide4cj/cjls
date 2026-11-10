from typing import Literal

class Receiver:
    """

    What the left of a `.` in a body stands for, as far as names tell (N75–N79).

    """
    def __repr__(self) -> str:
        ...
    def __eq__(self, __other: Receiver) -> bool:
        ...
    def __ne__(self, __other: Receiver) -> bool:
        ...
    kind: Literal['PackageReceiver', 'TypesReceiver', 'ValueReceiver', 'NoReceiver']
    class PackageReceiver(Receiver):
        kind: Literal['PackageReceiver'] = 'PackageReceiver'
        def __init__(self, __p1: PackageRef):
            """
             for type PackageRef, see 'loupe.hir/def_map.pyi'
            """
            ...
        @property
        def field0(self) -> PackageRef:
            ...
        __match_args__ = ('field0')
    class TypesReceiver(Receiver):
        kind: Literal['TypesReceiver'] = 'TypesReceiver'
        def __init__(self, __p1: list[ExtendedType]):
            """
             for type ExtendedType, see 'loupe.hir/members.pyi'
            """
            ...
        @property
        def field0(self) -> list[ExtendedType]:
            ...
        __match_args__ = ('field0')
    class ValueReceiver(Receiver):
        kind: Literal['ValueReceiver'] = 'ValueReceiver'
        def __init__(self):
            ...
    class NoReceiver(Receiver):
        kind: Literal['NoReceiver'] = 'NoReceiver'
        def __init__(self):
            ...
class FieldResolution:
    """

    What the name after a `.` in a body means.

    """
    def __repr__(self) -> str:
        ...
    def __eq__(self, __other: FieldResolution) -> bool:
        ...
    def __ne__(self, __other: FieldResolution) -> bool:
        ...
    kind: Literal['PackageMembers', 'TypeMembers', 'OfValue', 'NoField']
    class PackageMembers(FieldResolution):
        kind: Literal['PackageMembers'] = 'PackageMembers'
        def __init__(self, __p1: list[DefId]):
            """
             for type DefId, see 'loupe.hir/def_map.pyi'
            """
            ...
        @property
        def field0(self) -> list[DefId]:
            ...
        __match_args__ = ('field0')
    class TypeMembers(FieldResolution):
        kind: Literal['TypeMembers'] = 'TypeMembers'
        def __init__(self, __p1: list[MemberTarget]):
            """
             for type MemberTarget, see 'loupe.hir/members.pyi'
            """
            ...
        @property
        def field0(self) -> list[MemberTarget]:
            ...
        __match_args__ = ('field0')
    class OfValue(FieldResolution):
        kind: Literal['OfValue'] = 'OfValue'
        def __init__(self):
            ...
    class NoField(FieldResolution):
        kind: Literal['NoField'] = 'NoField'
        def __init__(self):
            ...
