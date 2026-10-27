package macro_host

import std.collection.*
import loupe.TextRange
import loupe.db.{MacroItem, MacroItemValue, MappedText, SpanOrigin}
import loupe.hir.{MacroChild, MacroRequest}
import macro_server.*

/**
 * Where a call's text is put on the wire, which cjc counts in lines and columns, so that a position the server
 * answers tells which text it is in (D98): the call itself on line 1, its attribute from line 2, its input on the
 * lines after.
 */
public class WireLayout {
    private let attrsStarts: Array<Int64>
    private let inputStarts: Array<Int64>
    let attrsLine: Int32 = 2
    let inputLine: Int32

    public WireLayout(private let attrs: ?MappedText, private let input: MappedText) {
        attrsStarts = lineStartsOf(attrs?.text ?? "")
        inputStarts = lineStartsOf(input.text)
        inputLine = attrsLine + Int32(attrsStarts.size)
    }

    /**
     * Where the token of `size` bytes at `line` and `column` comes from: the call, for one on line 1 (what a `quote`
     * made), else the part of the attribute or the input it was cut from; `None` for a position in neither.
     */
    public func originOf(line: Int32, column: Int32, size: Int64): ?SpanOrigin {
        if (line < attrsLine) {
            return SpanOrigin.FromCall
        }
        if (line < inputLine) {
            let text = attrs ?? return None
            let start =
                offsetOf(attrsStarts, text.text, Int64(line - attrsLine), column) ?? return None
            return text.originOf(TextRange(start, min(start + size, text.text.size)))
        }
        let start =
            offsetOf(inputStarts, input.text, Int64(line - inputLine), column) ?? return None
        input.originOf(TextRange(start, min(start + size, input.text.size)))
    }
}

/**
 * The offset of each line of `text`.
 */
func lineStartsOf(text: String): Array<Int64> {
    let starts = ArrayList<Int64>([0])
    let bytes = text.toArray()
    for (i in 0..bytes.size where bytes[i] == b'\n') {
        starts.add(i + 1)
    }
    starts.toArray()
}

func offsetOf(starts: Array<Int64>, text: String, line: Int64, column: Int32): ?Int64 {
    if (line < 0 || line >= starts.size || column < 1) {
        return None
    }
    let offset = starts[line] + Int64(column) - 1
    if (offset > text.size) { None } else { offset }
}

/**
 * The name cjc gives a macro's function in its library: `macroCall_a_<Macro>_<package>` for one called with an
 * attribute, `_c_` without, the package's `.` as `_` and an organization's `::` as `__`.
 */
public func methodNameOf(name: String, pkg: String, hasAttrs: Bool): String {
    let kind = if (hasAttrs) { "a" } else { "c" }
    "macroCall_${kind}_${name}_${pkg.replace("::", "__").replace(".", "_")}"
}

/**
 * What `request` asks the macro server, the macro run from `library` of `pkg`, and where its texts are on the wire.
 */
public func callDataOf(
    request: MacroRequest,
    pkg: String,
    library: String,
    numbers: TokenNumbers
): (MacroCallData, WireLayout) {
    let layout = WireLayout(request.attrs, request.input)
    let name = request.definition.name
    let attrs: Array<TokenData> =
        match (request.attrs) {
            case Some(text) =>
                withoutLeadingNewlines(
                    macroTokens(
                        text.text,
                        numbers,
                        PositionData(fileId: 1, line: layout.attrsLine, column: 1)
                    ),
                    numbers
                )
            case None => []
        }
    let input =
        withoutLeadingNewlines(
            macroTokens(
                request.input.text,
                numbers,
                PositionData(fileId: 1, line: layout.inputLine, column: 1)
            ),
            numbers
        )
    let call =
        MacroCallData(
            id: IdInfoData(name: name, pos: PositionData(fileId: 1, line: 1, column: 2)),
            hasAttrs: request.attrs.isSome(),
            args: input,
            attrs: attrs,
            parentNames: request.parents,
            childMsges: request.children.map { child => childOf(child, numbers) },
            methodName: methodNameOf(name, pkg, request.attrs.isSome()),
            packageName: pkg,
            libPath: library,
            begin: PositionData(fileId: 1, line: 1, column: 1),
            end: endOf(input, layout)
        )
    (call, layout)
}

/**
 * `tokens` from their first that is not an `NL`: cjc gives a macro no line break before the first token of its
 * attribute or of its input in parentheses, and keeps those after the last.
 */
func withoutLeadingNewlines(tokens: Array<TokenData>, numbers: TokenNumbers): Array<TokenData> {
    let nl = numbers.numberOf("NL")
    var start = 0
    while (start < tokens.size && tokens[start].kind == nl) {
        start++
    }
    tokens[start..]
}

/**
 * Where the input ends: after its last token, or where it starts for none.
 */
func endOf(input: Array<TokenData>, layout: WireLayout): PositionData {
    match (input.get(input.size - 1).flatMap { last => last.end }) {
        case Some(end) => end
        case None => PositionData(fileId: 1, line: layout.inputLine, column: 1)
    }
}

func childOf(child: MacroChild, numbers: TokenNumbers): ChildMsgData {
    ChildMsgData(childName: child.name, items: child.items.map { item => itemOf(item, numbers) })
}

func itemOf(item: MacroItem, numbers: TokenNumbers): ItemInfoData {
    let value =
        match (item.value) {
            case StringItem(text) => OptionValueData.AsSValue(text)
            case IntItem(n) => OptionValueData.AsIValue(IntValueData(val: n))
            case BoolItem(flag) => OptionValueData.AsBValue(BoolValueData(val: flag))
            case TokensItem(text) =>
                OptionValueData
                    .AsTValue(
                        TokensValueData(
                            val: macroTokens(
                                text.text,
                                numbers,
                                PositionData(fileId: 1, line: 1, column: 1)
                            )
                        )
                    )
        }
    ItemInfoData(key: item.key, value: value)
}
