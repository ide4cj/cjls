package cjmcp

import fjson.*
import ginkgo.TextRange
import loupe.{
    Diagnostic,
    HoverItem,
    HoverResult,
    Severity,
    StructureKind,
    StructureNode,
    definitionAt,
    fileStructure,
    hoverAt
}
import loupe.diagnostics as fileDiagnostics
import loupe.vfs.{FileId, VfsPath}
import loupe.*
import loupe.hir.*
import std.fs.Path
@When[os == "Linux"]
import py_interop.*
@When[os == "Linux"]
import py_interop.internal_macros.*

// Redirect file descriptors as well as Python streams: subprocesses, native extensions and native
// callbacks must not write onto the MCP wire. The protocol loop writes only after these are restored.
@When[os == "Linux"]
const PYTHON_RUNNER =
    #"
import contextlib as _cjmcp_contextlib
import ctypes as _cjmcp_ctypes
import json as _cjmcp_json
import os as _cjmcp_os
import sys as _cjmcp_sys
import tempfile as _cjmcp_tempfile
import traceback as _cjmcp_traceback

def __cjmcp_run(code, workspace, classes):
    scope = dict(classes, workspace=workspace, __name__='__cjmcp_script__')
    result = None
    error = None
    saved_out = _cjmcp_os.dup(1)
    saved_err = _cjmcp_os.dup(2)
    with _cjmcp_tempfile.TemporaryFile() as out, _cjmcp_tempfile.TemporaryFile() as err:
        try:
            _cjmcp_sys.stdout.flush()
            _cjmcp_sys.stderr.flush()
            _cjmcp_os.dup2(out.fileno(), 1)
            _cjmcp_os.dup2(err.fileno(), 2)
            with _cjmcp_os.fdopen(_cjmcp_os.dup(out.fileno()), 'w', encoding='utf-8', buffering=1) as stdout:
                with _cjmcp_os.fdopen(_cjmcp_os.dup(err.fileno()), 'w', encoding='utf-8', buffering=1) as stderr:
                    with _cjmcp_contextlib.redirect_stdout(stdout), _cjmcp_contextlib.redirect_stderr(stderr):
                        try:
                            exec(compile(code, '<runPython>', 'exec'), scope, scope)
                            result = scope.get('result')
                            _cjmcp_json.dumps(result, allow_nan=False)
                        except BaseException:
                            result = None
                            error = _cjmcp_traceback.format_exc()
            _cjmcp_sys.stdout.flush()
            _cjmcp_sys.stderr.flush()
            _cjmcp_ctypes.CDLL(None).fflush(None)
        finally:
            _cjmcp_os.dup2(saved_out, 1)
            _cjmcp_os.dup2(saved_err, 2)
            _cjmcp_os.close(saved_out)
            _cjmcp_os.close(saved_err)
        out.seek(0)
        err.seek(0)
        return _cjmcp_json.dumps(dict(
            stdout=out.read().decode('utf-8', errors='replace'),
            stderr=err.read().decode('utf-8', errors='replace'),
            result=result, error=error), allow_nan=False)
"#

/** A stable workspace handle; reload replaces its disk revision while preserving existing proxies. */
@When[os == "Linux"]
@DerivePython
class Workspace {
    private var current: ?WorkspaceState = None

    Workspace(private let directory: String) {}

    public prop root: String {
        get() {
            directory
        }
    }
    public prop problems: Array<String> {
        get() {
            loaded().problems
        }
    }
    public prop macrosExpanded: Bool {
        get() {
            false
        }
    }

    public func files(): Array<String> {
        loaded().files.map { path => path.toString() }
    }

    public func reload(): Unit {
        current = WorkspaceState(VfsPath.file(directory))
    }

    public func structure(path: String): Array<StructureNode> {
        let (view, file) = resolve(path)
        fileStructure(view.db, file)
    }

    public func diagnostics(path: String): Array<Diagnostic> {
        let (view, file) = resolve(path)
        fileDiagnostics(view.db, file)
    }

    public func hover(path: String, offset: Int64): ?HoverResult {
        let (view, file) = position(path, offset)
        hoverAt(view.db, file, offset)
    }

    public func definition(path: String, offset: Int64): Array<PythonLocation> {
        let (view, file) = position(path, offset)
        definitionAt(view.db, file, offset)
            .map {
                target =>
                PythonLocation(
                    view.vfs.paths.path(target.fileId).toString(),
                    target.fullRange,
                    target.focusRange
                )
            }
    }

    /** Capture a disk revision; it remains usable after workspace.reload(). */
    public func analysis(): AnalysisRevision {
        AnalysisRevision(loaded())
    }

    private func loaded(): WorkspaceState {
        if (current.isNone()) {
            reload()
        }
        current.getOrThrow()
    }

    private func resolve(written: String): (WorkspaceState, FileId) {
        let view = loaded()
        let path =
            if (Path(written).isAbsolute()) {
                VfsPath.file(written)
            } else {
                view.root.join(written)
            }
        let id =
            view.vfs.fileId(path) ?? throw IllegalArgumentException("file is not loaded: ${path}")
        (view, id)
    }

    private func position(path: String, offset: Int64): (WorkspaceState, FileId) {
        let (view, file) = resolve(path)
        let text = view.vfs.fileContents(file).getOrThrow().toString().toArray()
        if (
            offset < 0 || offset > text.size ||
                (offset < text.size && (text[offset] & 0xC0) == 0x80)
        ) {
            throw IllegalArgumentException("offset must be a UTF-8 byte boundary within the file")
        }
        (view, file)
    }
}

@When[os == "Linux"]
@DerivePython
class PythonLocation {
    PythonLocation(
        public let path: String,
        public let range: TextRange,
        public let selectionRange: TextRange
    ) {}
}

@When[os == "Linux"]
class PythonSession {
    private let workspace: Workspace
    private var runner: ?PyObj = None
    private var workspaceProxy: ?PyObj = None
    private var types: ?PyObj = None

    PythonSession(root: VfsPath) {
        workspace = Workspace(root.toString())
    }

    func run(code: String): JsonValue {
        if (runner.isNone()) {
            Python.load(loglevel: LogLevel.ERROR)
            Python.exec(PYTHON_RUNNER)
            workspaceProxy = workspace.toPyObj()
            types =
                PyDict<String, PyObj>(
                    [
                        ("TextRange", TextRange.pyClass()),
                        ("StructureNode", StructureNode.pyClass()),
                        ("StructureKind", StructureKind.pyClass()),
                        ("Diagnostic", Diagnostic.pyClass()),
                        ("Severity", Severity.pyClass()),
                        ("HoverResult", HoverResult.pyClass()),
                        ("HoverItem", HoverItem.pyClass()),
                        ("Location", PythonLocation.pyClass()),
                        ("AnalysisRevision", AnalysisRevision.pyClass())
                    ]
                        .concat(analysisTypes())
                )
            runner = Python.eval("__cjmcp_run")
        }
        let output =
            runner.getOrThrow()([PyString(code), workspaceProxy.getOrThrow(), types.getOrThrow()])
        fromJsonBytes<JsonValue>(output.toString().toArray())
    }
}

@When[os != "Linux"]
class PythonSession {
    PythonSession(root: VfsPath) {}
    func run(code: String): JsonValue {
        throw IllegalStateException(
            "Embedded Python is currently supported by this experiment on native Linux only"
        )
    }
}
