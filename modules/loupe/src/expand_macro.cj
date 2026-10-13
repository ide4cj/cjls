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
         * that call itself, or the outermost call of a workspace macro on its top-level item, whose input the call at
         * the position is in, as cjc expands one into the other (D98).
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
     * The macro server, running a macro of the workspace: its whole output, bodies included (#176).
     */
    | WorkspaceExpansion
    /**
     * The analysis, for a macro of std (#175): what it declares, signatures only, every body empty.
     */
    | StdExpansion

    public func toString(): String {
        match (this) {
            case WorkspaceExpansion => "WorkspaceExpansion"
            case StdExpansion => "StdExpansion"
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
        public let kind: ExpansionKind
    ) {}
}

/**
 * The macro call whose head (`@` to the end of its attribute, or of its name, the end included) is at `offset` of the
 * file, as `MacroCallAt` gives it; `None` off any head, on a call in a body, and on a call nothing expands: a macro
 * the analysis does not know (`@DeriveExclude`, an unresolved name), or a call of the workspace on a member whose type
 * has no call of the workspace (D98's consequence).
 */
public func macroCallAt(db: AnalysisDatabase, fileId: FileId, offset: Int64): ?MacroCallAt {
    let file = db.sourceFile(fileId) ?? return None
    let (under, range) = macroCallUnder(db, file, offset) ?? return None
    let call = readCallOf(db, under) ?? return None
    let focus = if (call == under) {
        None<TextRange>
    } else {
        expansionRangeOf(db, call, range)
    }
    MacroCallAt(call, range, focus: focus)
}

/**
 * What `call` expands to: the macro server's last output that succeeded for a call of the workspace, read
 * (`WorkspaceCall.read`); the analysis's own for one of std. `None` for a call whose expansion the analysis does not
 * read: not answered yet, not the call read on its item, or no longer there.
 */
public func expandedMacro(db: AnalysisDatabase, call: MacroCallId): ?ExpandedMacro {
    let file = call.file(db)
    if (!expandedCalls(db, file).contains(call)) {
        return None
    }
    let (name, range) = macroCallHeadOf(db, call) ?? return None
    let kind = if (workspaceCalls(db, file).iterator().any {one => one.call == call}) {
        ExpansionKind.WorkspaceExpansion
    } else {
        ExpansionKind.StdExpansion
    }
    ExpandedMacro(name, range, macroExpansion(db, call).text, kind)
}
