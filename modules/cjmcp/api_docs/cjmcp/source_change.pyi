from typing import Literal

class ApplyChangeResult:
    """
    Application report using zero-based operation indices in the supplied SourceChange. Preflight failures have no applied operations and no failed index. An I/O failure stops at failed; that operation may have changed disk. Nothing is rolled back. revision remains the script's original analysis revision, including after success.
    """
    def __init__(self, __revision: int, __applied: list[int], __failed: int | None, __error: str | None):
        ...
    @property
    def revision(self) -> int:
        ...
    @property
    def applied(self) -> list[int]:
        ...
    @property
    def failed(self) -> int | None:
        ...
    @property
    def error(self) -> str | None:
        ...
    @property
    def isSuccess(self) -> bool:
        """
        Whether all requested file operations were applied without an error.
        """
        ...
