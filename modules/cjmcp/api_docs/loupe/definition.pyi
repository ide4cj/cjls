from typing import Literal

class NavigationTarget:
    """
    A declaration a request goes to: its file, its whole node, and its name, what an editor selects; rust-analyzer's `NavigationTarget`. One a macro wrote, which a request in an expansion goes to (`definitionInExpansion`), is in the text of that expansion: `expansion` is its call, the ranges are of `expandedMacro`'s text, `fileId` the call's file.
    """
    def __init__(self, __fileId: FileId, __fullRange: TextRange, __focusRange: TextRange, *, expansion: MacroCallId | None = ...):
        """
         for type MacroCallId, see 'loupe.hir/expansion.pyi'
         for type TextRange, see 'ginkgo/text_range.pyi'
         for type FileId, see 'loupe.vfs/vfs.pyi'
        """
        ...
    @property
    def fileId(self) -> FileId:
        """
         for type FileId, see 'loupe.vfs/vfs.pyi'
        """
        ...
    @property
    def fullRange(self) -> TextRange:
        """
         for type TextRange, see 'ginkgo/text_range.pyi'
        """
        ...
    @property
    def focusRange(self) -> TextRange:
        """
         for type TextRange, see 'ginkgo/text_range.pyi'
        """
        ...
    @property
    def expansion(self) -> MacroCallId | None:
        """
         for type MacroCallId, see 'loupe.hir/expansion.pyi'
        """
        ...
    def __eq__(self, __other: NavigationTarget) -> bool:
        ...
    def __ne__(self, __other: NavigationTarget) -> bool:
        ...
