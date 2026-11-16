from typing import Literal

class CfgOption:
    """
    One option `@When` is evaluated against: `os == "Linux"` reads the option `os`.
    """
    def __init__(self, __key: str, __value: str):
        ...
    @property
    def key(self) -> str:
        ...
    @property
    def value(self) -> str:
        ...
    def __eq__(self, __other: CfgOption) -> bool:
        ...
    def __ne__(self, __other: CfgOption) -> bool:
        ...
class Cfg:
    """
    What `@When` is evaluated against: `os`, `arch`, `backend` and whatever else a build sets, each key once, in the order of the keys.
    """
    @property
    def options(self) -> list[CfgOption]:
        ...
    def __init__(self, __options: list[tuple[str, str]]):
        """

        A later option of a key replaces an earlier one.

        """
        ...
    def get(self, __key: str) -> str | None:
        """
        The value of `key`, `None` if this sets none.
        """
        ...
    def overriddenBy(self, __overrides: Cfg) -> Cfg:
        """
        These options, with those of `overrides` in place of any of the same key.
        """
        ...
    def __eq__(self, __other: Cfg) -> bool:
        ...
    def __ne__(self, __other: Cfg) -> bool:
        ...
class PackageModel:
    """
    A package of a project: the files cjc compiles as one, and how.
    """
    def __init__(self, __name: str, __dir: VfsPath, __files: list[VfsPath], *, noPrelude: bool = ..., isMacro: bool | None = ..., cfg: Cfg | None = ...):
        """
         for type VfsPath, see 'loupe.vfs/path.pyi'
        """
        ...
    @property
    def name(self) -> str:
        """
        As the files name it: `std.collection`, `org::a.b`.
        """
        ...
    @property
    def dir(self) -> VfsPath:
        """
        Where it is: the directory its name gives, unless the build says otherwise.
         for type VfsPath, see 'loupe.vfs/path.pyi'
        """
        ...
    @property
    def files(self) -> list[VfsPath]:
        """
         for type VfsPath, see 'loupe.vfs/path.pyi'
        """
        ...
    @property
    def noPrelude(self) -> bool:
        """
        Compiled with `--no-prelude`: inside it the prelude is the package itself (`std.core`).
        """
        ...
    @property
    def isMacro(self) -> bool | None:
        """
        Whether it is a `macro package`, `None` to read it from its files.
        """
        ...
    @property
    def cfg(self) -> Cfg | None:
        """
        The conditions of its own, those of a `cfg.toml` in its directory, in place of its module's of the same key; `None` for none.
        """
        ...
    def __eq__(self, __other: PackageModel) -> bool:
        ...
    def __ne__(self, __other: PackageModel) -> bool:
        ...
class NativeLibrary:
    """
    A native linker name and search directory; it supplies no Cangjie declarations.
    """
    def __init__(self, __name: str, __dir: VfsPath):
        """
         for type VfsPath, see 'loupe.vfs/path.pyi'
        """
        ...
    @property
    def name(self) -> str:
        ...
    @property
    def dir(self) -> VfsPath:
        """
         for type VfsPath, see 'loupe.vfs/path.pyi'
        """
        ...
    def __eq__(self, __other: NativeLibrary) -> bool:
        ...
    def __ne__(self, __other: NativeLibrary) -> bool:
        ...
    def __hash__(self) -> int:
        ...
    def __repr__(self) -> str:
        ...
class BinaryPackage:
    """
    A package compiled already, a `.cjo` and its library.
    """
    def __init__(self, __name: str, __path: VfsPath):
        """
         for type VfsPath, see 'loupe.vfs/path.pyi'
        """
        ...
    @property
    def name(self) -> str:
        ...
    @property
    def path(self) -> VfsPath:
        """
         for type VfsPath, see 'loupe.vfs/path.pyi'
        """
        ...
    def __eq__(self, __other: BinaryPackage) -> bool:
        ...
    def __ne__(self, __other: BinaryPackage) -> bool:
        ...
class BinarySources:
    """
    The sources a binary was compiled from, of its version: what its `.cjo` keeps nothing of, the declarations to go to. Never resolved against: a name resolves in the `.cjo` alone (D38).
    """
    def __init__(self, __dir: VfsPath, __packages: list[PackageModel]):
        """
         for type VfsPath, see 'loupe.vfs/path.pyi'
        """
        ...
    @property
    def dir(self) -> VfsPath:
        """
        The directory of its root package, each package in the directory its name gives under it (`std.collection` in `<dir>/collection`).
         for type VfsPath, see 'loupe.vfs/path.pyi'
        """
        ...
    @property
    def packages(self) -> list[PackageModel]:
        ...
    def __eq__(self, __other: BinarySources) -> bool:
        ...
    def __ne__(self, __other: BinarySources) -> bool:
        ...
class BinaryModel:
    """
    Modules compiled already, as cjpm's `bin-dependencies` give them: directories every `.cjo` of which is a package (`path-option`), and packages one by one (`package-option`).
    """
    def __init__(self, __name: str, __paths: list[VfsPath], *, packages: list[BinaryPackage] = ..., discoverPackages: bool = ..., sources: BinarySources | None = ...):
        """
         for type VfsPath, see 'loupe.vfs/path.pyi'
        """
        ...
    @property
    def name(self) -> str:
        ...
    @property
    def paths(self) -> list[VfsPath]:
        """
         for type VfsPath, see 'loupe.vfs/path.pyi'
        """
        ...
    @property
    def packages(self) -> list[BinaryPackage]:
        ...
    @property
    def discoverPackages(self) -> bool:
        """
        Whether `paths` discover packages. False retains watched search paths for an already selected package list, such as cjpm's profile-specific binary precedence.
        """
        ...
    @property
    def sources(self) -> BinarySources | None:
        """
        Its sources, `None` if they are not there.
        """
        ...
    def __eq__(self, __other: BinaryModel) -> bool:
        ...
    def __ne__(self, __other: BinaryModel) -> bool:
        ...
class Module:
    """
    A module of the project, one per root, name and resolution scope, never dropped: a module gone is no longer in `Project`. Independent scopes may share a physical root and name.
    """
    ...
class InactiveSourceFile:
    """
    A file of a module the build leaves out, by its id, and why.
    """
    def __init__(self, __fileId: FileId, __reason: str):
        """
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
    def reason(self) -> str:
        ...
    def __eq__(self, __other: InactiveSourceFile) -> bool:
        ...
    def __ne__(self, __other: InactiveSourceFile) -> bool:
        ...
class Package:
    """
    A package of the project, one per name in a module, never dropped: a package gone is no longer in its module. Its files are an input of their own, not found from their texts: a file deleted is an empty text (A5), which nothing tells from an empty file.
    """
    ...
class BinaryPackageFile:
    """
    A package compiled already, as the analysis sees it: the bytes of its `.cjo`, kept out of the `Vfs`, which holds what an editor may open and edit as text (D38). One per binary, package and file, never dropped: a package gone is no longer in `Project.binaryPackages`, and holds no bytes.
    """
    ...
