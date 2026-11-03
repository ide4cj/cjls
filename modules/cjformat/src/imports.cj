package cjformat

import std.collection.{ArrayList, HashMap, collectArray}
import std.sort.sort
import cjsyntax.{CjSyntaxNode, SyntaxKind, parse}
import ginkgo.TextRange
import source_change.{TextEdit, applyEdits}

/**
 * An import's condition and visibility travel with every leaf when lists are regrouped.
 */
private struct ImportPrefix {
    ImportPrefix(let text: String, let key: String) {}
}

/**
 * Keep package and organization separators from the tree, including escaped path components.
 */
private struct ImportPath {
    ImportPath(let text: String, let packageName: String, let separator: String) {}
}

private struct ImportedName {
    ImportedName(
        let path: ImportPath,
        let name: String,
        let alias: String,
        let hasTrailingComma!: Bool
    ) {}

    prop text: String {
        get() {
            "${name}${alias}"
        }
    }
}

private class ImportGroup {
    ImportGroup(
        let prefix: ImportPrefix,
        let packageName: String,
        let separator: String,
        let names: ArrayList<ImportedName>
    ) {}

    prop sortPackage: String {
        get() {
            if (packageName.isEmpty()) { names[0].name } else { packageName }
        }
    }

    func category(moduleName: String): Int64 {
        if (sortPackage == "std" || sortPackage.startsWith("std.")) {
            return 0
        }
        if (sortPackage == "stdx" || sortPackage.startsWith("stdx.")) {
            return 1
        }
        let name = names[0].path.text.replace("`", "")
        if (!moduleName.isEmpty() && (name == moduleName || name.startsWith("${moduleName}."))) {
            return 3
        }
        2
    }

    func firstName(): String {
        var first = names[0].text
        for (name in names) {
            if (name.text.compare(first) == Ordering.LT) {
                first = name.text
            }
        }
        "${separator}${first}"
    }

    func source(): String {
        let entries = names.toArray()
        sort(entries, stable: true, by: { a, b => a.text.compare(b.text) })
        let hasTrailingComma = entries.any { entry => entry.hasTrailingComma }
        let member =
            if (entries.size == 1 && (!hasTrailingComma || entries[0].name == "*")) {
                entries[0].text
            } else {
                let comma = if (hasTrailingComma) { "," } else { "" }
                "{${String.join(entries.map { entry => entry.text }, delimiter: ", ")}${comma}}"
            }
        "${prefix.text}import ${packageName}${separator}${member}"
    }
}

/**
 * The header supplies module identity even for detached text and import-only ranges.
 * Organization-qualified modules keep their qualifier so another organization's package stays external.
 */
func moduleImportPrefix(root: CjSyntaxNode): String {
    let header =
        root.children().filter { node => node.kind == SyntaxKind.PackageHeader }.next() ?? return ""
    let parts = ArrayList<String>()
    for (element in header.childrenWithTokens()) {
        match (element.kind) {
            case SyntaxKind.NameRef =>
                parts.add(element.asNode().getOrThrow().text().trimAscii().replace("`", ""))
            case SyntaxKind.ColonColon => parts.add("::")
            case SyntaxKind.Dot => break
            case _ => ()
        }
    }
    String.join(parts.toArray(), delimiter: "")
}

/**
 * Rewrites only consecutive comment-free import declarations. Semicolons and other source
 * elements end a run; blank lines between imports follow the repository's one-group policy.
 */
func importEdits(root: CjSyntaxNode, source: String, moduleName: String): Array<TextEdit> {
    if (root.kind != SyntaxKind.SourceFile) {
        return []
    }
    let edits = ArrayList<TextEdit>()
    let run = ArrayList<CjSyntaxNode>()
    for (element in root.childrenWithTokens()) {
        if (isSpace(element.kind)) {
            continue
        }
        if (let Some(node) <- element.asNode()) {
            if (node.kind == SyntaxKind.ImportDecl && canNormalizeImport(node, source)) {
                run.add(node)
                continue
            }
        }
        flushImports(run, source, edits, moduleName)
    }
    flushImports(run, source, edits, moduleName)
    edits.toArray()
}

/**
 * Only declarations with unambiguous comment attachment may move between their neighbours.
 */
private func canNormalizeImport(node: CjSyntaxNode, source: String): Bool {
    if (node.descendantsWithTokens().any { e => isComment(e.kind) }) {
        return false
    }
    // An inline trailing comment may belong to the next node in the lossless tree. Anchor the
    // preceding import too, rather than moving another import in front of its comment.
    var at = importRange(node).end
    while (at < source.size && (source[at] == b' ' || source[at] == b'\t')) {
        at++
    }
    if (source[at..].startsWith("//") || source[at..].startsWith("/*")) {
        return false
    }
    for (child in node.descendants() where child.kind == SyntaxKind.ImportTreeList) {
        if (!child.children().any { e => e.kind == SyntaxKind.ImportTree }) {
            return false
        }
    }
    true
}

