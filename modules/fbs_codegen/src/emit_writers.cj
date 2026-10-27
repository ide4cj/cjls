package fbs_codegen

import std.collection.*

/**
 * The writers of the schema, one `<Name>Data` a declaration but an enum (whose views are values already): a
 * struct's fields and its bytes, a table's fields and `pack`, which builds it in an `FbBuilder` after its
 * children, a union's members as an enum. A vector is always written, an empty one too: a reader that does not
 * check a field (cjc's) finds it.
 */
func emitWriters(w: CodeWriter, names: Names): Unit {
    for (d in names.schema.decls) {
        match (d.kind) {
            case EnumDecl => ()
            case UnionDecl =>
                w.blank()
                emitUnionWriter(w, names, d)
            case StructDecl =>
                w.blank()
                emitStructWriter(w, names, d)
            case TableDecl =>
                w.blank()
                emitTableWriter(w, names, d)
        }
    }
}

/** What a writer holds itself: a field named so is refused. */
let WRITER_MEMBERS = ["pack", "toBytes", "writeTo", "tag", "SIZE", "ALIGNMENT"]

func emitStructWriter(w: CodeWriter, names: Names, d: Decl): Unit {
    let name = names.dataName(d.name)
    let layout = structLayout(names, d)
    checkWriterMembers(names, d)
    w.doc(["A `${d.name}` to write."])
    w
        .block("public struct ${name}") {
            w.line("public static const SIZE = ${layout.size}")
            w.line("public static const ALIGNMENT = ${layout.alignment}")
            w.blank()
            let params = ArrayList<String>()
            for (f in d.fields) {
                params
                    .add(
                        "public let ${names.fieldName(f.name)}!: ${inlineDataType(names, f.fbType)}"
                    )
            }
            w.line("public ${name}(${String.join(params.toArray(), delimiter: ", ")}) {}")
            w.blank()
            w.doc(["Writes its fields into `buf` from `pos`, as the schema lays them out."])
            w
                .block("public func writeTo(buf: Array<Byte>, pos: Int64): Unit") {
                    for (i in 0..d.fields.size) {
                        let f = d.fields[i]
                        let at = "pos + ${layout.offsets[i]}"
                        let field = names.fieldName(f.name)
                        match (f.fbType) {
                            case ScalarType(s) => w.line("write${s.cangjie}(buf, ${at}, ${field})")
                            case NamedType(n) =>
                                let nd = names.decl(n)
                                match (nd.kind) {
                                    case EnumDecl =>
                                        w
                                            .line(
                                                "write${nd.underlying.getOrThrow().cangjie}(buf, ${at}, ${field}.value)"
                                            )
                                    case _ => w.line("${field}.writeTo(buf, ${at})")
                                }
                            case _ =>
                                throw ConfigException(
                                    "struct `${d.name}` has a field that is not inline"
                                )
                        }
                    }
                }
            w.blank()
            w.doc(["Its bytes."])
            w
                .block("public func toBytes(): Array<Byte>") {
                    w.line("let bytes = Array<Byte>(SIZE, repeat: 0)")
                    w.line("writeTo(bytes, 0)")
                    w.line("bytes")
                }
        }
}

/**
 * The type a writer takes for a value stored inline: a scalar, an enum (its view), a struct's writer.
 */
func inlineDataType(names: Names, t: FbType): String {
    match (t) {
        case ScalarType(s) => s.cangjie
        case NamedType(n) where names.decl(n).kind == EnumDecl => names.typeName(n)
        case NamedType(n) => names.dataName(n)
        case _ => throw ConfigException("a struct holds scalars, enums and structs only")
    }
}

func emitUnionWriter(w: CodeWriter, names: Names, d: Decl): Unit {
    let name = names.dataName(d.name)
    w.doc(["A `${d.name}` to write."])
    w
        .block("public enum ${name}") {
            for (m in d.unionMembers) {
                w.line("| ${unionConstructor(m)}(${unionMemberDataType(names, m)})")
            }
            w.blank()
            w.doc(["Its type, as the field before its value holds it."])
            w
                .block("public prop tag: UInt8") {
                    w
                        .block("get()") {
                            w
                                .block("match (this)") {
                                    var tag = 1
                                    for (m in d.unionMembers) {
                                        w.line("case ${unionConstructor(m)}(_) => ${tag}")
                                        tag++
                                    }
                                }
                        }
                }
            w.blank()
            w.doc(["Builds its value in `b`: where it is."])
            w
                .block("public func pack(b: FbBuilder): FbOffset") {
                    w
                        .block("match (this)") {
                            for (m in d.unionMembers) {
                                w
                                    .line(
                                        "case ${unionConstructor(m)}(v) => ${unionMemberPack(names, m)}"
                                    )
                            }
                        }
                }
        }
}

