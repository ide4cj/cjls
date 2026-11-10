from typing import Literal

class NoSpecific:
    """
    A `common` declaration no `specific` one completes, though it needs one, as cjc says it: `'common' function 'f' can not find 'specific' match`. The declaration ID is exposed as definition in Python.
    """
    def __init__(self, __def: DefId, __message: str):
        """
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    @property
    def definition(self) -> DefId:
        """
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    @property
    def message(self) -> str:
        ...
    def __eq__(self, __other: NoSpecific) -> bool:
        ...
    def __ne__(self, __other: NoSpecific) -> bool:
        ...