/**
 * Keep edits in original byte coordinates so one normalized run cannot shift a later edit.
 */
private func flushImports(
    run: ArrayList<CjSyntaxNode>,
    source: String,
    edits: ArrayList<TextEdit>,
    moduleName: String
): Unit {
    if (run.isEmpty()) {
        return
    }
    let ordered = groupedImports(run, source)
    sort(ordered, stable: true, by: { a, b => compareImports(a, b, moduleName) })
    let result = String.join(
        ordered.map { entry => entry.source() },
        delimiter: lineBreakIn(source)
    )
    let range = TextRange(importRange(run[0]).start, importRange(run[run.size - 1]).end)
    edits.add(all: replacement(source, range, result))
    run.clear()
}

/**
 * Conditions, visibility and organization separators must not collapse into a different import.
 */
private func groupedImports(run: ArrayList<CjSyntaxNode>, source: String): Array<ImportGroup> {
    let groups = ArrayList<ImportGroup>()
    let byPackage = HashMap<String, ImportGroup>()
    for (node in run) {
        let prefix = importPrefix(node, source)
        let names = ArrayList<ImportedName>()
        let tree =
            node.children().filter { child => child.kind == SyntaxKind.ImportTree }.next() ??
                throw IllegalStateException("an import declaration has an import tree")
        collectImports(tree, ImportPath("", "", ""), names, trailing: false)
        for (name in names) {
            let path = name.path
            let key =
                "${prefix.key.size}:${prefix.key}${path.packageName.size}:${path.packageName}${path.separator}"
            // Wildcards retain their own declaration, including when an explicit name from that
            // package is present. No name, alias or duplicate is eliminated by normalization.
            if (!path.packageName.isEmpty() && name.name != "*") {
                if (let Some(existing) <- byPackage.get(key)) {
                    existing.names.add(name)
                    continue
                }
            }
            let group = ImportGroup(
                prefix,
                path.packageName,
                path.separator,
                ArrayList<ImportedName>([name])
            )
            groups.add(group)
            if (!path.packageName.isEmpty() && name.name != "*") {
                byPackage[key] = group
            }
        }
    }
    groups.toArray()
}

/**
 * A group's representative must not depend on the author's member order.
 */
private func compareImports(a: ImportGroup, b: ImportGroup, moduleName: String): Ordering {
    let category = a.category(moduleName).compare(b.category(moduleName))
    if (category != Ordering.EQ) {
        return category
    }
    let packageName = a.sortPackage.compare(b.sortPackage)
    if (packageName != Ordering.EQ) {
        return packageName
    }
    let member = a.firstName().compare(b.firstName())
    if (member != Ordering.EQ) {
        return member
    }
    a.prefix.key.compare(b.prefix.key)
}

/**
 * Length-prefix tokens so whitespace can be ignored without conflating literals or token boundaries.
 */
private func importPrefix(node: CjSyntaxNode, source: String): ImportPrefix {
    let tokens = ArrayList<String>()
    let start = importRange(node).start
    for (element in node.descendantsWithTokens()) {
        let token = element.asToken() ?? continue
        if (token.kind == SyntaxKind.ImportKw) {
            let key = String.join(tokens.toArray(), delimiter: "")
            return ImportPrefix(source[start..token.textRange.start], key)
        }
        if (!token.kind.isTrivia()) {
            let value = token.text()
            tokens.add("${value.size}:${value}")
        }
    }
    throw IllegalStateException("an import declaration has an import keyword")
}

/**
 * Expand qualified leaves before choosing groups, retaining aliases on the final imported name.
 */