func unionMemberDataType(names: Names, m: UnionMember): String {
    if (m.typeName == "string") { "String" } else { names.dataName(m.typeName) }
}

func unionMemberPack(names: Names, m: UnionMember): String {
    if (m.typeName == "string") {
        return "b.createString(v)"
    }
    match (names.decl(m.typeName).kind) {
        case TableDecl => "v.pack(b)"
        case StructDecl => "b.createStruct(v.toBytes(), ${names.dataName(m.typeName)}.ALIGNMENT)"
        case _ =>
            throw ConfigException(
                "union `${m.name}` holds `${m.typeName}`, neither a table nor a struct"
            )
    }
}

func emitTableWriter(w: CodeWriter, names: Names, d: Decl): Unit {
    let name = names.dataName(d.name)
    let ids = fieldIds(names, d)
    checkWriterMembers(names, d)
    let fields = ArrayList<(Field, Int64)>()
    for (i in 0..d.fields.size where !d.fields[i].deprecated) {
        fields.add((d.fields[i], ids[i]))
    }
    w.doc(["A `${d.name}` to write."])
    w
        .block("public class ${name}") {
            let params = ArrayList<String>()
            for ((f, _) in fields) {
                params.add("public let ${names.fieldName(f.name)}!: ${tableFieldData(names, d, f)}")
            }
            w.line("public ${name}(${String.join(params.toArray(), delimiter: ", ")}) {}")
            w.blank()
            w.doc(["Builds it in `b`, its children first: where it is."])
            w
                .block("public func pack(b: FbBuilder): FbOffset") {
                    for ((f, _) in fields) {
                        packChild(w, names, f)
                    }
                    w.line("b.startTable()")
                    for ((f, id) in fields) {
                        addField(w, names, f, id)
                    }
                    w.line("b.endTable()")
                }
            if (names.schema.rootType == Some(d.name)) {
                w.blank()
                w.doc(["The buffer of which it is the root."])
                w
                    .block("public func toBytes(): Array<Byte>") {
                        w.line("let b = FbBuilder()")
                        match (names.schema.fileIdentifier) {
                            case Some(identifier) =>
                                w.line("b.finish(pack(b), fileIdentifier: ${quoted(identifier)})")
                            case None => w.line("b.finish(pack(b))")
                        }
                    }
            }
        }
}

/**
 * The parameter of field `f` of table `d`'s writer, with its default: a scalar's or an enum's of the schema,
 * an empty vector, `None` for what may be absent; none for a required field.
 */
func tableFieldData(names: Names, d: Decl, f: Field): String {
    match (f.fbType) {
        case ScalarType(s) => "${s.cangjie} = ${scalarDefault(s, f.defaultValue)}"
        case StringType => optionalData(f, "String")
        case NamedType(n) =>
            let nd = names.decl(n)
            match (nd.kind) {
                case EnumDecl =>
                    let t = names.typeName(n)
                    "${t} = ${t}.fromValue(${enumDefault(nd, f.defaultValue)})"
                case _ => optionalData(f, names.dataName(n))
            }
        case VectorType(e) =>
            let element =
                match (e) {
                    case ScalarType(s) => s.cangjie
                    case StringType => "String"
                    case NamedType(n) where names.decl(n).kind == EnumDecl => names.typeName(n)
                    case NamedType(n) where names.decl(n).kind == UnionDecl =>
                        throw ConfigException(
                            "`${d.name}.${f.name}`: a vector of unions is not written"
                        )
                    case NamedType(n) => names.dataName(n)
                    case VectorType(_) =>
                        throw ConfigException("a vector of vectors is not a flatbuffers type")
                }
            "Array<${element}> = []"
    }
}

func optionalData(f: Field, t: String): String {
    if (f.required) { t } else { "?${t} = None" }
}

/**
 * The local holding where child `f` was built: a string, a table, a union's value, a vector.
 */
