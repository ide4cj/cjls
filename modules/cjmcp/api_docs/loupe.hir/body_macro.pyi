from typing import Literal

class BodyMacroCall:
    """

    A macro called in an item, in a body or an initializer, not on the item (D117), as `bodyMacroCalls` finds it: its
    item, the macro's name as written (`m.M`), its ordinal among the calls of that name in the item in the order their
    `@`s are written, the names of the calls in the item whose input it is in, outermost first, and whether another call
    is in its own input. Nothing in it says where it is, so an edit that moves it alone changes no query reading it.

    """
    def __init__(self, __item: ItemId, __name: str, __index: int, __around: list[str], __holdsCalls: bool):
        """
         for type ItemId, see 'loupe.hir/item_id.pyi'
        """
        ...
    @property
    def item(self) -> ItemId:
        """
         for type ItemId, see 'loupe.hir/item_id.pyi'
        """
        ...
    @property
    def name(self) -> str:
        ...
    @property
    def index(self) -> int:
        ...
    @property
    def around(self) -> list[str]:
        ...
    @property
    def holdsCalls(self) -> bool:
        ...
    def __eq__(self, __other: BodyMacroCall) -> bool:
        ...
    def __ne__(self, __other: BodyMacroCall) -> bool:
        ...
