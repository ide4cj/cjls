package fbs_codegen

import std.collection.*
import std.convert.*

/**
 * Cangjie's keywords: a name of the schema that is one is written as a raw identifier (`` `type` ``).
 */
let KEYWORDS: HashSet<String> = HashSet<String>(
    [
        "as", "abstract", "break", "Bool", "case", "catch", "class", "const", "continue", "do", "else", "enum",
        "extend", "false", "finally", "Float16", "Float32", "Float64", "for", "foreign", "func", "if", "import",
        "in", "init", "inout", "Int16", "Int32", "Int64", "Int8", "interface", "IntNative", "internal", "is",
        "let", "macro", "main", "match", "mut", "Nothing", "open", "operator", "override", "package", "private",
        "prop", "protected", "public", "quote", "redef", "return", "Rune", "sealed", "spawn", "static", "struct",
        "super", "synchronized", "This", "this", "throw", "true", "try", "type", "UInt16", "UInt32", "UInt64",
        "UInt8", "UIntNative", "Unit", "unsafe", "var", "VArray", "where", "while"
    ]
)

/**
 * What the runtime the views are generated against declares in their package: a view cannot be named so.
 */
let RUNTIME_TYPES = ["FbTable", "FbVector", "FbVectorIterator"]

/**
 * The names the views of `schema` take, as `config` renames them, and where their fields are.
 */
class Names {
    Names(let schema: Schema, let config: Config) {}

    /** The Cangjie name of declaration `name` of the schema. */
    func typeName(name: String): String {
        config.rename.get(name) ?? name
    }

    /** The Cangjie name of member `member` of enum `owner`, as it is written in code. */
    func memberName(owner: String, member: String): String {
        raw(config.rename.get("${owner}.${member}") ?? member)
    }

    /** `name` as it is written in code: raw if it is a keyword. */
    func raw(name: String): String {
        if (KEYWORDS.contains(name)) {
            "`${name}`"
        } else {
            name
        }
    }

    /** `snake_case` as `snakeCase`, raw if it is a keyword. */
    func fieldName(name: String): String {
        let sb = StringBuilder()
        var upper = false
        for (r in name.runes()) {
            if (r == r'_' && sb.size > 0) {
                upper = true
            } else if (upper) {
                sb.append(r.toAsciiUpperCase())
                upper = false
            } else {
                sb.append(r)
            }
        }
        raw(sb.toString())
    }

    func decl(name: String): Decl {
        match (schema.find(name)) {
            case Some(d) => d
            case _ => throw ConfigException("`${name}` is not declared in the schema")
        }
    }

    func isOpen(name: String): Bool {
        config.open.contains(name)
    }

    /**
     * Checks that every name the views give is one Cangjie takes: no constructor of an enum (or of a
     * union) named like a type, which would leave the type no name in its package; and nothing the config
     * names that is not in the schema.
     *
     * @throws ConfigException - naming the first such name
     */
    func check(): Unit {
        let types = HashSet<String>(RUNTIME_TYPES)
        for (d in schema.decls) {
            if (!types.add(typeName(d.name))) {
                throw ConfigException("two declarations are named `${typeName(d.name)}`")
            }
        }
        for (name in config.open) {
            if (!(decl(name).kind == EnumDecl)) {
                throw ConfigException("`${name}` in `open` is not an enum")
            }
        }
        for ((key, _) in config.rename) {
            let parts = key.split(".")
            let d = decl(parts[0])
            if (parts.size == 2 && !hasMember(d, parts[1])) {
                throw ConfigException("`${key}` in `rename` is not a member of an enum")
            }
        }
        for ((key, _) in config.wrap) {
            let parts = key.split(".")
            if (parts.size != 2 || !hasField(decl(parts[0]), parts[1])) {
                throw ConfigException("`${key}` in `wrap` is not a field")
            }
        }
        for (d in schema.decls) {
            let constructors = ArrayList<String>()
            for (m in d.members) {
                constructors.add(config.rename.get("${d.name}.${m.name}") ?? m.name)
            }
            for (m in d.unionMembers) {
                constructors.add("As${m.name}")
            }
            for (c in constructors where types.contains(c)) {
                throw ConfigException(
                    "`${d.name}` has a member `${c}`, which is also a type: rename one (`${d.name}.${c}` or `${c}`)")
            }
        }
    }
}

