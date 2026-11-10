from typing import Literal

class BuiltinDoc:
    """

    What the language builds in and no source declares — a type that is a keyword, a type of the compiler's own, an
    annotation, a macro of the compiler's — told in our words (D109).

    """
    def __init__(self, __name: str, __code: str, __summary: str):
        ...
    @property
    def name(self) -> str:
        """

        Its name as code writes it, without the `@` of an annotation.

        """
        ...
    @property
    def code(self) -> str:
        """

        How it is written, as a hover shows it: `type Int64`, `@When[condition]`.

        """
        ...
    @property
    def summary(self) -> str:
        """

        What it is, as Markdown.

        """
        ...
