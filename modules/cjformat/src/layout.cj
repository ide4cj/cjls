package cjformat

import std.collection.ArrayList
import cjsyntax.{CjSyntaxElement, CjSyntaxNode, CjSyntaxToken, SyntaxKind}
import cjsyntax.ast.Expr
import ginkgo.{SyntaxElement, TextRange}

/**
 * Trivia stays in source order. A comment between children is trailing when its first byte is
 * on the preceding child's line, leading otherwise; comments in empty delimiters are dangling.
 * Keeping this attachment local prevents moving a comment across an operator or delimiter.
 */
class LayoutBuilder {
    LayoutBuilder(
        private let source: String,
        private let options!: FormatOptions = FormatOptions(),
        private let target!: ?CjSyntaxNode = None,
        private let position!: ?LayoutPosition = None
    ) {}

    func node(n: CjSyntaxNode, includeLeading!: Bool = false): Doc {
        if (includeLeading) {
            let leading = leadingComments(n)
            if (!leading.isEmpty()) {
                let docs = leading.map { p => concat([element(p), hardline()]) }
                return concat([concat(docs), node(n)])
            }
        }
        mark(n, nodeBody(n))
    }

    private func mark(n: CjSyntaxNode, doc: Doc): Doc {
        if (target == Some(n)) {
            if (let Some(at) <- position) {
                return positioned(doc, at)
            }
        }
        doc
    }

    private func nodeBody(n: CjSyntaxNode): Doc {
        if (n.kind == StringLit) {
            return verbatim(n.text())
        }
        if (isOpaque(n.kind)) {
            return opaque(n)
        }
        let parts = partsOf(n)
        var first = 0
        if (n.kind != Param && n.kind != LambdaExpr) {
            while (first < parts.size && parts[first].kind == Annotation) {
                first++
            }
        }
        if (first > 0) {
            return concat(
                [sequence(parts[..first], n.kind), hardline(), layoutParts(n, parts[first..])]
            )
        }
        layoutParts(n, parts)
    }

    private func layoutParts(n: CjSyntaxNode, parts: Array<CjSyntaxElement>): Doc {
        match (n.kind) {
            case SourceFile | StmtsFile =>
                if (parts.isEmpty()) {
                    return textDoc("")
                }
                concat([sequence(parts, n.kind, statements: true), hardline()])
            case Block | DeclBody | EnumBody | PropBody | MatchBody | ForeignBlock =>
                body(parts, n.kind)
            case LambdaExpr => lambda(parts)
            case IfExpr => ifExpression(n, parts)
            case MatchCase => matchCase(parts)
            case VarDecl | TypeAliasDecl | ResourceDecl => assignment(parts, n.kind)
            case FuncDecl |
                MainDecl |
                MacroDecl |
                ClassDecl |
                InterfaceDecl |
                StructDecl |
                EnumDecl |
                ExtendDecl |
                PropDecl |
                InitDecl |
                FinalizerDecl |
                PrimaryInitDecl |
                PropAccessor => declaration(parts, n.kind)
            case BinExpr | IsExpr | AsExpr | TypeBoundList | WhereClause | GenericConstraint =>
                group(sequence(parts, n.kind, continuation: true))
            case MemberAccessExpr |
                CallExpr |
                IndexExpr |
                OptionalExpr |
                PostfixExpr |
                TrailingLambdaExpr => chain(n)
            case _ => group(sequence(parts, n.kind))
        }
    }

    /**
     * Parser trivia ownership is for documentation lookup, not visual comment attachment.
     */
    private func partsOf(n: CjSyntaxNode): Array<CjSyntaxElement> {
        let parts = ArrayList<CjSyntaxElement>()
        var isLeading = n.parent.isSome()
        for (p in n.childrenWithTokens()) {
            if (isSpace(p.kind)) {
                continue
            }
            if (isLeading && isComment(p.kind)) {
                continue
            }
            isLeading = false
            if (let Some(child) <- p.asNode()) {
                parts.add(all: leadingComments(child))
            }
            parts.add(p)
        }
        parts.toArray()
    }

