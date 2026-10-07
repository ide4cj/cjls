# ADR-0052: A name after a `.` is resolved by names up to a value, members looked up from a type; a value's member is inference's

Status: accepted, 2026-10-06

## Context

- D50 resolves a name used alone in a body. After a `.` it is left: `a.b` is a qualifier and its member (`pkg.f()`, `Foo.make()`, `Color.Red`, `T.make()`) or a value and its member (`x.foo`, `f().g`); Cangjie writes both with one `.`, which only what `a` names tells apart.
- cjc 1.3.0-alpha.20260918 (N75–N80, #48 step 7): the left of a `.` is looked up as any name of the body, a value of its name hiding a package or a type (N75); after a package, its declarations the file's package sees, no constructor and no package under it (N76); after a type, its members, static or not, and its enum's constructors (N77); after a type parameter, its bounds' (N78); `this` and `super` the type around the body and its superclass, `Object` if it names none (N79). A member's modifiers do not keep cjc from finding it: it reports "can not access", "no matching function" or "cannot access by type name" at the use (N80).
- rust-analyzer (R1) has no such question: Rust writes a qualifier with `::` and a member with `.`, the first a path of `hir_def`, the second inference's. K2 (R7), Java's ambiguous names and cjc's `MemberAccess` have Cangjie's: they look the left up as a qualifier, else as a value whose type they infer.
- The `extend`s cjc lets a file see are wider than D50's two packages: one through an interface the file imports, one a `.cjo` holds (N81–N86, #48 step 7b).

## Decision

- **A name after a `.` is resolved by names alone up to a value** (`resolveField`): after a package, a type, an alias of one, a type parameter, `this` or `super` (`receiverOf`); after a value it is `OfValue`, its type's, which inference answers (step 8). No type of a value is read from what a declaration writes (`let x: Foo`): it would be a second way to a value's type, the one inference replaces.
- **Members are looked up from types** (`memberLookup(types, name, from)`): the level of D50, started at the types given; `membersNamed` is it from the type around the body. Inference calls it with the head of a value's type, its arguments substituted after the lookup.
- **A member's modifiers do not hide it from the lookup** (N80): what is accessible is a check at the use, as D50 finds a private member of a supertype.
- **The `extend`s seen through an import and those of a `.cjo` are a step of their own** (7b): the lookup sees those of the body's package and of the type's, as D50.

## Consequences

- `this.x`, `super.f()`, `pkg.f()`, `Foo.make()`, `Color.Red` and `T.make()` go to their declarations; `x.foo` goes nowhere until inference.
- An override is not told from its overload: `this.f()` finds both (step 8).
- The members of a type of the language (`Int64.Max`) and those an `extend` of a `.cjo` or an imported interface brings are not found (7b); nor what a macro declares (D47).