func hasMember(d: Decl, name: String): Bool {
    for (m in d.members where m.name == name) {
        return true
    }
    false
}

func hasField(d: Decl, name: String): Bool {
    for (f in d.fields where f.name == name) {
        return true
    }
    false
}

/**
 * Where the fields of a struct are, and how big and aligned it is: each field at the next offset its
 * alignment allows, the struct padded to its largest alignment.
 */
struct StructLayout {
    StructLayout(let offsets: Array<Int64>, let size: Int64, let alignment: Int64) {}
}

func structLayout(names: Names, d: Decl): StructLayout {
    let offsets = ArrayList<Int64>()
    var at = 0
    var alignment = 1
    for (f in d.fields) {
        let (size, align) = inlineSize(names, f.fbType)
        at = alignUp(at, align)
        offsets.add(at)
        at += size
        alignment = max(alignment, align)
    }
    StructLayout(offsets.toArray(), alignUp(at, alignment), alignment)
}

/**
 * `(size, alignment)` of a value of `t` stored inline: a scalar, an enum, a struct.
 */
func inlineSize(names: Names, t: FbType): (Int64, Int64) {
    match (t) {
        case ScalarType(s) => (s.size, s.size)
        case NamedType(n) =>
            let d = names.decl(n)
            match (d.kind) {
                case EnumDecl => (d.underlying.getOrThrow().size, d.underlying.getOrThrow().size)
                case StructDecl =>
                    let layout = structLayout(names, d)
                    (layout.size, layout.alignment)
                case _ => throw ConfigException("`${n}` cannot be stored inline")
            }
        case _ => throw ConfigException("a struct holds scalars, enums and structs only")
    }
}

func alignUp(at: Int64, align: Int64): Int64 {
    (at + align - 1) / align * align
}

/**
 * The id of each field of a table, the index of its slot in the vtable: in order, a union (or a vector of
 * unions) taking two, its type's then its value's.
 */
func fieldIds(names: Names, d: Decl): Array<Int64> {
    let ids = ArrayList<Int64>()
    var next = 0
    for (f in d.fields) {
        ids.add(next)
        next += if (isUnion(names, f.fbType)) {
            2
        } else {
            1
        }
    }
    ids.toArray()
}

func isUnion(names: Names, t: FbType): Bool {
    match (t) {
        case NamedType(n) => names.decl(n).kind == UnionDecl
        case VectorType(e) => isUnion(names, e)
        case _ => false
    }
}


/**
 * The views of the schema: a Cangjie file of package `packageName`, before `cjfmt` has had it.
 */
func emitViews(names: Names, header: String, packageName: String): String {
    names.check()
    let w = CodeWriter()
    w.line(header)
    w.blank()
    w.line("package ${packageName}")
    for (d in names.schema.decls) {
        w.blank()
        match (d.kind) {
            case EnumDecl => emitEnum(w, names, d)
            case UnionDecl => emitUnion(w, names, d)
            case StructDecl => emitStruct(w, names, d)
            case TableDecl => emitTable(w, names, d)
        }
    }
    w.toString()
}

