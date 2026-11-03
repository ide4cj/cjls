package cjmcp

import ginkgo.TextRange
import loupe.Severity
import py_interop.*
import py_interop.internal_macros.DerivePython

/**
 * A diagnostic in the script's revision. Unknown locations remain None rather
 * than being inferred by parsing a toolchain's human-readable message.
 * Ranges are UTF-8 bytes; line and column are one-based, with a UTF-8 byte column.
 */
@DerivePython
struct WorkspaceDiagnostic {
    WorkspaceDiagnostic(
        public let source: String,
        public let severity: Severity,
        public let message: String,
        public let code!: ?String = None,
        public let path!: ?String = None,
        public let range!: ?TextRange = None,
        public let line!: ?Int64 = None,
        public let column!: ?Int64 = None,
        public let unnecessary!: Bool = false
    ) {}
}

/**
 * Work completion and diagnostic severity are independent: settled can include
 * failures, and pending is not itself a diagnostic.
 */
@DerivePython
struct MacroStatus {
    MacroStatus(public let state: String, public let diagnostics: Array<WorkspaceDiagnostic>) {
        if (state != "pending" && state != "settled") {
            throw IllegalArgumentException("macro state must be pending or settled")
        }
    }
}
