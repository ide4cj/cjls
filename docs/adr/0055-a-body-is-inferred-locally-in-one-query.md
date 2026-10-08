# ADR-0055: A body's types are inferred locally, as cjc checks them, in one query of the body; a type not written is the body's

Status: accepted, 2026-10-07

## Context

- D54 gives every signature its types; a body's are inference's (#48 step 8b): what a member after the `.` of a value is (D52's `OfValue`), and then a hover, inlay hints, completion.
- rust-analyzer (R1) infers a body in one query (`infer(DefWithBodyId)`), unifying over the whole body: a variable of type `?T` may be told by a use twenty lines on. Rust has no subtyping, so equality is all it unifies. cjc (R3) checks bidirectionally (`Synthesize`, `Check` against an expected type); type variables live only within a call, for its type arguments, solved by `LocalTypeArgumentSynthesis` with upper and lower bounds, as `arg <: param`; branches are joined (`JoinAndMeet`); a literal's ideal type takes the type expected. Kotlin's K2 (R7, and R9 after it) solves a system per call too.
- In Cangjie a local of no initializer writes its type, and types have subtypes: nothing flows back through a body.
- cjc 1.3.0-alpha.20260918 (N97–N107): branches join to the one least common supertype, `Nothing` left out, else "types … of the two branches … mismatch" (two classes of one interface have two); a literal takes its suffix's type, else the type expected, `?T` looked through, else `Int64` or `Float64`, never another branch's (`1` and `2u8` mismatch), an integer no float; an operator of the language gives a literal the other side's type; a type not written is the body's: a function's block joined with its `return`s, a variable's initializer, and one calling itself, or on a cycle, "unable to infer return type"; a member of a value is seen with the arguments its type gives it, through supertypes and `extend`s, `This` its type; a lambda's parameters are the function type expected's; an override hides what it overrides.

## Decision

- **Local inference, as cjc's**: each expression synthesized, or checked against the type expected of it, which goes down to literals, lambdas, branches, the elements of an array or tuple, `None`; no variable spans a body. R1's unification over the body was the other way: Cangjie needs none, and its subtypes would have been coercions on top, each proven against cjc.
- **One query per body**, `inferBody(db, DefId)`, as R1's: the type of each expression, pattern and local, by id, and the members found after the `.` of a value. A query per expression, inferring only what a request asks, was the other way: many small memos, and what is expected comes from the root anyway.
- **A type a signature does not write is the body's** (`declaredTyOf`): a function's return type, a variable's. A body does not read its own while it infers it (an error, as cjc's); a cycle of such declarations is calca's fallback, every query on it an error (A14).
- **A member of a value is looked up from its type** (`memberLookup` at its declaration, a type parameter's at its bounds), seen on it (`asMemberOf`): the parameters of the type or `extend` it is in as the value's type is an instance of it, `This` the value's type. An `extend` of another instance (`extend Box<Int64>` for a `Box<String>`) is none of its members, and a member another nearer one overrides is hidden: what was a gap of 7b for a value. `definitionAt` goes to it.
- **A call takes the one callee of as many parameters as it has arguments**, the others hidden by an override; one it cannot tell is an error type, its arguments inferred alone. Type arguments not written are not inferred: an error type, 8c's; overloads 8d's; operators a type declares, `?.`, `??`, `|>` and `[]` 8e's.

## Consequences

- On this repository (5c67102), 139 806 expressions, 14 811 of no type but those that are no value (a macro, a type or package before a `.`, the callee of a call of no type): calls (3 902) and names (3 177) of members a macro declares (D47's gap) and of overloads (8d); `[]` (1 197 of 1 297), binary operators (2 090: `??` and operators of types) and `?.` (76 of 76), 8e's; the blocks (3 133), members (874) and branches (`match` 130, `if` 83, `try` 16) of what has none. A cold pass over every body 8.4–8.6 s in three runs on filaco.dev's Ryzen 7 8845HS; `InferenceBench` reads the memos, 14.4–14.8 ms.
- The errors are not found yet: a mismatch needs subtyping checked against cjc at each use, and is 8c's with the constraints.
- A local function's type parameters have no `Ty` yet: an error type.
