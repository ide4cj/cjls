from typing import Literal

class ScopeStage:
    """
    What a package's scope is read at (#175): what its files write, or that and what the macro calls in them add. A macro's name is looked up in the first, since no macro is ever generated and what is expanded depends on it: the second is a function of the first, and never a cycle of queries.
    """
    def __eq__(self, __other: ScopeStage) -> bool:
        ...
    def __ne__(self, __other: ScopeStage) -> bool:
        ...
    def __hash__(self) -> int:
        ...
    kind: Literal['Written', 'Expanded']
    class Written(ScopeStage):
        kind: Literal['Written'] = 'Written'
        def __init__(self):
            ...
    class Expanded(ScopeStage):
        kind: Literal['Expanded'] = 'Expanded'
        def __init__(self):
            ...
class Redefinition:
    """
    A declaration whose name another of its package took first: anything but a function sharing a name with any other declaration (N19, N20, N22). The declaration ID is exposed as definition in Python.
    """
    def __init__(self, __def: DefId, __name: str):
        ...
    @property
    def definition(self) -> DefId:
        ...
    @property
    def name(self) -> str:
        ...
    def __repr__(self) -> str:
        ...
    def __eq__(self, __other: Redefinition) -> bool:
        ...
    def __ne__(self, __other: Redefinition) -> bool:
        ...
class CalcaFields_DefId:
    """
    An item across files: its file and its id there, interned, so that what is keyed by a definition (its signature, its body) is keyed by one number.
    """
    ...
class DefId:
    """
    An item across files: its file and its id there, interned, so that what is keyed by a definition (its signature, its body) is keyed by one number.
    """
    ...
class PackageRef:
    """
    A package of either kind, as name resolution takes it: one of the project's sources, or one compiled already (D38). What resolves in it does not ask which.
    """
    def __eq__(self, __other: PackageRef) -> bool:
        ...
    def __ne__(self, __other: PackageRef) -> bool:
        ...
    def __hash__(self) -> int:
        ...
    def __repr__(self) -> str:
        ...
    kind: Literal['Source', 'Binary']
    class Source(PackageRef):
        kind: Literal['Source'] = 'Source'
        def __init__(self, __p1: Package):
            """
             for type Package, see 'loupe.db/project.pyi'
            """
            ...
        @property
        def field0(self) -> Package:
            ...
        __match_args__ = ('field0')
    class Binary(PackageRef):
        kind: Literal['Binary'] = 'Binary'
        def __init__(self, __p1: BinaryPackageFile):
            """
             for type BinaryPackageFile, see 'loupe.db/project.pyi'
            """
            ...
        @property
        def field0(self) -> BinaryPackageFile:
            ...
        __match_args__ = ('field0')
class Visibility:
    """
    Who sees a declaration (N1–N4): `private` its file, `internal` its package and those under it by name, `protected` the packages of its first segment, `public` anyone.
    """
    def __repr__(self) -> str:
        ...
    def __eq__(self, __other: Visibility) -> bool:
        ...
    def __ne__(self, __other: Visibility) -> bool:
        ...
    kind: Literal['Private', 'Internal', 'Protected', 'Public']
    class Private(Visibility):
        kind: Literal['Private'] = 'Private'
        def __init__(self):
            ...
    class Internal(Visibility):
        kind: Literal['Internal'] = 'Internal'
        def __init__(self):
            ...
    class Protected(Visibility):
        kind: Literal['Protected'] = 'Protected'
        def __init__(self):
            ...
    class Public(Visibility):
        kind: Literal['Public'] = 'Public'
        def __init__(self):
            ...
class Def:
    """
    A declaration a name of a package's scope stands for, and who sees it.
    """
    def __init__(self, __id: DefId, __visibility: Visibility):
        ...
    @property
    def id(self) -> DefId:
        ...
    @property
    def visibility(self) -> Visibility:
        ...
    def __repr__(self) -> str:
        ...
    def __eq__(self, __other: Def) -> bool:
        ...
    def __ne__(self, __other: Def) -> bool:
        ...
