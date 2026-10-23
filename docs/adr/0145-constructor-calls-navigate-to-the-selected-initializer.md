# ADR-0145: Constructor calls navigate to the selected initializer, and declarations to their type

Status: proposed
Amends ADR-0063: a class or struct call goes to the initializer selected by inference, rather than directly to the type

## Context

D63 records the overload selected by inference, but deliberately sends a class or
struct call to the type. That hides which initializer the arguments selected.
Sending the call only to its initializer would make the type harder to reach.
Enum calls already navigate to their selected constructor (D140).

The selected callee also supplies semantic identity for hover and reference
searches: changing the identity of a class call to its initializer would change
what they show and find for the type.

## Decision

A constructor call and its declaration form two successive navigation steps:
`C(args)` goes to the selected explicit initializer, and a request on `init` or
a primary constructor's name goes to the owning type. An enum constructor call
continues to go to its selected overload; its declaration goes to the enum.

Record initializer selection through the existing overload journal, but expose
it separately from ordinary callee identity. The navigation policy is A37 in
[the analysis rules](../design/02-analysis.md#a37-constructor-navigation).

## Consequences

Both the selected overload and its type are reachable without a second command.
An initializer target selects the `init` keyword, so the next request can follow
it to the type. Class/struct hover and references retain the identity of the type.

The existing inference rules still decide the overload, including enum argument
types, arity and the expected enum type. Navigation makes no choice of its own;
without a selected explicit initializer, a class/struct call keeps its type target.
