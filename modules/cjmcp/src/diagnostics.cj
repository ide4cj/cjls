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
@PyDoc["A diagnostic in the script's revision. Unknown locations remain None rather than being inferred by parsing a toolchain's human-readable message. Ranges are UTF-8 bytes; line and column are one-based, with a UTF-8 byte column."]
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
 * Whether this revision still needs macro preparation, independently of diagnostics.
 */
@DerivePython
@PyDoc["Whether this revision still needs macro preparation, independently of diagnostics."]
enum MacroState <: Equatable<MacroState> {
    | Pending
    | Settled

    public operator func ==(other: MacroState): Bool {
        match ((this, other)) {
            case (MacroState.Pending, MacroState.Pending) => true
            case (MacroState.Settled, MacroState.Settled) => true
            case _ => false
        }
    }

    public operator func !=(other: MacroState): Bool {
        !(this == other)
    }
}

/**
 * Work completion and diagnostic severity are independent: settled can include
 * failures, and pending is not itself a diagnostic.
 */
@DerivePython
@PyDoc["Work completion and diagnostic severity are independent: settled can include failures, and pending is not itself a diagnostic."]
struct MacroStatus {
    MacroStatus(public let state: MacroState, public let diagnostics: Array<WorkspaceDiagnostic>) {}
}
