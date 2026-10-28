package loupe

import std.collection.{ArrayList, HashMap, HashSet}
import std.deriving.Derive
import loupe.hir.{DefId, Ty}
import py_interop.*
import py_interop.internal_macros.DerivePython

/**
 * A declaration in a completion group, seen through its receiver type when it is a member.
 */
@DerivePython
public struct CompletionOverload <: Equatable<CompletionOverload> {
    public CompletionOverload(public let id: DefId, public let receiver: ?Ty) {}

    public operator func ==(other: CompletionOverload): Bool {
        id == other.id && receiver == other.receiver
    }

    public operator func !=(other: CompletionOverload): Bool {
        !(this == other)
    }
}

/**
 * The group a declaration belongs to. Kinds stay distinct: a constructor and its type insert
 * the same name but offer different things. All members of a group currently insert only its
 * label; future import edits or argument snippets must distinguish different insertions (D149).
 */
func completionOverloadKey(item: CompletionItem): ?String {
    if (item.kind != CompletionKind.FuncItem && item.kind != CompletionKind.CtorItem) {
        return None
    }
    match (item.source) {
        case DeclSource(_, _) => "${item.label}#${item.kind}"
        case _ => None
    }
}

/**
 * Already ranked and deduplicated items, with overloads grouped at their first member's position.
 * Keep receiver types with each declaration so resolving generic members substitutes correctly.
 */
func groupCompletionOverloads(items: Array<CompletionItem>): Array<CompletionItem> {
    let groups = HashMap<String, ArrayList<CompletionOverload>>()
    for (item in items) {
        let key = completionOverloadKey(item) ?? continue
        let decl =
            match (item.source) {
                case DeclSource(id, recv) => CompletionOverload(id, recv)
                case _ => continue
            }
        if (let Some(group) <- groups.get(key)) {
            group.add(decl)
        } else {
            groups[key] = ArrayList<CompletionOverload>([decl])
        }
    }
    let emitted = HashSet<String>()
    let result = ArrayList<CompletionItem>()
    for (item in items) {
        if (let Some(key) <- completionOverloadKey(item) && let Some(group) <- groups.get(key) &&
            group.size > 1) {
            if (emitted.add(key)) {
                result
                    .add(
                        CompletionItem(
                            item.label,
                            item.kind,
                            item.relevance,
                            OverloadSource(group.toArray())
                        )
                    )
            }
        } else {
            result.add(item)
        }
    }
    result.toArray()
}
