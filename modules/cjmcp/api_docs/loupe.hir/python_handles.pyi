from typing import Literal

class BodySource:
    """
    A file-qualified source anchor: syntax range, kind and optional macro expansion.
    """
    @property
    def range(self) -> TextRange:
        """
        The UTF-8 byte range of the source syntax.
         for type TextRange, see 'ginkgo/text_range.pyi'
        """
        ...
    @property
    def kind(self) -> str:
        """
        The source syntax kind name.
        """
        ...
    @property
    def expansion(self) -> MacroCallId | None:
        """
        The containing macro expansion ID, or None for written source.
         for type MacroCallId, see 'loupe.hir/expansion.pyi'
        """
        ...
