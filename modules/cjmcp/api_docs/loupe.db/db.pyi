from typing import Literal

class SourceFile:
    """
    One file's text as the analysis sees it, and what the macro server answered for its macro calls (#176). The physical editor input is one per `FileId`; independent package contexts have separate source inputs sharing its text. Inputs are never dropped: a deleted file is empty text (A5), and macro outputs belong to the context that produced them.
    """
    ...
