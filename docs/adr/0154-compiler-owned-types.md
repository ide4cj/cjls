# ADR-0154: Compiler-owned types have semantic heads and scoped declarations

Status: accepted

## Context

D66 chose declaration-independent types for `CPointer`, `CString`, `RawArray`,
`VArray` and `CFunc` (#218). Their names and extension lookup still depended on
`std.core.cjo`, preventing analysis of `std.core` as a source package. A fallback
for familiar spellings would bypass imports, shadowing and `RawArray` visibility.

## Decision

Give source `std.core` a synthetic item-file origin, containing the five
`BuiltIn` declarations cjc adds in `TypeChecker.cpp`. Its identity belongs to the
package, so reordering or removing source files does not rename a builtin.
Keep `RawArray` internal and the others public; `CPointer<T>` has the `CType`
bound. Ordinary package scopes, imports and aliases resolve these declarations.
A misspelled name remains unresolved.

Retain a binary `BuiltInDecl` as a scoped declaration for navigation and generic
metadata. Lower pointer, C string and raw array types to compiler-owned semantic
heads; retain the existing function and fixed-size-array representations for
`CFunc` and `VArray`. Binary type records need no `std.core` declaration to
identify these types. Extensions are indexed by semantic head, and their generic
arguments are matched and substituted as for ordinary generic types.

## Consequences

Source and binary signatures share type identity without sharing declaration
identity. Synthetic declarations have no source navigation target. Source
`std.core` participates in the diagnostics gate; its known-gap baseline must not
grow to accommodate this change.