private func collectImports(
    tree: CjSyntaxNode,
    prefix: ImportPath,
    names: ArrayList<ImportedName>,
    trailing!: Bool
): Unit {
    var path = prefix.text
    var packageName = prefix.packageName
    var separator = prefix.separator
    var alias = ""
    for (element in tree.childrenWithTokens()) {
        match (element.kind) {
            case SyntaxKind.NameRef =>
                path =
                    "${path}${element.asNode().getOrThrow { IllegalStateException("a structured import component is a node") }.text().trimAscii()}"
            case SyntaxKind.Dot | SyntaxKind.ColonColon =>
                packageName = path
                separator =
                    element
                        .asToken()
                        .getOrThrow { IllegalStateException("an import separator is a token") }
                        .text()
                path = "${path}${separator}"
            case SyntaxKind.Star => path = "${path}*"
            case SyntaxKind.ImportAlias =>
                let node =
                    element
                        .asNode()
                        .getOrThrow {
                            IllegalStateException("a structured import component is a node")
                        }
                let name =
                    node.children().filter { n => n.kind == SyntaxKind.Name }.next() ??
                        throw IllegalStateException("an import alias has a name")
                alias = " as ${name.text().trimAscii()}"
            case SyntaxKind.ImportTreeList =>
                collectImportList(
                    element
                        .asNode()
                        .getOrThrow {
                            IllegalStateException("a structured import component is a node")
                        },
                    ImportPath(path, packageName, separator),
                    names,
                    trailing: trailing
                )
                return
            case _ => ()
        }
    }
    names.add(
        ImportedName(
            ImportPath(path, packageName, separator),
            path[packageName.size + separator.size..],
            alias,
            hasTrailingComma: trailing
        )
    )
}

/**
 * Carry the trailing comma to each leaf so regrouped explicit-name lists can retain it.
 */
private func collectImportList(
    list: CjSyntaxNode,
    prefix: ImportPath,
    names: ArrayList<ImportedName>,
    trailing!: Bool
): Unit {
    let parts = list.childrenWithTokens().filter { e => !e.kind.isTrivia() } |> collectArray
    let hasTrailingComma =
        trailing || (parts.size > 2 && parts[parts.size - 2].kind == SyntaxKind.Comma)
    for (child in list.children() where child.kind == SyntaxKind.ImportTree) {
        collectImports(child, prefix, names, trailing: hasTrailingComma)
    }
}

/**
 * The non-trivia span, excluding comments that the parser attaches before the declaration.
 */
func importRange(node: CjSyntaxNode): TextRange {
    var start = node.textRange.end
    var end = start
    for (element in node.descendantsWithTokens()) {
        if (element.asToken().isSome() && !element.kind.isTrivia()) {
            start = min(start, element.textRange.start)
            end = element.textRange.end
        }
    }
    TextRange(start, end)
}

/**
 * Import-only selections normalize their enclosing imports without reformatting the rest of
 * the source file. A selection spanning other syntax uses the usual statement/body policy.
 */
func formatImportRange(
    root: CjSyntaxNode,
    source: String,
    range: TextRange,
    options: FormatOptions
): ?Array<TextEdit> {
    if (root.kind != SyntaxKind.SourceFile) {
        return None
    }
    var start = range.start
    var end = range.end
    while (start < end && isAsciiSpace(source[start])) {
        start++
    }
    while (end > start && isAsciiSpace(source[end - 1])) {
        end--
    }
    let selection = TextRange(start, end)
    let nodes =
        root
            .children()
            .filter {
                node =>
                if (node.kind != SyntaxKind.ImportDecl) {
                    return false
                }
                let span = importRange(node)
                if (selection.start == selection.end) {
                    return span.start <= selection.start && selection.start <= span.end
                }
                span.end > selection.start && span.start < selection.end
            } |>
            collectArray
    if (nodes.isEmpty()) {
        return None
    }
    var from = nodes[0].textRange.start
    let spanEnd = importRange(nodes[nodes.size - 1]).end
    let to = trailingImportCommentEnd(root, source, spanEnd)
    if (start < from || end > to) {
        return None
    }
    while (from > 0 && (source[from - 1] == b' ' || source[from - 1] == b'\t')) {
        from--
    }
    // A single-line fragment carries no newline of its own; seed it with the file's convention.
    let fragment = "${source[from..to]}${lineBreakIn(source)}"
    let edits =
        formatWithModule(parse(fragment), options, moduleImportPrefix(root))
            .getOrThrow {
                IllegalStateException("an import-only selection is a valid source fragment")
            }
    let formatted = applyEdits(fragment, edits)
    let result = if (to == source.size) { formatted } else { formatted.trimAsciiEnd() }
    Some(replacement(source, TextRange(from, to), result))
}

/**
 * A range keeps the trailing comment context that anchors an import during whole-file formatting.
 */
private func trailingImportCommentEnd(root: CjSyntaxNode, source: String, from: Int64): Int64 {
    var end = from
    for (element in root.descendantsWithTokens()) {
        let token = element.asToken() ?? continue
        if (!isComment(token.kind) || token.textRange.start < end) {
            continue
        }
        let gap = source[end..token.textRange.start]
        if (!gap.trimAscii().isEmpty() || gap.contains("\n")) {
            break
        }
        end = token.textRange.end
    }
    end
}
