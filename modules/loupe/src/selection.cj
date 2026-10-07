package loupe

import std.collection.*
import std.unicode.*
import ginkgo.{Direction, SyntaxElement, TokenAtOffset, TokenSet}
import cjsyntax.{CjSyntaxNode, CjSyntaxToken, SyntaxKind}
import loupe.vfs.FileId
import loupe.db.AnalysisDatabase
import loupe.syntax.parse

/**
 * Tokens whose words are selected on their own: comments and the pieces of a string.
 */
let WORDY = TokenSet<SyntaxKind>([SyntaxKind.LineComment, SyntaxKind.BlockComment, SyntaxKind.StringContent,
    SyntaxKind.RawStringLit])

/**
 * Nodes whose elements are separated by commas.
 */
let LISTS = TokenSet<SyntaxKind>([SyntaxKind.ArgList, SyntaxKind.AnnotationArgList, SyntaxKind.ParamList,
    SyntaxKind.LambdaParamList, SyntaxKind.TypeParamList, SyntaxKind.TypeArgList, SyntaxKind.TupleType,
    SyntaxKind.FuncType, SyntaxKind.TuplePat, SyntaxKind.EnumPat, SyntaxKind.EnumCtor, SyntaxKind.TupleExpr,
    SyntaxKind.ArrayExpr, SyntaxKind.ImportTreeList, SyntaxKind.ResourceList])

/**
 * The ranges a selection at `offset` widens through, innermost first, each strictly containing the
 * one before, the last the whole file: the token there, a word of it first in a comment or a
 * string, then the nodes around it, an element of a list with its comma before the list. Empty for
 * a file the database does not know.
 *
 * Not a query: it is keyed by a position (A2, A3). What it reads, `parse`, is one.
 */
public func extendSelection(db: AnalysisDatabase, fileId: FileId, offset: Int64): Array<TextRange> {
    let file = db.sourceFile(fileId) ?? return []
    selectionsAt(parse(db, file).syntaxNode(), offset)
}

/**
 * The selections of `root`'s tree at `offset`; only the whole of it for an offset outside it.
 */
func selectionsAt(root: CjSyntaxNode, offset: Int64): Array<TextRange> {
    let chain = SelectionChain()
    if (let Some(token) <- tokenToSelect(root.tokenAtOffset(offset))) {
        if (WORDY.contains(token.kind) && let Some(word) <- wordAt(token, offset)) {
            chain.add(word)
        }
        chain.add(token.textRange)
        for (node in token.ancestors()) {
            chain.add(node.textRange)
            if (let Some(list) <- node.parent && LISTS.contains(list.kind) && let Some(range) <- withComma(node)) {
                chain.add(range)
            }
        }
    }
    chain.add(root.textRange)
    chain.ranges.toArray()
}

class SelectionChain {
    let ranges = ArrayList<TextRange>()

    /**
     * `range`, if it widens the last: a node of one child adds nothing.
     */
    func add(range: TextRange): Unit {
        if (let Some(last) <- ranges.last && (range == last || !range.containsRange(last))) {
            return
        }
        ranges.add(range)
    }
}

/**
 * Between two tokens the one more worth selecting: a name, a keyword or a literal over punctuation
 * and a comment, either over white space; the left one of two alike.
 */
func tokenToSelect(found: TokenAtOffset<CjSyntaxToken>): ?CjSyntaxToken {
    match (found) {
        case Single(token) => token
        case Between(left, right) => if (selectionPriority(right.kind) > selectionPriority(left.kind)) {
            right
        } else {
            left
        }
        case NoToken => None
    }
}

func selectionPriority(kind: SyntaxKind): Int64 {
    if (kind == SyntaxKind.Whitespace || kind == SyntaxKind.Newline) {
        0
    } else if (kind.isTrivia() || kind.isPunctuation()) {
        1
    } else {
        2
    }
}

/**
 * The word of `token` `offset` is in or at an end of: letters, digits and `_`. `None` where there
 * is none, or it is the whole token.
 */
func wordAt(token: CjSyntaxToken, offset: Int64): ?TextRange {
    let bytes = token.text().toArray()
    let at = offset - token.textRange.start
    var position = 0
    var start = -1
    while (position <= bytes.size) {
        let (rune, size) = if (position < bytes.size) {
            Rune.fromUtf8(bytes, position)
        } else {
            (r' ', 0)
        }
        if (rune == r'_' || rune.isLetter() || rune.isNumber()) {
            if (start < 0) {
                start = position
            }
        } else {
            if (start >= 0 && start <= at && at <= position) {
                if (start == 0 && position == bytes.size) {
                    return None
                }
                return TextRange(token.textRange.start + start, token.textRange.start + position)
            }
            start = -1
        }
        if (position == bytes.size) {
            break
        }
        position += size
    }
    None
}

/**
 * `element` with the comma after it and the spaces after that, or for the last of a list the comma
 * before it; `None` if neither is there.
 */
func withComma(element: CjSyntaxNode): ?TextRange {
    let range = element.textRange
    if (let Some(comma) <- commaBeside(element, Direction.Next)) {
        let end = match (comma.nextSiblingOrToken()) {
            case Some(SyntaxElement.Token(space)) where space.kind == SyntaxKind.Whitespace => space.textRange.end
            case _ => comma.textRange.end
        }
        return TextRange(range.start, end)
    }
    let comma = commaBeside(element, Direction.Prev) ?? return None
    TextRange(comma.textRange.start, range.end)
}

/**
 * The comma next to `element` in `direction`, spaces on one line between them.
 */
func commaBeside(element: CjSyntaxNode, direction: Direction): ?CjSyntaxToken {
    let beside = element.siblingsWithTokens(direction) |> skip(1) |>
        filter {it: SyntaxElement<SyntaxKind> => it.kind != SyntaxKind.Whitespace} |> first
    match (beside) {
        case Some(SyntaxElement.Token(token)) where token.kind == SyntaxKind.Comma => token
        case _ => None
    }
}
