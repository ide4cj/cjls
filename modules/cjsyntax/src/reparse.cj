package cjsyntax

import ginkgo.*
import ginkgo.parsing.*

let REPARSER = Reparser<SyntaxKind>(tokenize, inputOf, CangjieTrivia(), Eof, ErrorNode, LBrace, RBrace, blockGrammar)

/**
 * The parse of `before`'s text with `delete` replaced by `insert`: what `parse` gives for the new text, made by
 * parsing again only the nearest `Block` around the edit when the edit leaves it balanced
 * (`ginkgo.parsing.Reparser`), and the whole text otherwise.
 */
public func reparse(before: CjParse, delete: TextRange, insert: String): CjParse {
    if (let Some(reparsed) <- REPARSER.reparse(before, delete, insert)) {
        return reparsed
    }
    let old = before.green.toString()
    parse(old[..delete.start] + insert + old[delete.end..])
}

/**
 * The blocks parsed on their own: a `Block`, whose grammar starts at its `{`. A `DeclBody` is not one, since its
 * grammar depends on the declaration around it.
 */
func blockGrammar(kind: SyntaxKind): ?((P) -> Unit) {
    match (kind) {
        case Block => Some(block)
        case _ => None
    }
}
