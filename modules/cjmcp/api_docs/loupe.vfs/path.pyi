from typing import Literal

class VfsPath:
    """

    Where a file is: a normalized absolute path on disk, or, for a document that has none (an
    editor's `untitled:` buffer), the URI it was given, as is. Two URIs spelling one path apart (a
    `%`-escape the other does not use, a `/./`) give the one `VfsPath`.

    Paths are `std.fs.Path`s and URIs stdx's `URL`s, so a path is absolute as the platform the
    server runs on says (D12). On Windows a drive path keeps `\\` for its separator and its letter
    lowercase: clients differ in both (VS Code sends `c%3A/`, Neovim `C:/`), and the letter's case
    never tells two drives apart. The rest keeps its case, as the client got it from the file system.

    """
    @staticmethod
    def file(__path: str) -> VfsPath:
        """

        @throws IllegalArgumentException - if `path` is not absolute

        """
        ...
    @staticmethod
    def virtual(__name: str) -> VfsPath:
        """
        Create a virtual path without resolving it as a filesystem path.
        """
        ...
    @staticmethod
    def fromUri(__uri: str) -> VfsPath:
        """

        The path a `file:` URI names, anything else a virtual path of the URI itself.

        """
        ...
    def toUri(self) -> str:
        """

        A `file:` URI for a path on disk (`file:///c:/src/a.cj` for a drive), the URI given for a
        virtual one.

        """
        ...
    def isUnder(self, __dir: VfsPath) -> bool:
        """

        Whether this is `dir`, or a path inside it; a virtual path is under nothing, and nothing is
        under it.

        """
        ...
    @property
    def parent(self) -> VfsPath | None:
        """

        The directory holding this path, `None` for the root of the file system (`/`, a drive's
        `c:\\`) and a virtual path.

        """
        ...
    @property
    def name(self) -> str:
        """

        The last name of the path, empty for the root of the file system; a virtual path's URI.

        """
        ...
    def join(self, __relative: str) -> VfsPath:
        """

        The path `relative` leads to from this one, normalized: `..` goes up.

        @throws IllegalArgumentException - if this path is virtual, or `relative` is absolute

        """
        ...
    def segmentsUnder(self, __dir: VfsPath) -> list[str] | None:
        """

        The names that lead from `dir` down to this path, this path's own last; empty for `dir`
        itself, `None` if it is not under `dir`.

        """
        ...
    def __hash__(self) -> int:
        ...
    def __eq__(self, __other: VfsPath) -> bool:
        ...
    def __ne__(self, __other: VfsPath) -> bool:
        ...
    def __repr__(self) -> str:
        ...