func emitEnum(w: CodeWriter, names: Names, d: Decl): Unit {
    let name = names.typeName(d.name)
    let scalar = d.underlying.getOrThrow().cangjie
    let open = names.isOpen(d.name)
    w.doc(d.doc)
    w.block("public enum ${name}") {
        for (m in d.members) {
            w.doc(m.doc)
            w.line("| ${names.memberName(d.name, m.name)}")
        }
        if (open) {
            w.doc(["A value this version of the schema does not have."])
            w.line("| Unknown(${scalar})")
        }
    }
    w.blank()
    // in the enum's body a member named like a type (`LitConstKind.String`) hides it, not in an extend
    w.block("extend ${name} <: Hashable & Equatable<${name}> & ToString") {
        w.block("static func fromValue(value: ${scalar}): ${name}") {
            w.block("match (value)") {
                for (m in d.members) {
                    w.line("case ${m.value} => ${name}.${names.memberName(d.name, m.name)}")
                }
                if (open) {
                    w.line("case _ => ${name}.Unknown(value)")
                } else {
                    w.line("case _ => throw broken(\"${d.name} has no value \${value}\")")
                }
            }
        }
        w.blank()
        w.doc(["Its value in the file."])
        w.block("public prop value: ${scalar}") {
            w.block("get()") {
                w.block("match (this)") {
                    for (m in d.members) {
                        w.line("case ${name}.${names.memberName(d.name, m.name)} => ${m.value}")
                    }
                    if (open) {
                        w.line("case ${name}.Unknown(v) => v")
                    }
                }
            }
        }
        w.blank()
        w.block("public operator func ==(other: ${name}): Bool") {
            w.line("value == other.value")
        }
        w.blank()
        w.block("public operator func !=(other: ${name}): Bool") {
            w.line("value != other.value")
        }
        w.blank()
        w.block("public func hashCode(): Int64") {
            w.line("Int64(value)")
        }
        w.blank()
        w.block("public func toString(): String") {
            w.block("match (this)") {
                for (m in d.members) {
                    let member = names.memberName(d.name, m.name)
                    w.line("case ${name}.${member} => ${quoted(member.replace("`", ""))}")
                }
                if (open) {
                    w.line("case ${name}.Unknown(v) => \"Unknown(\${v})\"")
                }
            }
        }
    }
}

func emitUnion(w: CodeWriter, names: Names, d: Decl): Unit {
    let name = names.typeName(d.name)
    w.doc(d.doc)
    w.block("public enum ${name}") {
        for (m in d.unionMembers) {
            w.doc(m.doc)
            w.line("| As${m.name}(${unionMemberType(names, m)})")
        }
        w.doc(["A member this version of the schema does not have, by its type."])
        w.line("| Unknown(UInt8)")
        w.blank()
        w.doc(["The union of field `id` (its type; `id + 1` is its value), if it is there."])
        w.block("static func read(fb: FbTable, id: Int64): ?${name}") {
            w.line("let tag = fb.scalar(id, 0, readUInt8)")
            w.block("if (tag == 0)") {
                w.line("return Option<${name}>.None")
            }
            w.line("let o = fb.offset(id + 1)")
            w.block("if (o == 0)") {
                w.line("throw broken(\"${d.name} of type \${tag} has no value\")")
            }
            w.line("at(fb.buf, tag, fb.pos + o)")
        }
        w.blank()
        w.doc(["The vector of unions of field `id` (their types; `id + 1` is their values)."])
        w.block("static func readVector(fb: FbTable, id: Int64): FbVector<${name}>") {
            w.line("let tags = fb.vector(id, 1, readUInt8)")
            w.line("let values = fb.vector(id + 1, 4) {_, p => p}")
            w.block("if (tags.size != values.size)") {
                w.line("throw broken(\"${d.name}: \${tags.size} types for \${values.size} values\")")
            }
            w.line("FbVector<${name}>(fb.buf, values.start, values.size, 4) {b, p => at(b, tags[(p - values.start) / 4], p)}")
        }
        w.blank()
        w.doc(["The member of type `tag` whose offset is stored at `pos`."])
        w.block("static func at(buf: Array<Byte>, tag: UInt8, pos: Int64): ${name}") {
            w.block("match (tag)") {
                var tag = 1
                for (m in d.unionMembers) {
                    w.line("case ${tag} => ${name}.As${m.name}(${unionMemberRead(names, m)})")
                    tag++
                }
                w.line("case _ => ${name}.Unknown(tag)")
            }
        }
    }
}

func unionMemberType(names: Names, m: UnionMember): String {
    if (m.typeName == "string") {
        "String"
    } else {
        names.typeName(m.typeName)
    }
}

func unionMemberRead(names: Names, m: UnionMember): String {
    if (m.typeName == "string") {
        return "readString(buf, pos)"
    }
    let t = names.typeName(m.typeName)
    match (names.decl(m.typeName).kind) {
        case TableDecl => "${t}(FbTable.at(buf, pos))"
        case StructDecl => "${t}(buf, follow(buf, pos))"
        case _ => throw ConfigException("union `${m.name}` holds `${m.typeName}`, neither a table nor a struct")
    }
}

func emitStruct(w: CodeWriter, names: Names, d: Decl): Unit {
    let name = names.typeName(d.name)
    let layout = structLayout(names, d)
    checkMembers(names, d, ["buf", "pos"])
    w.doc(d.doc)
    w.block("public struct ${name}") {
        w.line("${name}(let buf: Array<Byte>, let pos: Int64) {}")
        for (i in 0..d.fields.size) {
            let f = d.fields[i]
            if (f.deprecated) {
                continue
            }
            let at = if (layout.offsets[i] == 0) {
                "pos"
            } else {
                "pos + ${layout.offsets[i]}"
            }
            let (fieldType, read) = match (f.fbType) {
                case ScalarType(s) => (s.cangjie, "${reader(s)}(buf, ${at})")
                case NamedType(n) =>
                    let t = names.typeName(n)
                    let nd = names.decl(n)
                    match (nd.kind) {
                        case EnumDecl => (t, "${t}.fromValue(${reader(nd.underlying.getOrThrow())}(buf, ${at}))")
                        case _ => (t, "${t}(buf, ${at})")
                    }
                case _ => throw ConfigException("struct `${d.name}` has a field that is not inline")
            }
            w.blank()
            emitProp(w, f, names.fieldName(f.name), fieldType, read)
        }
    }
}

func emitTable(w: CodeWriter, names: Names, d: Decl): Unit {
    let name = names.typeName(d.name)
    let ids = fieldIds(names, d)
    checkMembers(names, d, ["fb"])
    w.doc(d.doc)
    w.block("public struct ${name}") {
        w.line("${name}(let fb: FbTable) {}")
        if (names.schema.rootType == Some(d.name)) {
            if (let Some(identifier) <- names.schema.fileIdentifier) {
                w.blank()
                w.doc(["What a file of this schema has at bytes 4 to 8."])
                w.line("static let FILE_IDENTIFIER = ${quoted(identifier)}")
            }
            w.blank()
            w.doc(["The root table of `buf`, nothing checked."])
            w.block("static func root(buf: Array<Byte>): ${name}") {
                w.line("${name}(FbTable.at(buf, 0))")
            }
        }
        for (i in 0..d.fields.size) {
            let f = d.fields[i]
            if (f.deprecated) {
                continue
            }
            var (fieldType, read) = tableField(names, d, f, ids[i])
            if (let Some(wrapper) <- names.config.wrap.get("${d.name}.${f.name}")) {
                fieldType = wrapper
                read = "${wrapper}(${read})"
            }
            w.blank()
            emitProp(w, f, names.fieldName(f.name), fieldType, read)
        }
    }
}

/**
 * `(type, expression)` of field `f` of table `d`, read from its `fb`.
 */
func tableField(names: Names, d: Decl, f: Field, id: Int64): (String, String) {
    match (f.fbType) {
        case ScalarType(s) => (s.cangjie, "fb.scalar(${id}, ${scalarDefault(s, f.defaultValue)}, ${reader(s)})")
        case StringType => optional(d, f, "String", "fb.string(${id})")
        case NamedType(n) =>
            let t = names.typeName(n)
            let nd = names.decl(n)
            match (nd.kind) {
                case EnumDecl =>
                    let s = nd.underlying.getOrThrow()
                    (t, "${t}.fromValue(fb.scalar(${id}, ${enumDefault(nd, f.defaultValue)}, ${reader(s)}))")
                case UnionDecl => optional(d, f, t, "${t}.read(fb, ${id})")
                case StructDecl => optional(d, f, t, "fb.structAt(${id}).map {p => ${t}(fb.buf, p)}")
                case TableDecl => optional(d, f, t, "fb.table(${id}).map {x => ${t}(x)}")
            }
        case VectorType(e) =>
            let (elementType, stride, read) = vectorElement(names, e)
            let vector = match (e) {
                case NamedType(n) where names.decl(n).kind == UnionDecl => "${elementType}.readVector(fb, ${id})"
                case _ => "fb.vector(${id}, ${stride}, ${read})"
            }
            ("FbVector<${elementType}>", vector)
    }
}

/**
 * `(type, stride, reader)` of an element of a vector of `e`: the reader takes the file and where the element
 * is stored.
 */
func vectorElement(names: Names, e: FbType): (String, Int64, String) {
    match (e) {
        case ScalarType(s) => (s.cangjie, s.size, reader(s))
        case StringType => ("String", 4, "readString")
        case NamedType(n) =>
            let t = names.typeName(n)
            let nd = names.decl(n)
            match (nd.kind) {
                case EnumDecl =>
                    let s = nd.underlying.getOrThrow()
                    (t, s.size, "{b, p => ${t}.fromValue(${reader(s)}(b, p))}")
                case StructDecl => (t, structLayout(names, nd).size, "{b, p => ${t}(b, p)}")
                case TableDecl => (t, 4, "{b, p => ${t}(FbTable.at(b, p))}")
                case UnionDecl => (t, 4, "")
            }
        case VectorType(_) => throw ConfigException("a vector of vectors is not a flatbuffers type")
    }
}

/**
 * A field that may be absent: `?type`, or `type` if it is required, the file broken without it.
 */
func optional(d: Decl, f: Field, t: String, read: String): (String, String) {
    if (f.required) {
        (t, "FbTable.required(${read}, ${quoted(d.name)}, ${quoted(f.name)})")
    } else {
        ("?${t}", read)
    }
}

func scalarDefault(s: Scalar, value: ?String): String {
    match ((s, value)) {
        case (FbBool, Some(v)) => v
        case (FbBool, None) => "false"
        case (FbFloat32, None) | (FbFloat64, None) => "0.0"
        case (_, Some(v)) => v
        case (_, None) => "0"
    }
}

func enumDefault(d: Decl, value: ?String): String {
    match (value) {
        case Some(v) =>
            for (m in d.members where m.name == v) {
                return "${m.value}"
            }
            match (Int64.tryParse(v)) {
                case Some(n) => "${n}"
                case _ => throw ConfigException("`${v}` is not a member of `${d.name}`")
            }
        case None => if (d.members.isEmpty()) {
            "0"
        } else {
            "${d.members[0].value}"
        }
    }
}

/**
 * Refuses a field named like what a view holds itself.
 */
func checkMembers(names: Names, d: Decl, taken: Array<String>): Unit {
    for (f in d.fields where taken.contains(names.fieldName(f.name))) {
        throw ConfigException("`${d.name}.${f.name}` is named like what the view holds")
    }
}

func emitProp(w: CodeWriter, f: Field, name: String, fieldType: String, read: String): Unit {
    w.doc(f.doc)
    w.block("public prop ${name}: ${fieldType}") {
        w.block("get()") {
            w.line(read)
        }
    }
}

/** The runtime's function reading a `s` where it starts. */
func reader(s: Scalar): String {
    "read${s.cangjie}"
}
