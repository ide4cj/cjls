package ginkgo.parsing

import std.deriving.*
import ginkgo.*

/**
 * A toy language for the tests: integers, `+`, `*` and `>>` over lines, `(...)` groups, `#` comments.
 */
@Derive[Equatable, Hashable]
enum Toy {
    | Num
    | Plus
    | Star
    | Gt
    | Shr
    | LParen
    | RParen
    | Ws
    | Newline
    | Comment
    | Bad
    | Eof
    | Root
    | Line
    | Bin
    | Lit
    | Group
    | ErrorNode

    public func ordinal(): Int64 {
        match (this) {
            case Num => 0
            case Plus => 1
            case Star => 2
            case Gt => 3
            case Shr => 4
            case LParen => 5
            case RParen => 6
            case Ws => 7
            case Newline => 8
            case Comment => 9
            case Bad => 10
            case Eof => 11
            case Root => 12
            case Line => 13
            case Bin => 14
            case Lit => 15
            case Group => 16
            case ErrorNode => 17
        }
    }

    public func toString(): String {
        match (this) {
            case Num => "Num"
            case Plus => "Plus"
            case Star => "Star"
            case Gt => "Gt"
            case Shr => "Shr"
            case LParen => "LParen"
            case RParen => "RParen"
            case Ws => "Ws"
            case Newline => "Newline"
            case Comment => "Comment"
            case Bad => "Bad"
            case Eof => "Eof"
            case Root => "Root"
            case Line => "Line"
            case Bin => "Bin"
            case Lit => "Lit"
            case Group => "Group"
            case ErrorNode => "ErrorNode"
        }
    }
}

extend Toy <: Kind<Toy> {}

class ToyTrivia <: TriviaRules<Toy> {
    public func isTrivia(kind: Toy): Bool {
        kind == Ws || kind == Newline || kind == Comment
    }

    /**
     * A comment right before a line, with no blank line in between, belongs to it.
     */
    public func attachedTrivia(kind: Toy, trivia: Array<(Toy, String)>): Int64 {
        if (kind != Line) {
            return 0
        }
        var attached = 0
        var i = trivia.size - 1
        while (i >= 0) {
            let (k, text) = trivia[i]
            if (k == Comment) {
                attached = trivia.size - i
            } else if (k == Newline && text.size > 1) {
                break
            }
            i--
        }
        attached
    }
}

func toyLex(text: String): Lexed<Toy> {
    let lexed = Lexed<Toy>(text)
    let bytes = text.toArray()
    var i = 0
    while (i < bytes.size) {
        let start = i
        let b = bytes[i]
        let kind = if (b >= b'0' && b <= b'9') {
            while (i < bytes.size && bytes[i] >= b'0' && bytes[i] <= b'9') {
                i++
            }
            Num
        } else if (b == b' ') {
            while (i < bytes.size && bytes[i] == b' ') {
                i++
            }
            Ws
        } else if (b == b'\n') {
            while (i < bytes.size && bytes[i] == b'\n') {
                i++
            }
            Newline
        } else if (b == b'#') {
            while (i < bytes.size && bytes[i] != b'\n') {
                i++
            }
            Comment
        } else {
            i++
            match (b) {
                case b'+' => Plus
                case b'*' => Star
                case b'>' => Gt
                case b'(' => LParen
                case b')' => RParen
                case _ => Bad
            }
        }
        lexed.push(kind, i - start)
        if (kind == Bad) {
            lexed.error("unknown character")
        }
    }
    lexed
}

/**
 * root: line*; line: expr, ended by a newline; expr: precedence climbing over `>>` < `+` < `*`, over numbers
 * and groups in parentheses.
 */
func toyParse(text: String): Parse<Toy> {
    let lexed = toyLex(text)
    let p = toyParser(lexed)
    toyRoot(p)
    buildTree(lexed, p, ToyTrivia())
}

func toyRoot(p: Parser<Toy>): Unit {
    let root = p.start()
    while (!p.atEof()) {
        let line = p.start()
        toyExpr(p, 0)
        while (!p.atEof() && !p.newlineBefore()) {
            p.errAndBump("expected a newline")
        }
        line.complete(p, Line)
    }
    root.complete(p, Root)
}

func toyInput(lexed: Lexed<Toy>): Input<Toy> {
    let trivia = ToyTrivia()
    lexed.toInput({k => trivia.isTrivia(k)}, {k => k == Newline})
}

func toyParser(lexed: Lexed<Toy>): Parser<Toy> {
    Parser<Toy>(toyInput(lexed), Eof, ErrorNode)
}

func toyExpr(p: Parser<Toy>, minPower: Int64): Unit {
    var lhs = if (p.at(Num)) {
        let m = p.start()
        p.bump(Num)
        m.complete(p, Lit)
    } else if (p.at(LParen)) {
        toyGroup(p)
    } else {
        p.errAndBump("expected a number")
        return
    }
    while (true) {
        let (power, op, n) = if (p.at(Star)) {
            (3, Star, 1)
        } else if (p.at(Plus)) {
            (2, Plus, 1)
        } else if (p.atComposite([Gt, Gt])) {
            (1, Shr, 2)
        } else {
            return
        }
        if (power <= minPower) {
            return
        }
        let m = lhs.precede(p)
        p.bumpComposite(op, n)
        toyExpr(p, power)
        lhs = m.complete(p, Bin)
    }
}

/**
 * `(` expr `)`: the block of the toy language, which `Reparser` parses on its own.
 */
func toyGroup(p: Parser<Toy>): CompletedMarker<Toy> {
    let m = p.start()
    p.bump(LParen)
    toyExpr(p, 0)
    p.expect(RParen)
    m.complete(p, Group)
}

func toyGroupAlone(p: Parser<Toy>): Unit {
    toyGroup(p)
    return
}

func toyBlockGrammar(kind: Toy): ?((Parser<Toy>) -> Unit) {
    match (kind) {
        case Group => Some(toyGroupAlone)
        case _ => None<(Parser<Toy>) -> Unit>
    }
}

func toyReparser(): Reparser<Toy> {
    Reparser<Toy>(toyLex, toyInput, ToyTrivia(), Eof, ErrorNode, LParen, RParen, toyBlockGrammar)
}
