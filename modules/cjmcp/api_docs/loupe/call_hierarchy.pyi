from typing import Literal

class CallHierarchyEntry:
    """
    A callable with source locations, independent of protocol positions. Without attached sources, a binary callable uses the referring name's location; `definition` still identifies its overload.
    """
    def __init__(self, __name: str, __kind: StructureKind, __target: NavigationTarget, *, definition: DefId | None = ...):
        """
         for type DefId, see 'loupe.hir/def_map.pyi'
         for type NavigationTarget, see 'loupe/definition.pyi'
         for type StructureKind, see 'loupe/structure.pyi'
        """
        ...
    @property
    def name(self) -> str:
        ...
    @property
    def kind(self) -> StructureKind:
        """
         for type StructureKind, see 'loupe/structure.pyi'
        """
        ...
    @property
    def target(self) -> NavigationTarget:
        """
         for type NavigationTarget, see 'loupe/definition.pyi'
        """
        ...
    @property
    def definition(self) -> DefId | None:
        """
        Canonical binary identity, including when `target` is an attached source declaration.
         for type DefId, see 'loupe.hir/def_map.pyi'
        """
        ...
    def __eq__(self, __other: CallHierarchyEntry) -> bool:
        ...
    def __ne__(self, __other: CallHierarchyEntry) -> bool:
        ...
class HierarchyCalls:
    """
    One caller or callee, grouping its call sites. Ranges always belong to the caller's file.
    """
    def __init__(self, __item: CallHierarchyEntry, __ranges: list[TextRange]):
        """
         for type TextRange, see 'ginkgo/text_range.pyi'
        """
        ...
    @property
    def item(self) -> CallHierarchyEntry:
        ...
    @property
    def ranges(self) -> list[TextRange]:
        """
         for type TextRange, see 'ginkgo/text_range.pyi'
        """
        ...
