package loupe

import std.deriving.*
import ginkgo.TextRange
import loupe.db.AnalysisDatabase
import loupe.hir.*
import loupe.vfs.FileId

/**
 * The macro call at a position (`macroCallAt`): the call whose expansion shows it, and where the call at the position
 * is.
 */
@Derive[Equatable]
public struct MacroCallAt {
    public MacroCallAt(
        /**
         * The call whose expansion the analysis reads that shows what the call at the position adds (`readCallOf`):
         * that call itself, or the outermost call the macro server runs on its top-level item, whose input the call
         * at the position is in, as cjc expands one into the other (D98).
         */
        public let call: MacroCallId,
        /**
         * The head of the call at the position in its file, `@` to the end of its attribute, or of its name.
         */
        public let range: TextRange,
        /**
         * Where what the call at the position added is in the text of `call`'s expansion, when that is another call's
         * (`expansionRangeOf`); `None` for the call itself, or where it cannot be told.
         */
        public let focus!: ?TextRange = None
    ) {}
}

/**
 * Who wrote an expansion.
 */
@Derive[Equatable]
public enum ExpansionKind <: ToString {
    /**
     * The macro server, running a macro of the workspace or of std: its whole output, bodies included (#176).
     */
    | ServerExpansion
    /**
     * The analysis, for a macro of std the server has not expanded (#175): what it declares, signatures only, every
     * body a comment (D118).
     */
    | OwnExpansion

    public func toString(): String {
        match (this) {
            case ServerExpansion => "ServerExpansion"
            case OwnExpansion => "OwnExpansion"
        }
    }
}

/**
 * What a macro call expands to, as the analysis reads it.
 */
@Derive[Equatable]
public struct ExpandedMacro {
    public ExpandedMacro(
        /**
         * The macro's name as the call writes it, `@` and its path, its attribute left out: `@Derive`, `@m.M`.
         */
        public let name: String,
        /**
         * The head of the call in its file (`MacroCallAt.range`).
         */
        public let range: TextRange,
        /**
         * The text of the expansion, which `hoverInExpansion` and `definitionInExpansion` take offsets in and
         * `NavigationTarget.expansion` gives ranges of.
         */
        public let text: String,
        public let kind: ExpansionKind,
        /**
         * The declaration the call is on, as written after the call's head, for an expansion that adds after it
         * rather than replaces it, which cjc's output starts with: one of std's but `@Strategy`'s. `None` otherwise.
         */
        public let declaration!: ?String = None
    ) {}
}

/**
 * The macro call at `offset` of the file, as `MacroCallAt` gives it, as rust-analyzer finds one: the call whose head
 * (`@` to the end of its attribute, or of its name, the end included) it is on; else the outermost call of the
 * innermost item around it with one that expands, from anywhere in the item, or, unless `inBody`, anywhere but in its
 * bodies. A call in a body is one only from its head and if `inBody` (D117). `None` where no call expands: a call of a
 * macro the analysis does not know (an unresolved name), or on a member whose type has no call the server runs
 * (`@DeriveExclude` but under `@Derive`, D98's consequence), has no expansion.
 */
public func macroCallAt(
    db: AnalysisDatabase,
    fileId: FileId,
    offset: Int64,
    inBody!: Bool = true
): ?MacroCallAt {
    let file = db.sourceFile(fileId) ?? return None
    let candidates =
        match (macroCallUnder(db, file, offset)) {
            case Some(under) where inBody || under[0].inBody(db).isNone() => [under]
            case _ => Array<(MacroCallId, TextRange)>()
        }
    for ((under, range) in candidates.concat(macroCallsAround(db, file, offset, inBody))) {
        let call = readCallOf(db, under) ?? continue
        let focus =
            if (call == under) { None<TextRange> } else { expansionRangeOf(db, call, range) }
        return MacroCallAt(call, range, focus: focus)
    }
    None
}

/**
 * What `call` expands to: the macro server's last output that succeeded for a call it runs, read (`ServerCall.read`),
 * or one it runs in an item (D117); else the analysis's own for one of std. `None` for a call whose expansion the
 * analysis does not read: not answered yet, not the call read on its item, or no longer there.
 */
public func expandedMacro(db: AnalysisDatabase, call: MacroCallId): ?ExpandedMacro {
    let file = call.file(db)
    if (call.inBody(db).isSome()) {
        if (!serverCalls(db, file).iterator().any { one => one.call == call }) {
            return None
        }
        let output = macroOutputOf(db, call).flatMap { one => one.expansion } ?? return None
        let (name, range) = macroCallHeadOf(db, call) ?? return None
        return ExpandedMacro(name, range, output.text, ExpansionKind.ServerExpansion)
    }
    if (!expandedCalls(db, file).contains(call)) {
        return None
    }
    let (name, range) = macroCallHeadOf(db, call) ?? return None
    let answered =
        serverCalls(db, file).iterator().any { one => one.read && one.call == call } &&
            macroOutputOf(db, call).flatMap { output => output.expansion }.isSome()
    let kind = if (answered) { ExpansionKind.ServerExpansion } else { ExpansionKind.OwnExpansion }
    let expansion = macroExpansion(db, call)
    let declaration = if (expansion.replaces) { None<String> } else { declarationUnder(db, call) }
    ExpandedMacro(name, range, expansion.text, kind, declaration: declaration)
}
