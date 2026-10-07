# ADR-0054: A type is an interned `Ty`; a declaration's signature is lowered to it in one query, of a source or a `.cjo` alike

Status: accepted, 2026-10-06

## Context

- D48 resolves a path in a type to declarations and leaves `Ty` to inference (#48 step 8). Inference compares types, substitutes their parameters and unifies them with its variables: it needs a type as a value, its names resolved, its aliases expanded (step 8a).
- rust-analyzer (R1) interns its `Ty` in salsa; a type parameter is a `Param` by its place among the generics of its owner, the parent's first; a signature is lowered by queries of their own (`ty`, `callable_item_signature`, `field_types`, `generic_predicates`), split mostly because of cycles through associated types, an alias expanded and its cycle an error. cjc hash-conses its `Ty`s in `TypeManager` (`GetClassTy(decl, args)` hands out one pointer), a `GenericsTy` per `GenericParamDecl`, and substitutes aliases in PreCheck (`ResolveTypeAlias`), after its cycle check; a `.cjo` keeps the `SemaTy`s it resolved, an alias kept as one (`Array<Byte>`).
- cjc 1.3.0-alpha.20260918 (N88–N92): `This` only as the whole return type of an instance function of a class ("'This' type is not allowed", "… here" in a static one); "undeclared type name"; a generic type of no argument ("generic type should be used with type argument"), in a supertype, an `extend`, an alias as well; as many arguments as no parameters ("type argument's number does not match type parameter's number"), a type parameter's or a non-generic type's included; "type cycle detected: 'X->Y->X'", once per alias of the cycle.

## Decision

- **A type is an interned `Ty`** (`@CalcaInterned`, as `DefId`): equal types are one id, compared and hashed as a number, held once whatever holds them; inference's result will hold one per expression (#159). Its kinds are cjc's that a signature writes: a type of the language, a declaration and its arguments (`DeclTy`: a class, interface, struct, enum or a type of the compiler's own), a tuple, a function (a `CFunc` a flag), a `VArray`, a type parameter (`ParamTy(owner, index)`, `GenericOf`'s), `This`, an error. A tree of values was the other way: simpler, compared and copied by its size.
- **A declaration's signature as types is one query** (`signatureTypes(db, DefId)`), `Signature`'s fields each a `Ty` and the errors found; a type's own `ty` is itself (`C<T>`), a constructor's its type's. R1's split into a query per question was the other way: Cangjie has no associated types, so a signature reads only other declarations' names and type parameters, and an alias's type.
- **Of a source and of a `.cjo` alike, in one step**: a `.cjo`'s `SemaTy`s, resolved by cjc, are read into the same `Ty`s, the alias it kept expanded; what a declaration of `std` is, inference reads as a source's.
- **An alias is expanded at the lowering**, its arguments substituted, as cjc and R1 do; an alias on a cycle is an error type, a fallback of the query (A14), the cycle named as cjc names it.
- **A type of a path is checked against its declaration's type parameters**, read from its `Signature` (A24), the missing ones error types, the extra ones dropped (R1's), each an error as cjc's.

## Consequences

- Every declaration of this repository has its signature as types, none an error: 23 068 types, 0.71 s cold on an M-series Mac (`SignatureTypesBench`). Of the `.cjo`s of the project, those of `std.ast`, `stdx.chir` and `stdx.syntax` name types of `flatbuffers`, which the SDK has no `.cjo` of: error types.
- The errors are found, not reported yet, as the bodies' are not (D50). cjc reports a cycle at the alias; here it is at the type the alias writes.
- A use of `This` keeps it, unsubstituted (`ThisTy`): the type of what a call is on is inference's. So is a type not written, and a literal's.