    private func leadingComments(n: CjSyntaxNode): Array<CjSyntaxElement> {
        let result = ArrayList<CjSyntaxElement>()
        if (isOpaque(n.kind)) {
            return []
        }
        for (p in n.childrenWithTokens()) {
            if (!p.kind.isTrivia()) {
                break
            }
            if (isComment(p.kind)) {
                result.add(p)
            }
        }
        result.toArray()
    }

    private func startOf(p: CjSyntaxElement): Int64 {
        if (let Some(n) <- p.asNode()) {
            for (child in n.childrenWithTokens()) {
                if (!child.kind.isTrivia()) {
                    return child.textRange.start
                }
            }
        }
        p.textRange.start
    }

    private func element(p: CjSyntaxElement): Doc {
        match (p) {
            case SyntaxElement.Node(n) => node(n)
            case SyntaxElement.Token(t) =>
                if (isComment(t.kind)) { comment(t) } else { textDoc(t.text()) }
        }
    }

    /**
     * Only complete, comment-free expression branches may share a line.
     */
    private func ifExpression(n: CjSyntaxNode, parts: Array<CjSyntaxElement>): Doc {
        match (options.simpleIf) {
            case SimpleIf.Multiline => return group(sequence(parts, IfExpr))
            case _ => ()
        }
        // An else-if chain uses one layout throughout, including its final if/else pair.
        if (n.parent.map { parent => parent.kind == IfExpr } ?? false) {
            return group(sequence(parts, IfExpr))
        }
        var branches = 0
        for (part in parts) {
            if (isComment(part.kind) || part.kind == IfExpr) {
                return group(sequence(parts, IfExpr))
            }
            if (let Some(n) <- part.asNode()) {
                if (n.descendantsWithTokens().any { e => isComment(e.kind) }) {
                    return group(sequence(parts, IfExpr))
                }
                if (part.kind == Block) {
                    let children = partsOf(n)
                    if (children.size != 3 || !Expr.canCast(children[1].kind)) {
                        return group(sequence(parts, IfExpr))
                    }
                    branches++
                }
            }
        }
        if (branches != 2) {
            return group(sequence(parts, IfExpr))
        }
        let flat = ArrayList<Doc>()
        let broken = ArrayList<Doc>()
        for (i in 0..parts.size) {
            let part = parts[i]
            if (i > 0) {
                let space = tokenSeparator(parts[i - 1], part, IfExpr, continuation: false)
                flat.add(space)
                broken.add(space)
            }
            if (part.kind == Block) {
                let block = part.asNode().getOrThrow()
                // Share the expression document between alternatives: rebuilding it for both
                // layouts would multiply work at each level of nested if expressions.
                let expression = element(partsOf(block)[1])
                flat.add(mark(block, concat([textDoc("{ "), expression, textDoc(" }")])))
                broken
                    .add(
                        mark(
                            block,
                            concat(
                                [
                                    textDoc("{"),
                                    indent(concat([hardline(), expression])),
                                    hardline(),
                                    textDoc("}")
                                ]
                            )
                        )
                    )
            } else {
                let doc = element(part)
                flat.add(doc)
                broken.add(doc)
            }
        }
        group(ifBreak(concat(broken.toArray()), concat(flat.toArray())))
    }

    private func assignment(parts: Array<CjSyntaxElement>, context: SyntaxKind): Doc {
        let equals = indexOfKind(parts, Eq) ?? return group(sequence(parts, context))
        group(
            concat(
                [
                    sequence(parts[..equals + 1], context),
                    indent(concat([softline(), sequence(parts[equals + 1..], context)]))
                ]
            )
        )
    }

