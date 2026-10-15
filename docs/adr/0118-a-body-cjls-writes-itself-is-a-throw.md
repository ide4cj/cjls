# ADR-0118: A body cjls writes in an expansion of its own is a throw

Status: proposed
Amends ADR-0114: the `extend`s an outer macro copies have bodies that throw, not empty ones

## Context

- cjls writes the expansions of std's `@Derive` and of `std.unittest.testmacro`'s macros itself, signatures only (#175). Each member's body was `{}`: cjsyntax needs a body of a function or a property in an `extend`, a `struct` or a `class` that is not abstract, and so does `parseDecl` of a workspace macro the `extend` is sent to (D114).
- `{}` is a body of `Unit`. On `hashCode(): Int64` it is a wrong one, and reads as a `hashCode` that does nothing: the user of `cjls/expandMacro` (D103) sees a lie, one the leading comment has to disclaim. The analysis lowers no body of an expansion, so nothing reports it.
- The alternatives: no body, which cjsyntax reports and the macro server's `parseDecl` may reject; a body of a comment alone, still `{}` to a compiler; a `throw`, whose type `Nothing` is a body for any return type, in a block of its own lines an editor folds, and a true statement of what cjls wrote.

## Decision

- **Every body cjls writes in an expansion of its own is `throw UnsupportedException("cjls wrote no body")`**, on a line of its own in a block (`stubBody`), under a member's indent. It is the one body of the `extend`s of `@Derive`, of `@Test`'s `asTestSuite` and registrations, and of `@UnittestOption`'s getters.
- The comment `cjls/expandMacro` and the expanded file start with says so: `signatures only, every body throws`.

## Consequences

- The expansion is Cangjie cjc would type: an outer workspace macro given it (D114) copies bodies that throw, and a macro that reads them sees a throw, where it saw nothing.
- A block folds; whether the editor folds it on opening is the editor's own. The server folds nothing for it, and the one-line `{ throw … }` was not chosen: three lines read as a stub, one as a signature with noise after it.
- Once #176's step 4 runs std's macros in the macro server, cjc's own bodies replace these, and nothing here is read.
