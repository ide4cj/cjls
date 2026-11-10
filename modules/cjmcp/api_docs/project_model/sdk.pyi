from typing import Literal

class CangjieHome:
    """
    The selected SDK: path, discovery source, compiler version and support channel. Unknown version and channel are None.
    """
    def __init__(self, __path: str, __source: str, *, version: str | None = ...):
        ...
    @property
    def path(self) -> str:
        ...
    @property
    def source(self) -> str:
        """

        What named it, for the log: `initializationOptions.cangjieHome`, `CANGJIE_HOME`, cjsdk's
        default toolchain, or `cjc` on `PATH`.

        """
        ...
    @property
    def version(self) -> str | None:
        """

        The selected compiler's version; absent when it cannot run or its output is unrecognized.

        """
        ...
    @property
    def channel(self) -> str | None:
        """
        LTS, STS, pinned nightly or out of window; None when the compiler version is unknown.
        """
        ...
    def __eq__(self, __other: CangjieHome) -> bool:
        ...
    def __ne__(self, __other: CangjieHome) -> bool:
        ...
    def __hash__(self) -> int:
        ...
    def __repr__(self) -> str:
        ...