    private func declaration(parts: Array<CjSyntaxElement>, context: SyntaxKind): Doc {
        if (parts.isEmpty()) {
            return textDoc("")
        }
        let last = parts[parts.size - 1]
        match (last.kind) {
            case Block | DeclBody | EnumBody | PropBody =>
                concat(
                    [
                        group(sequence(parts[..parts.size - 1], context)),
                        if (parts.size > 1 && parts[parts.size - 2].kind == LineComment) {
                            hardline()
                        } else {
                            textDoc(" ")
                        },
                        element(last)
                    ]
                )
            case _ => group(sequence(parts, context))
        }
    }

    /**
     * Bodies have one statement per line, regardless of the input's line breaks.
     */
    private func body(parts: Array<CjSyntaxElement>, context: SyntaxKind): Doc {
        let open = indexOfKind(parts, LBrace) ?? return sequence(parts, context)
        let close = parts.size - 1
        let prefix = sequence(parts[..open], context)
        let content = parts[open + 1..close]
        let brace = if (open == 0) { textDoc("{") } else { concat([prefix, textDoc(" {")]) }
        if (content.isEmpty()) {
            return concat([brace, textDoc("}")])
        }
        concat(
            [
                brace,
                indent(concat([hardline(), sequence(content, context, statements: true)])),
                hardline(),
                element(parts[close])
            ]
        )
    }

    /**
     * Single-expression lambdas can flatten; a statement sequence must keep its separators.
     */
    private func lambda(parts: Array<CjSyntaxElement>): Doc {
        let open = indexOfKind(parts, LBrace) ?? return sequence(parts, LambdaExpr)
        let content = parts[open + 1..parts.size - 1]
        let arrow = indexOfKind(content, FatArrow)
        let bodyStart = arrow.map { i => i + 1 } ?? 0
        let statements =
            content[bodyStart..].filter { p => !isComment(p.kind) && p.kind != Semicolon }
        let mustBreak = statements.size > 1
        let header = sequence(content[..bodyStart], LambdaExpr)
        let body = sequence(content[bodyStart..], LambdaExpr, statements: true)
        let inner =
            if (bodyStart == 0) {
                body
            } else {
                concat([header, if (mustBreak) { hardline() } else { softline() }, body])
            }
        if (content.isEmpty()) {
            return concat([sequence(parts[..open], LambdaExpr), textDoc("{}")])
        }
        group(
            concat(
                [
                    sequence(parts[..open], LambdaExpr),
                    textDoc("{"),
                    indent(concat([if (mustBreak) { hardline() } else { softline() }, inner])),
                    if (mustBreak) { hardline() } else { softline() },
                    textDoc("}")
                ]
            )
        )
    }

    private func matchCase(parts: Array<CjSyntaxElement>): Doc {
        let arrow = indexOfKind(parts, FatArrow) ?? return sequence(parts, MatchCase)
        let tail = parts[arrow + 1..]
        let count = tail.filter { p => !isComment(p.kind) && p.kind != Semicolon }.size
        concat(
            [
                group(sequence(parts[..arrow + 1], MatchCase, continuation: true)),
                group(
                    indent(
                        concat(
                            [
                                if (count > 1) { hardline() } else { softline() },
                                sequence(tail, MatchCase, statements: true)
                            ]
                        )
                    )
                )
            ]
        )
    }

    /**
     * A whole postfix chain shares one continuation indent, including calls after each dot.
     */
    private func chain(n: CjSyntaxNode): Doc {
        let links = ArrayList<CjSyntaxNode>()
        var base = n
        while (isChain(base.kind)) {
            let children = partsOf(base)
            if (children.isEmpty()) {
                break
            }
            let receiver = children[0].asNode() ?? break
            links.add(base)
            base = receiver
        }
        let head = ArrayList<Doc>([node(base)])
        let suffix = ArrayList<Doc>()
        var hasMember = false
        for (i in 0..links.size) {
            let link = links[links.size - i - 1]
            let children = partsOf(link)
            if (link.kind == MemberAccessExpr) {
                hasMember = true
            }
            let target = if (hasMember) { suffix } else { head }
            if (link.kind == MemberAccessExpr) {
                target.add(softbreak())
            } else if (link.kind == TrailingLambdaExpr) {
                target.add(textDoc(" "))
            }
            target.add(sequence(children[1..], link.kind))
        }
        group(concat([concat(head.toArray()), indent(concat(suffix.toArray()))]))
    }

