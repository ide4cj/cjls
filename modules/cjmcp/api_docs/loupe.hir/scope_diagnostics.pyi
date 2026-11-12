from typing import Literal

class ScopeProblem:
    """
    What is wrong with a file's scope, as cjc and cjpm report it.
    """
    def __repr__(self) -> str:
        ...
    def isWarning(self) -> bool:
        """
        Whether cjc reports it as a warning, not an error.
        """
        ...
    def message(self) -> str:
        """
        What cjc says of it.
        """
        ...
    def __eq__(self, __other: ScopeProblem) -> bool:
        ...
    def __ne__(self, __other: ScopeProblem) -> bool:
        ...
    kind: Literal['ImportFailed', 'Shadowed', 'Conflicted', 'SubPackage']
    class ImportFailed(ScopeProblem):
        kind: Literal['ImportFailed'] = 'ImportFailed'
        def __init__(self, __p1: ImportError):
            """
             for type ImportError, see 'loupe.hir/imports.pyi'
            """
            ...
        @property
        def field0(self) -> ImportError:
            ...
        __match_args__ = ('field0',)
    class Shadowed(ScopeProblem):
        kind: Literal['Shadowed'] = 'Shadowed'
        def __init__(self, __p1: str):
            ...
        @property
        def field0(self) -> str:
            ...
        __match_args__ = ('field0',)
    class Conflicted(ScopeProblem):
        kind: Literal['Conflicted'] = 'Conflicted'
        def __init__(self, __p1: str):
            ...
        @property
        def field0(self) -> str:
            ...
        __match_args__ = ('field0',)
    class SubPackage(ScopeProblem):
        kind: Literal['SubPackage'] = 'SubPackage'
        def __init__(self, __p1: str, __p2: str):
            ...
        @property
        def field0(self) -> str:
            ...
        @property
        def field1(self) -> str:
            ...
        __match_args__ = ('field0', 'field1')
class ScopeProblemAt:
    """
    Where a problem is: a path of an import, or a name of a declaration.
    """
    def __eq__(self, __other: ScopeProblemAt) -> bool:
        ...
    def __ne__(self, __other: ScopeProblemAt) -> bool:
        ...
    kind: Literal['AtImport', 'AtDecl']
    class AtImport(ScopeProblemAt):
        kind: Literal['AtImport'] = 'AtImport'
        def __init__(self, __p1: ImportSite):
            """
             for type ImportSite, see 'loupe.hir/scope.pyi'
            """
            ...
        @property
        def field0(self) -> ImportSite:
            ...
        __match_args__ = ('field0',)
    class AtDecl(ScopeProblemAt):
        kind: Literal['AtDecl'] = 'AtDecl'
        def __init__(self, __p1: DefId, __p2: str):
            """
             for type DefId, see 'loupe.hir/def_map.pyi'
            """
            ...
        @property
        def field0(self) -> DefId:
            ...
        @property
        def field1(self) -> str:
            ...
        __match_args__ = ('field0', 'field1')
class ScopeDiagnostic:
    """
    A scope-resolution problem paired with the import, declaration or file site that caused it.
    """
    def __init__(self, __at: ScopeProblemAt, __problem: ScopeProblem):
        ...
    @property
    def at(self) -> ScopeProblemAt:
        ...
    @property
    def problem(self) -> ScopeProblem:
        ...
    def __eq__(self, __other: ScopeDiagnostic) -> bool:
        ...
    def __ne__(self, __other: ScopeDiagnostic) -> bool:
        ...
