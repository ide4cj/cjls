class Reference:
    """
    
    A name of the workspace meaning what the one asked about does: where it is, how it reaches it, as
    `RelatedHighlight` has it, and whether it is the name a declaration gives.
    
    """
    def __init__(self, __fileId: FileId, __range: TextRange, __access: ReferenceAccess | None, __isDeclaration: bool):
        """
         for type ReferenceAccess, see 'loupe/highlight_related.pyi'
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
    def range(self) -> TextRange:
        """
         for type TextRange, see 'ginkgo/text_range.pyi'
        """
        ...
    @property
    def access(self) -> ReferenceAccess | None:
        """
         for type ReferenceAccess, see 'loupe/highlight_related.pyi'
        """
        ...
    @property
    def isDeclaration(self) -> bool:
        ...
    def __eq__(self, __other: Reference) -> bool:
        ...
    def __ne__(self, __other: Reference) -> bool:
        ...
