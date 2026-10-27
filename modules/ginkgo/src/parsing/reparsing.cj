package ginkgo.parsing

import std.collection.ArrayList
import std.sort.*
import ginkgo.*

/**
 * Parses again only the block around an edit, as rust-analyzer's `reparse_block` does: the nearest enclosing
 * node of a block kind has its text, the edit applied, lexed and parsed with the grammar of that kind, and the
 * new node takes the old one's place, everything else shared. The language brings its lexer, how a `Lexed`
 * becomes the parser's `Input`, its trivia rules, the kinds that open and close a block, and the grammar for a
 * block of a kind, `None` for a kind that is no block.
 *
 * A block kind must get no attached trivia (`TriviaRules.attachedTrivia`): parsed on its own, a block has none
 * before it to attach.
 */
public class Reparser<K> where K <: Kind<K> {
    public Reparser(
        let lex: (String) -> Lexed<K>,
        let toInput: (Lexed<K>) -> Input<K>,
        let rules: TriviaRules<K>,
        let eof: K,
        let errorKind: K,
        let open: K,
        let close: K,
        let blockGrammar: (K) -> ?((Parser<K>) -> Unit)
    ) {}

    /**
     * The parse of `parse`'s text with `delete` replaced by `insert`, equal to a full parse of it, made by
     * parsing again the nearest block around the edit that the edit leaves balanced, open to close, and that its
     * grammar then consumes whole. `None` when no block around the edit qualifies, and a full parse is what is
     * left.
     */
    @Frozen
    public func reparse(parse: Parse<K>, delete: TextRange, insert: String): ?Parse<K> {
        let root = parse.syntaxNode()
        if (!root.textRange.containsRange(delete)) {
            return None
        }
        var node =
            match (root.coveringElement(delete)) {
                case SyntaxElement.Node(n) => Some(n)
                case SyntaxElement.Token(t) => Some(t.parent)
            }
        while (let Some(n) <- node) {
            if (let Some(grammar) <- blockGrammar(n.kind)) {
                if (let Some(reparsed) <- reparseBlock(parse, n, grammar, delete, insert)) {
                    return reparsed
                }
            }
            node = n.parent
        }
        None
    }

    @Frozen
    func reparseBlock(
        parse: Parse<K>,
        node: SyntaxNode<K>,
        grammar: (Parser<K>) -> Unit,
        delete: TextRange,
        insert: String
    ): ?Parse<K> {
        let range = node.textRange
        let old = node.text()
        let text = old[..delete.start - range.start] + insert + old[delete.end - range.start..]
        let lexed = lex(text)
        if (!isBalanced(lexed)) {
            return None
        }
        let p = Parser<K>(toInput(lexed), eof, errorKind)
        let block =
            try {
                grammar(p)
                if (!p.atEof()) {
                    return None
                }
                buildTree(lexed, p, rules)
            } catch (e: Exception) {
                return None
            }
        if (block.green.kind != node.kind) {
            return None
        }
        let delta = insert.size - delete.len
        let errors = ArrayList<SyntaxError<K>>()
        for (e in parse.errors) {
            if (e.range.end <= range.start) {
                errors.add(e)
            } else if (e.range.start >= range.end) {
                errors.add(SyntaxError(e.error, e.range.shift(delta)))
            }
        }
        for (e in block.errors) {
            errors.add(SyntaxError(e.error, e.range.shift(range.start)))
        }
        let sorted = errors.toArray()
        sort(
            sorted,
            stable: true,
            by: { a: SyntaxError<K>, b: SyntaxError<K> => a.range.start.compare(b.range.start) }
        )
        Parse(node.replaceWith(block.green), sorted)
    }

    /**
     * Whether the tokens are one block: `open` first, its `close` last, and nothing closing it earlier.
     */
    @Frozen
    func isBalanced(lexed: Lexed<K>): Bool {
        let n = lexed.size
        if (n < 2 || lexed.kind(0) != open || lexed.kind(n - 1) != close) {
            return false
        }
        var depth = 0
        for (i in 0..n) {
            let kind = lexed.kind(i)
            if (kind == open) {
                depth++
            } else if (kind == close) {
                depth--
                if (depth == 0 && i != n - 1) {
                    return false
                }
            }
        }
        depth == 0
    }
}
