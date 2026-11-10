from typing import Literal

class FoundSymbol:
    """

    A declaration of the workspace a search found, and the file it is in.

    """
    def __init__(self, __fileId: FileId, __symbol: FileSymbol):
        """
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
    def symbol(self) -> FileSymbol:
        ...
class FileSymbol:
    """

    A declaration of a file, as a search of the workspace sees it: an entry of its outline, and the
    name of the one it is under, if any.

    """
    def __init__(self, __name: str, __kind: StructureKind, __range: TextRange, __selectionRange: TextRange, __containerName: str | None):
        """
         for type TextRange, see 'ginkgo/text_range.pyi'
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
    def range(self) -> TextRange:
        """
         for type TextRange, see 'ginkgo/text_range.pyi'
        """
        ...
    @property
    def selectionRange(self) -> TextRange:
        """
         for type TextRange, see 'ginkgo/text_range.pyi'
        """
        ...
    @property
    def containerName(self) -> str | None:
        ...
    def __eq__(self, __other: FileSymbol) -> bool:
        ...
    def __ne__(self, __other: FileSymbol) -> bool:
        ...
