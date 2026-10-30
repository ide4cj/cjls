package cjmcp

import ginkgo.TextRange
import loupe.hir.{LoweredSignature, Signature, SignatureSourceMap, TypeRefId}
@When[os == "Linux"]
import py_interop.*
@When[os == "Linux"]
import py_interop.internal_macros.DerivePython

/**
 * Concrete signature mapping for Python, keeping generic syntax pointers inside loupe.
 */
@When[os == "Linux"]
@DerivePython
class PythonSignatureSourceMap {
    @PyIgnore
    PythonSignatureSourceMap(private let value: SignatureSourceMap) {}

    public prop ranges: Array<?TextRange> {
        get() {
            value.ptrs.map { ptr => ptr.map { one => one.range } }
        }
    }

    /**
     * The first type reference written at exactly this range, or None.
     */
    public func typeAtRange(range: TextRange): ?TypeRefId {
        for (i in 0..value.ptrs.size where value.ptrs[i].map { ptr => ptr.range } == Some(range)) {
            return TypeRefId(i)
        }
        None
    }
}

/**
 * A native written signature and its concrete Python source mapping.
 */
@When[os == "Linux"]
@DerivePython
class PythonLoweredSignature {
    @PyIgnore
    PythonLoweredSignature(value: LoweredSignature) {
        signature = value.signature
        sourceMap = PythonSignatureSourceMap(value.sourceMap)
    }

    public let signature: Signature
    public let sourceMap: PythonSignatureSourceMap
}
