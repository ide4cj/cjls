class BuiltinDoc:
    """
    
    What the language builds in and no source declares — a type that is a keyword, a type of the compiler's own, an
    annotation, a macro of the compiler's — told in our words (D109).
    
    """
    def __init__(self, __name: str, __code: str, __summary: str):
        ...
    @property
    def name(self) -> str:
        ...
    @property
    def code(self) -> str:
        ...
    @property
    def summary(self) -> str:
        ...
