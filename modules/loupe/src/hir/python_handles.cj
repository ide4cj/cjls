package loupe.hir

import ginkgo.TextRange
import py_interop.*
import py_interop.internal_macros.DerivePython

/**
 * File-qualified source adapter: the generic syntax pointer stays inside loupe.
 */
@DerivePython
@PyName["BodySource"]
@PyDoc["A file-qualified source anchor: syntax range, kind and optional macro expansion."]
public class PythonBodySource {
    @PyIgnore
    let value: BodySource

    @PyIgnore
    public init(value: BodySource) {
        this.value = value
    }

    @PyDoc["The UTF-8 byte range of the source syntax."]
    public prop range: TextRange {
        get() {
            value.ptr.range
        }
    }
    @PyDoc["The source syntax kind name."]
    public prop kind: String {
        get() {
            value.ptr.kind.toString()
        }
    }
    @PyDoc["The containing macro expansion ID, or None for written source."]
    public prop expansion: ?MacroCallId {
        get() {
            value.expansion
        }
    }
}

extend BodySource <: IntoPy<BodySource> & FromPy<BodySource> {
    public func toPyObj(marker!: PyInteropTypeMarker<BodySource> = PyInteropTypeMarker()): PyObj {
        PythonBodySource(this).toPyObj()
    }
    public static func fromNativePyObj(
        obj: NativePyObj,
        marker!: PyInteropTypeMarker<BodySource> = PyInteropTypeMarker()
    ): ?BodySource {
        PythonBodySource.fromNativePyObj(obj).map { proxy => proxy.value }
    }
    public static func fromPyObj(
        obj: PyObj,
        marker!: PyInteropTypeMarker<BodySource> = PyInteropTypeMarker()
    ): ?BodySource {
        fromNativePyObj(obj.getRef().getPtr())
    }
}
