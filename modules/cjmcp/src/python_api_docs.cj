package cjmcp

// Documentation belongs to the executable, independently of the selected workspace.
@When[os == "Linux"]
const PYTHON_API_DOCS =
    #"
import pathlib as _cjmcp_pathlib

class _CjmcpApiDocs:
    """Read the supplied Python API reference; paths are relative to its root."""

    def _root(self):
        executable = _cjmcp_pathlib.Path('/proc/self/exe').resolve()
        bundled = executable.parent / 'api_docs'
        if bundled.is_dir():
            return bundled.resolve()
        # The documented source build lives at <checkout>/target/release/bin/cjmcp.
        if len(executable.parents) >= 4 and executable.parent.name == 'bin' and executable.parents[2].name == 'target':
            source = executable.parents[3] / 'modules' / 'cjmcp' / 'api_docs'
            if source.is_dir():
                return source.resolve()
        raise FileNotFoundError('cjmcp API documentation is missing; keep api_docs/ beside the executable')

    def files(self):
        """Return sorted .pyi paths, relative to the documentation root."""
        root = self._root()
        return sorted(path.relative_to(root).as_posix()
                      for path in root.rglob('*.pyi')
                      if path.is_file() and self._inside(path, root))

    def read(self, path):
        """Return a .pyi file as UTF-8 text, following root-relative doc links.

        Raise ValueError for invalid paths and FileNotFoundError for missing files.
        """
        if not isinstance(path, str):
            raise TypeError('path must be a root-relative .pyi path')
        relative = _cjmcp_pathlib.PurePosixPath(path)
        if relative.is_absolute() or '..' in relative.parts or relative.suffix != '.pyi':
            raise ValueError('path must be a root-relative .pyi path without ..')
        root = self._root()
        target = root.joinpath(*relative.parts)
        if not self._inside(target, root):
            raise ValueError('path must stay inside the API documentation root')
        return target.read_text(encoding='utf-8')

    @staticmethod
    def _inside(path, root):
        try:
            path.resolve().relative_to(root)
            return True
        except ValueError:
            return False
"#
