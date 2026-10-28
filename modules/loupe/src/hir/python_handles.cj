package loupe.hir

import ginkgo.TextRange
import py_interop.*
import py_interop.internal_macros.DerivePython

/**
 * File-qualified source adapter: the generic syntax pointer stays inside loupe.
 */
@DerivePython
public class PythonBodySource {
    @PyIgnore
    let value: BodySource

    @PyIgnore
    public init(value: BodySource) {
        this.value = value
    }

    public prop range: TextRange {
        get() {
            value.ptr.range
        }
    }
    public prop kind: String {
        get() {
            value.ptr.kind.toString()
        }
    }
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
