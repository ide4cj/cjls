package loupe.db

import py_interop.*
import py_interop.internal_macros.*

import std.collection.HashMap
import std.deriving.*
import ginkgo.TextRange

/**
 * Where a piece of a macro call's input or output comes from (#176).
 */
@DerivePython[equatable]
@Derive[Equatable]
public enum SpanOrigin <: ToString {
    /**
     * Text of the source file, as a range relative to the start of the top-level item the call is under (its
     * outermost macro call's `@`), which an edit elsewhere in the file leaves right.
     */
    | FromSource(TextRange)
    /**
     * The call itself: what its macro wrote (a token a `quote` made).
     */
    | FromCall

    public func toString(): String {
        match (this) {
            case FromSource(range) => "FromSource(${range})"
            case FromCall => "FromCall"
        }
    }
}

/**
 * A range of a `MappedText` and where it comes from.
 */
@DerivePython[equatable]
@Derive[Equatable]
public struct MappedSpan <: ToString {
    public MappedSpan(public let range: TextRange, public let origin: SpanOrigin) {}

    public func toString(): String {
        "${range} <- ${origin}"
    }
}

/**
 * Text a macro call reads or writes, and where its pieces come from: spans in order, not overlapping; text in none of
 * them (the spaces between printed tokens) comes from nowhere.
 */
@DerivePython[equatable]
@Derive[Equatable]
public struct MappedText {
    public MappedText(public let text: String, public let spans: Array<MappedSpan>) {}

    /**
     * Text all of which comes from the source at `origin`, relative to the top-level item, as one span.
     */
    public static func fromSource(text: String, origin: Int64): MappedText {
        MappedText(
            text,
            [
                MappedSpan(
                    TextRange.at(0, text.size),
                    SpanOrigin.FromSource(TextRange.at(origin, text.size))
                )
            ]
        )
    }

    /**
     * Where `range` of the text comes from: the origin of the span its start is in; within a span as long as its
     * origin (text copied from the source), the same part of it. `None` for text in no span.
     */
    public func originOf(range: TextRange): ?SpanOrigin {
        for (span in spans where span.range.start <= range.start && range.start < span.range.end) {
            return match (span.origin) {
                case FromSource(source) where source.len == span.range.len =>
                    let start = source.start + range.start - span.range.start
                    let end = min(source.start + range.end - span.range.start, source.end)
                    SpanOrigin.FromSource(TextRange(start, end))
                case other => other
            }
        }
        None
    }
}

/**
 * A value a macro gives the macro calls around it (`setItem`, which they read with `getChildMessages`).
 */
@DerivePython[equatable]
@Derive[Equatable]
public enum MacroItemValue <: ToString {
    | StringItem(String)
    | IntItem(Int64)
    | BoolItem(Bool)
    | TokensItem(MappedText)

    public func toString(): String {
        match (this) {
            case StringItem(value) => "String(${value})"
            case IntItem(value) => "Int(${value})"
            case BoolItem(value) => "Bool(${value})"
            case TokensItem(value) => "Tokens(${value.text})"
        }
    }
}

/**
 * One `setItem` of a macro call: its key and value.
 */
@DerivePython[equatable]
@Derive[Equatable]
public struct MacroItem <: ToString {
    public MacroItem(public let key: String, public let value: MacroItemValue) {}

    public func toString(): String {
        "${key}=${value}"
    }
}

/**
 * How bad what a macro reports is (`diagReport`'s `DiagReportLevel`).
 */
@DerivePython[equatable]
@Derive[Equatable]
public enum MacroSeverity {
    | MacroError
    | MacroWarning
}

/**
 * What a macro reported running a call: where in its input (`None` for no token of it), and what.
 */
@DerivePython[equatable]
@Derive[Equatable]
public struct MacroDiagnostic {
    public MacroDiagnostic(
        public let severity: MacroSeverity,
        public let origin: ?SpanOrigin,
        public let message: String,
        public let hint: String
    ) {}
}

/**
 * What the macro server answered for a macro call (#176): the fingerprint of the request it answered; the last
 * expansion that succeeded and the items it set, which stand when a later run fails; and what the last run reported.
 */
@Derive[Equatable]
public struct MacroOutput {
    public MacroOutput(
        public let fingerprint: Int64,
        public let expansion: ?MappedText,
        public let items: Array<MacroItem>,
        public let diagnostics: Array<MacroDiagnostic>
    ) {}

    /**
     * This answer after `previous`: a run that failed (no expansion) keeps the expansion and the items of the last
     * one that succeeded.
     */
    public func after(previous: ?MacroOutput): MacroOutput {
        match ((expansion, previous)) {
            case (None, Some(old)) where old.expansion.isSome() =>
                MacroOutput(fingerprint, old.expansion, old.items, diagnostics)
            case _ => this
        }
    }
}

/**
 * A macro call of a file as `MacroOutputs` keys it: its item (`loupe.hir`'s `ItemId`, as text, which an edit
 * elsewhere leaves alone), and on it its index among the macros called on it, outermost first; in it, in a body or
 * an initializer (D117), the macro's name as written (`inBody`) and its ordinal among the calls of that name there.
 */
@Derive[Equatable, Hashable]
public struct MacroCallKey <: ToString {
    public MacroCallKey(
        public let item: String,
        public let index: Int64,
        public let inBody!: ?String = None
    ) {}

    public func toString(): String {
        match (inBody) {
            case Some(name) => "${item}/@${name}#${index}"
            case None => "${item}@${index}"
        }
    }
}

/**
 * The macro server's answers for the macro calls of a file, by call. Immutable: `withOutput` makes another.
 */
public class MacroOutputs {
    private let outputs: HashMap<MacroCallKey, MacroOutput>

    public init() {
        outputs = HashMap<MacroCallKey, MacroOutput>()
    }

    private init(outputs: HashMap<MacroCallKey, MacroOutput>) {
        this.outputs = outputs
    }

    public func get(key: MacroCallKey): ?MacroOutput {
        outputs.get(key)
    }

    /**
     * These outputs with `output` for `key`, after the one there (`MacroOutput.after`).
     */
    public func withOutput(key: MacroCallKey, output: MacroOutput): MacroOutputs {
        let copy = outputs.clone()
        copy[key] = output.after(outputs.get(key))
        MacroOutputs(copy)
    }

    public prop size: Int64 {
        get() {
            outputs.size
        }
    }
}