    /**
     * Delimited lists choose between one line and one element per line.
     */
    private func delimited(
        parts: Array<CjSyntaxElement>,
        context: SyntaxKind,
        grouped!: Bool = true
    ): Doc {
        if (parts.size == 2) {
            return concat([element(parts[0]), element(parts[1])])
        }
        let doc =
            concat(
                [
                    element(parts[0]),
                    indent(concat([softbreak(), sequence(parts[1..parts.size - 1], context)])),
                    softbreak(),
                    element(parts[parts.size - 1])
                ]
            )
        if (grouped) { group(doc) } else { doc }
    }

    private func sequence(
        parts: Array<CjSyntaxElement>,
        context: SyntaxKind,
        statements!: Bool = false,
        continuation!: Bool = false
    ): Doc {
        let docs = ArrayList<Doc>()
        var i = 0
        while (i < parts.size) {
            let current = parts[i]
            if (i > 0) {
                docs
                    .add(
                        separator(
                            parts[i - 1],
                            current,
                            context,
                            statements: statements,
                            continuation: continuation
                        )
                    )
            }
            if (current.kind == LineComment && i > 0 && !hasNewline(parts[i - 1], current)) {
                docs
                    .add(
                        lineSuffix(
                            textDoc(
                                " ${source[current.textRange.start..current.textRange.end].trimAsciiEnd()}"
                            )
                        )
                    )
                docs.add(hardline())
                i++
                continue
            }
            if (let Some(end) <- delimiterEnd(parts, i, context)) {
                docs.add(delimited(parts[i..end + 1], context))
                i = end + 1
            } else {
                if (current.kind == ParamList && isFunctionDeclaration(context)) {
                    let parameters =
                        current.asNode() ??
                            throw IllegalStateException("a parameter list is a node")
                    // The signature chooses the parameter layout as a whole, reserving its return
                    // type and body brace before resorting to breaks inside nested types.
                    docs.add(delimited(partsOf(parameters), ParamList, grouped: false))
                } else {
                    docs.add(element(current))
                }
                i++
            }
        }
        if (continuation && docs.size > 1) {
            return concat([docs[0], indent(concat(docs.toArray()[1..]))])
        }
        concat(docs.toArray())
    }

    private func separator(
        before: CjSyntaxElement,
        after: CjSyntaxElement,
        context: SyntaxKind,
        statements!: Bool,
        continuation!: Bool
    ): Doc {
        let a = before.kind
        let b = after.kind
        if (a == LineComment) {
            return sourceBreak(before, after)
        }
        if (isComment(b)) {
            if (hasNewline(before, after)) {
                return sourceBreak(before, after)
            }
            return if (b == LineComment) { textDoc("") } else { textDoc(" ") }
        }
        if (isComment(a)) {
            return if (hasNewline(before, after)) {
                sourceBreak(before, after)
            } else {
                textDoc(" ")
            }
        }
        if (b == Semicolon) {
            return textDoc("")
        }
        if (statements) {
            if (context == EnumBody && a == Pipe) {
                return textDoc(" ")
            }
            return sourceBreak(before, after)
        }
        tokenSeparator(before, after, context, continuation: continuation)
    }

