from typing import Literal

class CompletionOverload:
    """
    A declaration in a completion group, seen through its receiver type when it is a member.
    """
    def __init__(self, __id: DefId, __receiver: Ty | None):
        """
         for type Ty, see 'loupe.hir/ty.pyi'
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    @property
    def id(self) -> DefId:
        """
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    @property
    def receiver(self) -> Ty | None:
        """
         for type Ty, see 'loupe.hir/ty.pyi'
        """
        ...
    def __eq__(self, __other: CompletionOverload) -> bool:
        ...
    def __ne__(self, __other: CompletionOverload) -> bool:
        ...
