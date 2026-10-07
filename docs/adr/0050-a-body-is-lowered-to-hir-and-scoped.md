# ADR-0050: A body is lowered to HIR as rust-analyzer's, its scopes a query over it; the members of the type around it a level of the lookup

Status: accepted, 2026-10-06
Amends ADR-0047: the constructors of an enum any file of the package imports are seen in each

## Context

- D48 says what a name in a declaration's types means. A name in a body (#48 step 6) may also be a local: a parameter, a `let`, a local function, a parameter of a lambda, a name a pattern binds, a `catch`'s, a resource. What it sees depends on where it stands, not only on its name.
- cjc 1.3.0-alpha.20260918 on locals (N59–N74, #48 step 6): a local is seen after its declaration only, and not in its own initializer, a name before it meaning the one outside (N60, N61); a local function calls itself, not one declared after it; functions gather over the levels as at the top, a variable stops them (N63); what a `let … <-` binds is seen along its `&&` and in its block, not in `else` (N62); a pattern's lone name is a constructor if an enum of the package or of any of its files' imports has one by it, whatever a local says (N72, N73); between the locals and the file stand the members of the type around the body, its supertypes' and its `extend`s', a private one of a superclass found too (N69, N70); type parameters are values before a static member (N74).
- rust-analyzer (R1) lowers a body to `Body`: expressions and patterns in arenas, apart from where they are written (`BodySourceMap`); `ExprScopes` is a query over it, each `let` opening a scope for the rest of its block, which is N60 and N61. Rust has no implicit `this`: R1 has no level of members. K2 (R7) puts an implicit receiver's members, then its extensions, as levels of its tower between the locals and the imports; cjc does as much in `LookupImpl`.

## Decision

- **A body is lowered to HIR** (`bodyWithSourceMap(db, DefId)` / `body`): its expressions, patterns, locals, local functions and types each in an array, naming one another by index, every kind of expression lowered (inference reads the same); where each is written, apart. An edit that does not change the code, a comment, a blank line, or an edit elsewhere, leaves `body` equal. A body is a function's, a constructor's, a property's accessors', a variable's initializer; a parameter's default value is in its function's.
- **Local functions and lambdas are in their owner's body**, not items: cjc orders them as variables (N60).
- **The scopes are a query over the body** (`exprScopes`): a tree, each declaration opening a scope for what follows it, and the scope each expression and type sees. A block and the bindings before it are one scope in cjc, which shows only in a redefinition; nested here, they answer a lookup the same.
- **A name in a body is looked up outward** (`resolveBodyName`): the locals (a local function's type parameters among them), the declaration's type parameters, the members of the type around it, that type's type parameters, the file's scope (`lookUp`); the first that has it decides, but for functions, which gather (N63, N70). Whether a pattern's lone name binds is decided at the lookup, so the body and its scopes depend on nothing but the text.
- **The members' level is the type's own, its `extend`s' and its supertypes', level by level** (`membersNamed`): supertypes as the signature writes them, resolved, or as a `.cjo` has them (`binarySupertypes`); the `extend`s of the body's package and of the type's.
- **The constructors of an enum any file of a package imports are seen in each of its files** (N73), correcting D47's level of constructors.

## Consequences

- An edit to a body runs again that body's lowering and scopes, not another's, and nothing that read it if it leaves it equal.
- A member after a `.` (`x.foo`, `this.x`) is not resolved: it needs `x`'s type (step 7). Overrides are not told from overloads: a method and the one it overrides are both found until types tell them.
- The `extend`s of a package other than the body's and the type's, seen through an interface the file imports, and those of a type of a `.cjo` written in a `.cjo`, are not in the members' level; they are member lookup's, step 7.
- A name a macro declares does not resolve, as in D47; a `quote` or a macro call in a body is lowered to nothing.
- What cjc reports of locals (a redefinition in one block, N59, N64; a type declared in a body, N65; a binding in an `|` pattern, N66) is not reported yet.