    /**
     * Spaces and optional breaks between significant tokens within one syntax node.
     */
    private func tokenSeparator(
        before: CjSyntaxElement,
        after: CjSyntaxElement,
        context: SyntaxKind,
        continuation!: Bool
    ): Doc {
        let a = before.kind
        let b = after.kind
        if (isAnnotationEnd(before, after, context)) {
            return hardline()
        }
        if (isTightBefore(b)) {
            return textDoc("")
        }
        if (a == Comma) {
            return softline()
        }
        // Joining this pair can turn `(a < b, c >\n(d))` into a generic call.
        // A break after the comparison is legal and keeps the parser's follower test unambiguous.
        if (context == BinExpr && a == Gt && (b == ParenExpr || b == TupleExpr || b == UnitExpr)) {
            return hardline()
        }
        if (isTightAfter(a)) {
            return textDoc("")
        }
        if (context == UnaryExpr && a == Minus && b == UnaryExpr) {
            return textDoc(" ")
        }
        if (isTightContext(context) || isAttachedSuffix(b)) {
            return textDoc("")
        }
        if ((a == Lt || b == Gt) && isAngleContext(context)) {
            return textDoc("")
        }
        if (
            context == RangeExpr && (a == DotDot || b == DotDot || a == DotDotEq || b == DotDotEq)
        ) {
            return textDoc("")
        }
        if (b == LParen) {
            return if (context == EnumCtor || context == EnumPat || context == FuncType ||
                context == TypeConvExpr) {
                textDoc("")
            } else {
                textDoc(" ")
            }
        }
        if (a == Semicolon) {
            return hardline()
        }
        if (continuation && isOperator(a)) {
            return softline()
        }
        textDoc(" ")
    }

    private func sourceBreak(before: CjSyntaxElement, after: CjSyntaxElement): Doc {
        let gap = source[before.textRange.end..startOf(after)]
        if (gap.count("\n") > 1) { blankline() } else { hardline() }
    }

    private func hasNewline(before: CjSyntaxElement, after: CjSyntaxElement): Bool {
        source[before.textRange.end..startOf(after)].contains("\n")
    }

    /**
     * Move only whitespace at line starts; a string token inside a macro is never rewritten.
     */
    private func opaque(n: CjSyntaxNode): Doc {
        let ranges = ArrayList<TextRange>()
        var isLineStart = false
        for (e in n.descendantsWithTokens()) {
            let t = e.asToken() ?? continue
            if (t.kind == Newline) {
                isLineStart = true
            } else if (isLineStart) {
                let start = t.textRange.start - n.textRange.start
                ranges
                    .add(
                        TextRange(
                            start,
                            start + if (t.kind == Whitespace) { t.textRange.len } else { 0 }
                        )
                    )
                isLineStart = false
            }
        }
        reindented(n.text(), originalIndent(n.textRange.start), ranges.toArray())
    }

    private func comment(t: CjSyntaxToken): Doc {
        let value =
            String
                .join(
                    t.text().split("\n").map { line => line.trimAsciiEnd() },
                    delimiter: lineBreakIn(source)
                )
        let ranges = ArrayList<TextRange>()
        var offset = 0
        for (line in value.split("\n")) {
            if (offset > 0 && !line.trimAscii().isEmpty()) {
                ranges.add(TextRange(offset, offset + line.size - line.trimAsciiStart().size))
            }
            offset += line.size + 1
        }
        reindented(value, originalIndent(t.textRange.start), ranges.toArray())
    }

    private func originalIndent(offset: Int64): Int64 {
        var start = offset
        while (start > 0 && source[start - 1] != b'\n') {
            start--
        }
        var end = start
        while (end < source.size && (source[end] == b' ' || source[end] == b'\t')) {
            end++
        }
        end - start
    }
}

/**
 * Whether a node's internal layout must be preserved.
 */
func isOpaque(kind: SyntaxKind): Bool {
    match (kind) {
        case QuoteExpr | MacroArgs | MacroAttr | StringLit => true
        case _ => false
    }
}

/**
 * Whether a postfix node extends the same receiver chain.
 */
private func isChain(kind: SyntaxKind): Bool {
    match (kind) {
        case MemberAccessExpr |
            CallExpr |
            IndexExpr |
            OptionalExpr |
            PostfixExpr |
            TrailingLambdaExpr => true
        case _ => false
    }
}

