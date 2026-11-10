from typing import Literal

class MacroStatus:
    """

    Work completion and diagnostic severity are independent: settled can include
    failures, and pending is not itself a diagnostic.

    """
    def __init__(self, __state: MacroState, __diagnostics: list[WorkspaceDiagnostic]):
        ...
    @property
    def state(self) -> MacroState:
        ...
    @property
    def diagnostics(self) -> list[WorkspaceDiagnostic]:
        ...
class WorkspaceDiagnostic:
    """

    A diagnostic in the script's revision. Unknown locations remain None rather
    than being inferred by parsing a toolchain's human-readable message.
    Ranges are UTF-8 bytes; line and column are one-based, with a UTF-8 byte column.

    """
    def __init__(self, __source: str, __severity: Severity, __message: str, *, code: str | None = ..., path: str | None = ..., range: TextRange | None = ..., line: int | None = ..., column: int | None = ..., unnecessary: bool = ...):
        """
         for type TextRange, see 'ginkgo/text_range.pyi'
         for type Severity, see 'loupe/diagnostics.pyi'
        """
        ...
    @property
    def source(self) -> str:
        ...
    @property
    def severity(self) -> Severity:
        """
         for type Severity, see 'loupe/diagnostics.pyi'
        """
        ...
    @property
    def message(self) -> str:
        ...
    @property
    def code(self) -> str | None:
        ...
    @property
    def path(self) -> str | None:
        ...
    @property
    def range(self) -> TextRange | None:
        """
         for type TextRange, see 'ginkgo/text_range.pyi'
        """
        ...
    @property
    def line(self) -> int | None:
        ...
    @property
    def column(self) -> int | None:
        ...
    @property
    def unnecessary(self) -> bool:
        ...
class MacroState:
    """

    Whether this revision still needs macro preparation, independently of diagnostics.

    """
    def __eq__(self, __other: MacroState) -> bool:
        ...
    def __ne__(self, __other: MacroState) -> bool:
        ...
    kind: Literal['Pending', 'Settled']
    class Pending(MacroState):
        kind: Literal['Pending'] = 'Pending'
        def __init__(self):
            ...
    class Settled(MacroState):
        kind: Literal['Settled'] = 'Settled'
        def __init__(self):
            ...
