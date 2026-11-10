from typing import Literal

class FileChange:
    """
    A file operation. Existing-file operations carry the complete expected original text. Paths use the consumer's normalized namespace; renames never overwrite a destination. CreateFile includes initial contents, so it needs no subsequent EditFile.
    """
    def __eq__(self, __other: FileChange) -> bool:
        ...
    def __ne__(self, __other: FileChange) -> bool:
        ...
    def __repr__(self) -> str:
        ...
    def paths(self) -> list[str]:
        """
        Every path reserved by this operation, including a rename destination.
        """
        ...
    kind: Literal['EditFile', 'CreateFile', 'RenameFile', 'DeleteFile']
    class EditFile(FileChange):
        kind: Literal['EditFile'] = 'EditFile'
        def __init__(self, __p1: str, __p2: str, __p3: list[TextEdit]):
            """
             for type TextEdit, see 'source_change/text_edit.pyi'
            """
            ...
        @property
        def field0(self) -> str:
            ...
        @property
        def field1(self) -> str:
            ...
        @property
        def field2(self) -> list[TextEdit]:
            ...
        __match_args__ = ('field0', 'field1', 'field2')
    class CreateFile(FileChange):
        kind: Literal['CreateFile'] = 'CreateFile'
        def __init__(self, __p1: str, __p2: str):
            ...
        @property
        def field0(self) -> str:
            ...
        @property
        def field1(self) -> str:
            ...
        __match_args__ = ('field0', 'field1')
    class RenameFile(FileChange):
        kind: Literal['RenameFile'] = 'RenameFile'
        def __init__(self, __p1: str, __p2: str, __p3: str):
            ...
        @property
        def field0(self) -> str:
            ...
        @property
        def field1(self) -> str:
            ...
        @property
        def field2(self) -> str:
            ...
        __match_args__ = ('field0', 'field1', 'field2')
    class DeleteFile(FileChange):
        kind: Literal['DeleteFile'] = 'DeleteFile'
        def __init__(self, __p1: str, __p2: str):
            ...
        @property
        def field0(self) -> str:
            ...
        @property
        def field1(self) -> str:
            ...
        __match_args__ = ('field0', 'field1')
class SourceChange:
    """
    A collection of independent file operations, not a filesystem transaction. Each path may occur once, including rename destinations: rename chains and an edit of a renamed/created file must be composed by the producer before constructing it. Consumers resolve paths, check expected contents and capabilities, and own application.
    """
    def __init__(self, __files: list[FileChange]):
        ...
    @property
    def files(self) -> list[FileChange]:
        ...
    def __eq__(self, __other: SourceChange) -> bool:
        ...
    def __ne__(self, __other: SourceChange) -> bool:
        ...
    def __repr__(self) -> str:
        ...
    def validate(self) -> None:
        """
        Checks path spelling conflicts and all text edits without touching the filesystem. Consumers must also reject aliases after resolving paths in their own namespace.  @throws IllegalArgumentException - for empty or repeated paths, or invalid text edits
        """
        ...