/**
 * Whether angle brackets delimit types rather than comparisons.
 */
private func isAngleContext(kind: SyntaxKind): Bool {
    kind == TypeArgList || kind == TypeParamList || kind == VArrayType
}

/**
 * Whether an operator permits a following continuation break.
 */
private func isOperator(kind: SyntaxKind): Bool {
    match (kind) {
        case Eq |
            Plus |
            Minus |
            Star |
            StarStar |
            Slash |
            Percent |
            Amp |
            Pipe |
            Caret |
            AmpAmp |
            PipePipe |
            Lt |
            Gt |
            LtEq |
            GtEq |
            EqEq |
            BangEq |
            LtLt |
            GtGt |
            QuestionQuestion |
            PipeGt |
            TildeGt |
            LtColon |
            Arrow |
            LArrow |
            FatArrow => true
        case _ => false
    }
}

/**
 * Whether the following declaration starts on its own line.
 */
private func isAnnotationEnd(
    before: CjSyntaxElement,
    after: CjSyntaxElement,
    context: SyntaxKind
): Bool {
    if (before.kind == Annotation) {
        return context != Param && context != LambdaExpr
    }
    (
        context == MacroExpandDecl &&
            (after.asNode().map { n => n.kind != MacroArgs && n.kind != MacroAttr } ?? false) &&
            (before.kind == NameRef || before.kind == MacroAttr)
    )
}

/**
 * Finds the matching direct delimiter; children already own their nested delimiters.
 */
private func delimiterEnd(
    parts: Array<CjSyntaxElement>,
    start: Int64,
    context: SyntaxKind
): ?Int64 {
    let close =
        match (parts[start].kind) {
            case LParen => RParen
            case LBracket => RBracket
            case LBrace where context == ImportTreeList || context == FeaturesDirective => RBrace
            case Lt where isAngleContext(context) => Gt
            case _ => return None
        }
    for (i in start + 1..parts.size) {
        if (parts[i].kind == close) {
            return Some(i)
        }
    }
    None
}

/**
 * Finds the first direct element of the requested kind.
 */
private func indexOfKind(parts: Array<CjSyntaxElement>, kind: SyntaxKind): ?Int64 {
    for (i in 0..parts.size) {
        if (parts[i].kind == kind) {
            return Some(i)
        }
    }
    None
}

/**
 * Whether a declaration's signature controls its parameter layout.
 */
private func isFunctionDeclaration(kind: SyntaxKind): Bool {
    match (kind) {
        case FuncDecl |
            MainDecl |
            MacroDecl |
            InitDecl |
            FinalizerDecl |
            PrimaryInitDecl |
            PropAccessor => true
        case _ => false
    }
}

/**
 * Punctuation that attaches to its preceding token.
 */
private func isTightBefore(kind: SyntaxKind): Bool {
    match (kind) {
        case Comma | Colon | Dot | ColonColon | RParen | RBracket | RBrace => true
        case _ => false
    }
}

/**
 * Punctuation that attaches to its following token.
 */
private func isTightAfter(kind: SyntaxKind): Bool {
    match (kind) {
        case Dot | ColonColon | At | AtBang | Dollar | Tilde | LParen | LBracket | LBrace => true
        case _ => false
    }
}

/**
 * Syntax whose direct parts form one lexical unit, except nested unary minus.
 */
private func isTightContext(kind: SyntaxKind): Bool {
    match (kind) {
        case Name | LiteralPat | OptionType | OptionalExpr | PostfixExpr | UnaryExpr => true
        case _ => false
    }
}

/**
 * Suffix nodes and punctuation that need no preceding space.
 */
private func isAttachedSuffix(kind: SyntaxKind): Bool {
    match (kind) {
        case TypeArgList |
            TypeParamList |
            ParamList |
            ArgList |
            AnnotationArgList |
            MacroArgs |
            MacroAttr |
            Bang |
            RetType |
            LBracket => true
        case _ => false
    }
}