func childOf(names: Names, f: Field): String {
    "${names.fieldName(f.name).replace("`", "")}Offset"
}

/**
 * Builds the child of field `f` before its table: what is not stored in the table itself.
 */
func packChild(w: CodeWriter, names: Names, f: Field): Unit {
    let field = names.fieldName(f.name)
    let child = childOf(names, f)
    match (f.fbType) {
        case ScalarType(_) => ()
        case StringType => packOptional(w, f, field, child) { v => "b.createString(${v})" }
        case NamedType(n) =>
            match (names.decl(n).kind) {
                case EnumDecl | StructDecl => ()
                case _ => packOptional(w, f, field, child) { v => "${v}.pack(b)" }
            }
        case VectorType(e) => packVector(w, names, field, child, e)
    }
}

/**
 * `let child = ` what `pack` builds of `field`, or of its value if it has one.
 */
func packOptional(
    w: CodeWriter,
    f: Field,
    field: String,
    child: String,
    pack: (String) -> String
): Unit {
    if (f.required) {
        w.line("let ${child} = ${pack(field)}")
    } else {
        w.line("let ${child} = ${field}.map {v => ${pack("v")}}")
    }
}

func packVector(w: CodeWriter, names: Names, field: String, child: String, e: FbType): Unit {
    match (e) {
        case StringType => w.line("let ${child} = b.createStringVector(${field})")
        case ScalarType(s) =>
            packElements(
                w,
                field,
                child,
                "${s.size}",
                "${s.size}",
                "b.add${s.cangjie}(${field}[i])"
            )
        case NamedType(n) =>
            let nd = names.decl(n)
            match (nd.kind) {
                case EnumDecl =>
                    let s = nd.underlying.getOrThrow()
                    packElements(
                        w,
                        field,
                        child,
                        "${s.size}",
                        "${s.size}",
                        "b.add${s.cangjie}(${field}[i].value)"
                    )
                case StructDecl =>
                    let data = names.dataName(n)
                    packElements(
                        w,
                        field,
                        child,
                        "${data}.SIZE",
                        "${data}.ALIGNMENT",
                        "b.addStruct(${field}[i].toBytes(), ${data}.ALIGNMENT)"
                    )
                case _ => w.line("let ${child} = b.createVector(${field}.map {v => v.pack(b)})")
            }
        case VectorType(_) => throw ConfigException("a vector of vectors is not a flatbuffers type")
    }
}

/**
 * A vector of values stored inline, added last to first.
 */
func packElements(
    w: CodeWriter,
    field: String,
    child: String,
    size: String,
    alignment: String,
    add: String
): Unit {
    w.line("b.startVector(${size}, ${field}.size, ${alignment})")
    w.block("for (i in ${field}.size - 1..=0 : -1)") { w.line(add) }
    w.line("let ${child} = b.endVector(${field}.size)")
}

/**
 * Adds field `f`, id `id`, to the table being built: a scalar or an enum only if it is not its default, a
 * struct in the table, an offset to its child, a union as its type then its value.
 */
func addField(w: CodeWriter, names: Names, f: Field, id: Int64): Unit {
    let field = names.fieldName(f.name)
    let child = childOf(names, f)
    match (f.fbType) {
        case ScalarType(s) =>
            w
                .block("if (${field} != ${scalarDefault(s, f.defaultValue)})") {
                    w.line("b.add${s.cangjie}(${field})")
                    w.line("b.slot(${id})")
                }
        case StringType => addOffsetField(w, f, child, id)
        case VectorType(_) =>
            w.line("b.addOffset(${child})")
            w.line("b.slot(${id})")
        case NamedType(n) =>
            let nd = names.decl(n)
            match (nd.kind) {
                case EnumDecl =>
                    let s = nd.underlying.getOrThrow()
                    w
                        .block("if (${field}.value != ${enumDefault(nd, f.defaultValue)})") {
                            w.line("b.add${s.cangjie}(${field}.value)")
                            w.line("b.slot(${id})")
                        }
                case StructDecl =>
                    let data = names.dataName(n)
                    if (f.required) {
                        w.line("b.addStruct(${field}.toBytes(), ${data}.ALIGNMENT)")
                        w.line("b.slot(${id})")
                    } else {
                        w
                            .block("if (let Some(v) <- ${field})") {
                                w.line("b.addStruct(v.toBytes(), ${data}.ALIGNMENT)")
                                w.line("b.slot(${id})")
                            }
                    }
                case UnionDecl =>
                    if (f.required) {
                        w.line("b.addUInt8(${field}.tag)")
                        w.line("b.slot(${id})")
                        w.line("b.addOffset(${child})")
                        w.line("b.slot(${id + 1})")
                    } else {
                        w
                            .block("if (let (Some(v), Some(o)) <- (${field}, ${child}))") {
                                w.line("b.addUInt8(v.tag)")
                                w.line("b.slot(${id})")
                                w.line("b.addOffset(o)")
                                w.line("b.slot(${id + 1})")
                            }
                    }
                case TableDecl => addOffsetField(w, f, child, id)
            }
    }
}

func addOffsetField(w: CodeWriter, f: Field, child: String, id: Int64): Unit {
    if (f.required) {
        w.line("b.addOffset(${child})")
        w.line("b.slot(${id})")
    } else {
        w
            .block("if (let Some(o) <- ${child})") {
                w.line("b.addOffset(o)")
                w.line("b.slot(${id})")
            }
    }
}

func checkWriterMembers(names: Names, d: Decl): Unit {
    for (f in d.fields where WRITER_MEMBERS.contains(names.fieldName(f.name))) {
        throw ConfigException("`${d.name}.${f.name}` is named like what the writer holds")
    }
}
