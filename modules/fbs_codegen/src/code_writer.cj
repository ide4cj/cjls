package fbs_codegen

/**
 * Builds a Cangjie file a line at a time, indented by blocks; `cjfmt` has the last word on its layout.
 */
class CodeWriter <: ToString {
    let sb = StringBuilder()
    var indentation = 0

    func line(text: String): Unit {
        if (!text.isEmpty()) {
            sb.append(" " * (indentation * 4))
            sb.append(text)
        }
        sb.append("\n")
    }

    func blank(): Unit {
        sb.append("\n")
    }

    /**
     * `head {`, the body one level in, `}`.
     */
    func block(head: String, body: () -> Unit): Unit {
        line("${head} {")
        indentation++
        body()
        indentation--
        line("}")
    }

    /**
     * A doc comment of `lines`, `/*` and `*/` in them escaped (block comments nest); nothing if there are
     * none.
     */
    func doc(lines: Array<String>): Unit {
        if (lines.isEmpty()) {
            return
        }
        line("/**")
        for (l in lines) {
            let text = l.replace("/*", "/\\*").replace("*/", "*\\/")
            if (text.isEmpty()) {
                line(" *")
            } else {
                line(" * ${text}")
            }
        }
        line(" */")
    }

    public func toString(): String {
        sb.toString()
    }
}

/**
 * `s` as a Cangjie string literal.
 */
func quoted(s: String): String {
    let sb = StringBuilder("\"")
    for (r in s.runes()) {
        match (r) {
            case '"' => sb.append("\\\"")
            case '\\' => sb.append("\\\\")
            case '$' => sb.append("\\$")
            case '\n' => sb.append("\\n")
            case _ => sb.append(r)
        }
    }
    sb.append("\"")
    sb.toString()
}
