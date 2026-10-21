# ADR-0128: A member's overrides are matched by name and parameters, found down through each package's subtype edges

Status: accepted, 2026-10-20

## Context

- #389 (epic #205) asks for the members a member overrides or implements (up) and those overriding or implementing it (down): what `textDocument/implementation` answers, and what #390's references and #391's rename follow. N107's `notOverridden` already decides it at one member lookup, on one receiver.
- cjc 1.3.0-alpha.20261014 (N159–N163, in the PR): neither `override` nor `redef` is required (a static `Sub.t` without `redef` is called as `Sub.t()`, a `prop` implements without a keyword, a generic `id<U>` implements `id<T>`) (N159). A type's own member implements an interface an `extend` of it adds, and so does a member of another `extend` of the type (`extend Int64 { func m() }` with `extend Int64 <: K {}`); an `extend`'s member never implements what the type itself declares: "extend member 'k' is not allowed to shadow members" (N160). An `extend` adding an interface stands in the type's package or the interface's: "imported type 'C' cannot extend imported interface" (N161). Once `extend A <: I {}` is in `A`'s package, a `B <: A` overriding `A.g`, `override` written or not, is not called through `a: A` nor `i: I` at `-O0`, cjc's default: `A.g` runs; at `-O2` `B.g` does (N162, a bug of cjc's dispatch, not of its typing).
- R1 answers go to implementation by searching the impls of a trait in the crates that depend on it, per request, through its `TraitImpls` query per crate; gopls keeps a method-set index.

## Decision

- **A member matches another by its name, its kind (a function or a property), as static as it is, and its parameters seen on the type below** (`asMemberOf`, its own type parameters unknown), as N107: never by `override` or `redef` (N159). An overload of the name is no match.
- **Up** (`overriddenMembers`, tracked): the own members of every supertype of the member's type, as its file sees them, those an `extend` it sees adds included (`allSupertypes`), the nearest first. The members of a supertype's `extend`s are no candidates: "cannot override function 'e' in extend of supertype" (N163).
- **Down** (`overridingMembers`, tracked): the types and `extend`s below the member's type (`subtypesOf`), level by level, each read from a tracked function per package, `packageSubtypes`: its types and `extend`s by each declaration they name as a supertype, R1's `TraitImpls` per crate. Below an `extend` of a type, that type's own members and those of its `extend`s the `extend` sees implement too (N160), and the type's subtypes are below it in turn.
- **The packages searched down are those that may import the declaring one** (`importersOf`): of the modules whose dependencies hold its module, the binaries of its owner for a binary. A superset of its transitive importers, which every subtype and every `extend` naming the type is in (N161), with no import graph kept.
- **`textDocument/implementation`** (`implementationsAt`): of a member, what overrides or implements it; of a class or an interface, the types below it and the `extend`s declaring it, an `extend` at the type it extends. As `Location`s only.
- **The relation is cjc's typing, not its dispatch**: N162 is cjc's to fix, and the analysis does not follow it.

## Consequences

- One edit invalidates one package's edges; a request reads the edges of every package that may import the type's, each kept until its files change.
- A member of a type of std asked down reads every std package's edges once, and those of every package of the project.
- Up does not see an `extend` adding an interface in a package the member's file does not see (the interface's); down from the interface finds the member.
- #390 and #391 follow the hierarchy through these two queries.
