# ADR-0157: Type parameter binders include local functions without making them declarations

Status: accepted, 2026-10-30
Amends ADR-0057: an open callee may name a local function binder

## Context

D50 keeps local functions inside their enclosing body rather than allocating
items for them. Their generic names already resolve, but `ParamTy(DefId, index)`
could only name declaration parameters. Consequently local generic signatures,
bodies and calls had unknown types (#241).

## Decision

Use one `ParamTy(GenericOwner, index)` representation for both declaration and
local function parameters. `GenericOwner` is either a declaration's `DefId` or
an enclosing body's `DefId` plus its local function index. Reusing `ParamTy`
keeps substitution, subtype relations and D57's solver uniform; a separate local
type kind would duplicate these operations. Synthetic declarations would break
D50's body ownership and introduce a second identity for locals.

A local function callable retains its binder while its type arguments are open.
Explicit arguments substitute that binder; inferred calls use the existing
solver and overload journal. Local `where` bounds use the same bounded expansion
as declaration bounds. Their query key is the enclosing declaration and local
index, and reads the body; no query reads its inference result to lower bounds.

## Consequences

Local and enclosing parameters remain distinct even when both are named `T`.
Substitution changes only the selected binder, preserving captured outer types.
Local function identities and bounds invalidate with the owning body. Navigation
maps a local parameter back through its existing `LocalGenericOf` target.
