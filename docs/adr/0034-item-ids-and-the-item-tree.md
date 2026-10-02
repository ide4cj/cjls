# ADR-0034: An item is named by a hash of its parent and its name; a file's items are a tree with no ranges

Status: accepted, 2026-10-02

## Context

- What outlives a tree keeps a `SyntaxNodePtr` (A13): a kind and an absolute range. An edit anywhere above a declaration moves the range of every one under it, so a scope or a definition map holding pointers changes at every keystroke, never backdates, and everything that read it runs again (#97).
- Name resolution (#48) needs what a file declares without its bodies, as rust-analyzer's `ItemTree` (R1), and a way back from what it found to a node.
- rust-analyzer named an item by its index in the order of the file, so an item added above moved every id after it; it moved to a hash of the item's kind, name and parent, an index telling apart those with the same.
- Cangjie overloads by name (`func f(x: Int64)`, `func f(x: String)`), and declares unnamed items: `extend`s, macro calls on no declaration, `let` of a pattern.

## Decision

- **An `AstId` is (kind, hash, index)**: FNV-1a of the parent's id and the item's name, and the item's place among those of the file with the same kind and hash. The name is as written; `main`, `init`, `~init` for what a keyword names; for an `extend`, its type and bounds; for a `let` of a pattern, the pattern; for a macro call, its macro; for an import, its tree. Each without whitespace or comments. FNV, not `hashCode`, so the same file gives the same ids in every process.
- **An item** is an import, a declaration of the file or of a type's body (enum constructors included), the declaration under macro calls (its id is the declaration's; the macros and the modifiers of the calls go with it), each declaration of a `foreign` block (as the block's parent's, `foreign` added), and a macro call on no declaration. What a body declares is not an item: it is a block's, later.
- **Two queries per file, in `loupe.hir`.** `astIdMap`: each id to the pointer of its node and back; it changes with every edit that moves an item. `itemTree`: the package line, the imports (one path per leaf of their braces), and the items with their id, names, modifiers (in one order, whatever the order written), macros and members. No range, no body, no signature: a signature is a query of its own per item, `@When` comes with the project model (#69).

## Consequences

- An edit inside a body, a blank line, or an item added, removed or moved leaves the item tree equal and every other id as it was: what is keyed by an `AstId`, or holds one, does not run again (A19).
- Renaming an item gives it and its members new ids; an overload added before another moves the later one's index; a 64-bit collision is told by the index, at the cost of that stability.
- A modifier changed changes the item tree: visibility is resolution's to know.
- A definition across files, a file and an `AstId` interned, is #48's.
