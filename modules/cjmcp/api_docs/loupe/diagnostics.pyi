from typing import Literal

class Severity:
    """
    Diagnostic severity: Error, Warning, or informational Hint.
    """
    def __eq__(self, __other: Severity) -> bool:
        ...
    def __ne__(self, __other: Severity) -> bool:
        ...
    kind: Literal['Error', 'Warning', 'Hint']
    class Error(Severity):
        kind: Literal['Error'] = 'Error'
        def __init__(self):
            ...
    class Warning(Severity):
        kind: Literal['Warning'] = 'Warning'
        def __init__(self):
            ...
    class Hint(Severity):
        kind: Literal['Hint'] = 'Hint'
        def __init__(self):
            ...
class Diagnostic:
    """
    Something wrong in a file, or worth knowing of it. `range` is where its source put it, empty ones included, as "expected `}`" at the end of a file (A12). `unnecessary` for code a build leaves out, which an editor shows faded.
    """
    def __init__(self, __range: TextRange, __severity: Severity, __message: str, *, unnecessary: bool = ...):
        """
         for type TextRange, see 'ginkgo/text_range.pyi'
        """
        ...
    @property
    def range(self) -> TextRange:
        """
         for type TextRange, see 'ginkgo/text_range.pyi'
        """
        ...
    @property
    def severity(self) -> Severity:
        ...
    @property
    def message(self) -> str:
        ...
    @property
    def unnecessary(self) -> bool:
        ...
    def __eq__(self, __other: Diagnostic) -> bool:
        ...
    def __ne__(self, __other: Diagnostic) -> bool:
        ...
