package lsp_codegen

import std.collection.{HashMap, collectArray, filter, filterMap}
import ftoml.*

enum TypeBinding {
    /**
     * We declare it, under this identifier.
     */
    | Owned(String)

    /**
     * Declared elsewhere. A `public type <lspName> = <target>` is emitted for it and references
     * keep using the metaModel name, so generated signatures still read like the specification.
     */
    | Aliased(String)

    /**
     * Declared elsewhere. References resolve straight to the target and no alias is emitted. An
     * enumeration's values are adopted onto the target, except those it already declares itself.
     */
    | Extern(String, Array<String>)

    /**
     * Neither declared nor referred to - the metaModel entry is dropped outright.
     */
    | Skipped

    /**
     * The identifier a reference to `lspName` resolves to, or `None` when the entry is dropped.
     */
    func typeNameOf(lspName: String): ?String {
        match (this) {
            case Owned(ident) => ident
            case Aliased(_) => lspName
            case Extern(target, _) => target
            case Skipped => None
        }
    }
}

struct TypeMap <: FromToml<TypeMap> {
    TypeMap(let entries!: HashMap<String, TypeBinding> = HashMap<String, TypeBinding>()) {}

    func bind(lspName: String): TypeBinding {
        entries.get(lspName) ?? TypeBinding.Owned(lspName)
    }

    /**
     * `(lspName, target)` of every aliased entry
     */
    func aliases(): Array<(String, String)> {
        entries |> filterMap {
            entry: (String, TypeBinding) => match (entry[1]) {
                case Aliased(target) => (entry[0], target)
                case _ => None
            }
        } |> collectArray
    }

    /**
     * @throws FtException - if an entry is not a table, or sets other than exactly one of the
     * mutually exclusive keys, placed at it.
     */
    public static func fromToml(v: FtValue): TypeMap {
        let entries = HashMap<String, TypeBinding>()
        for ((lspName, entry) in v.asTable()) {
            entries.add(lspName, bindingOf(lspName, entry))
        }

        TypeMap(entries: entries)
    }
}

private func bindingOf(lspName: String, v: FtValue): TypeBinding {
    let entry = v.asTable()

    let declared = entry.get("declared").map {it => declaredOf(it)}
    let fields = entry.iterator() |> filter {it: (String, FtValue) => it[0] != "declared"} |> collectArray
    if (fields.isEmpty()) {
        throw v.error("`types.${lspName}` sets none of `rename`, `alias`, `extern`, `skip`")
    }

    if (fields.size > 1) {
        throw v.error("`types.${lspName}` sets more than one of `rename`, `alias`, `extern`, `skip`")
    }

    let (key, data) = fields[0]
    if (key != "extern" && declared.isSome()) {
        throw v.error("`types.${lspName}.declared` goes only with `extern`")
    }
    match (key) {
        case "rename" => Owned(targetOf(lspName, key, data))
        case "alias" => Aliased(targetOf(lspName, key, data))
        case "extern" => Extern(targetOf(lspName, key, data), declared ?? [])
        case "skip" where data.asBool() => Skipped
        case _ => throw v.error("unknown field \"${key}\"")
    }
}

private func declaredOf(v: FtValue): Array<String> {
    Array<String>.fromToml(v)
}

/**
 * The Cangjie identifier a binding points at. A blank one would emit `public type LSPAny = ` and
 * only surface as a syntax error in the generated file, far from the config line that caused it.
 */
private func targetOf(lspName: String, key: String, v: FtValue): String {
    let target = v.asString().trimAscii()
    if (target.isEmpty()) {
        throw v.error("`types.${lspName}.${key}` must not be empty")
    }

    target
}
