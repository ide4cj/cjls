package cjmcp

// Documentation belongs to the executable, independently of the selected workspace.
@When[os == "Linux"]
const PYTHON_API_DOCS =
    #"
import ast as _cjmcp_ast
import textwrap as _cjmcp_textwrap
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


    def outline(self, path, symbol=None):
        """List immediate declarations in source order, optionally inside a class.

        Entries contain symbol (qualified name), kind, line and end_line.
        Lines are one-based and inclusive, including decorators. Overloads and
        property accessors retain separate entries with the same symbol.
        """
        text = self.read(path)
        tree = _cjmcp_ast.parse(text, filename=path)
        parents = [tree] if symbol is None else self._select(tree, symbol)
        if any(not isinstance(node, (_cjmcp_ast.Module, _cjmcp_ast.ClassDef)) for node in parents):
            raise ValueError('outline symbol must name a class')
        prefix = '' if symbol is None else symbol + '.'
        return [dict(symbol=prefix + name, kind=kind,
                     line=self._start(node), end_line=node.end_lineno)
                for parent in parents for node, name, kind in self._declarations(parent)]

    def read_symbol(self, path, symbol, *, max_bytes=12000):
        """Return complete dedented declarations, including docs and decorators.

        Dotted names select nested declarations. All overloads/property accessors
        are returned in source order. Missing names raise KeyError. A selection
        over max_bytes UTF-8 bytes raises ValueError; narrow it with outline()
        or explicitly increase max_bytes. Nothing is silently truncated.
        """
        if isinstance(max_bytes, bool) or not isinstance(max_bytes, int):
            raise TypeError('max_bytes must be a positive integer')
        if max_bytes <= 0:
            raise ValueError('max_bytes must be a positive integer')
        text = self.read(path)
        nodes = self._select(_cjmcp_ast.parse(text, filename=path), symbol)
        lines = text.splitlines(keepends=True)
        selected = '\n'.join(_cjmcp_textwrap.dedent(''.join(lines[self._start(node)-1:node.end_lineno]))
                             for node in nodes)
        size = len(selected.encode('utf-8'))
        if size > max_bytes:
            raise ValueError(f'{symbol} requires {size} UTF-8 bytes, exceeding max_bytes={max_bytes}; '
                             'select a member with outline(path, symbol) or increase max_bytes')
        return selected

    @staticmethod
    def _start(node):
        return min([node.lineno] + [d.lineno for d in getattr(node, 'decorator_list', [])])

    @staticmethod
    def _declarations(parent):
        for node in getattr(parent, 'body', []):
            if isinstance(node, _cjmcp_ast.ClassDef):
                yield node, node.name, 'class'
            elif isinstance(node, (_cjmcp_ast.FunctionDef, _cjmcp_ast.AsyncFunctionDef)):
                yield node, node.name, 'function'
            elif isinstance(node, _cjmcp_ast.AnnAssign) and isinstance(node.target, _cjmcp_ast.Name):
                yield node, node.target.id, 'attribute'
            elif isinstance(node, _cjmcp_ast.Assign):
                for target in node.targets:
                    if isinstance(target, _cjmcp_ast.Name):
                        yield node, target.id, 'attribute'

    def _select(self, tree, symbol):
        if not isinstance(symbol, str):
            raise TypeError('symbol must be a dotted declaration name')
        if not symbol or any(not part.isidentifier() for part in symbol.split('.')):
            raise ValueError('symbol must be a dotted declaration name')
        nodes = [tree]
        for part in symbol.split('.'):
            nodes = [node for parent in nodes
                     for node, name, _ in self._declarations(parent) if name == part]
            if not nodes:
                raise KeyError(symbol)
        return nodes

    @staticmethod
    def _inside(path, root):
        try:
            path.resolve().relative_to(root)
            return True
        except ValueError:
            return False
"#
