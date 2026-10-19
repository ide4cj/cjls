# ADR-0140: An enum's constructors of one name are overloads, narrowed by arity and type arguments before a call tries them

Status: proposed

## Context

- A name of several constructors (`Ctors(own, imported)`, N46) was one constructor or none: the expected enum's, else the package's own if one. Type arguments written and a call's arguments were not looked at, so `None<String>` beside an imported `Kind.None` was an error type, beside the package's own `None` that one's type; `Full("a", 1)` of an enum of `Full/2` and `Full/3` none (#278, #279, #48).
- R1 has nothing to say: Rust has no overloads, a constructor is a path. cjc is the specification (D15).
- N172, cjc 1.3.0-alpha.20261014, checked in this ADR's PR:
  - type arguments written keep the constructors of an enum of as many type parameters, before the package's own come first: `None<String>` beside the package's `enum Own { None }` is `Option<String>`, `None<Int64, String>` beside `Pair<A, B>.None` a `Pair`; `None<String>` of `Mine<T>.None` and `Option<T>.None` is "find multiple constructor";
  - a call keeps those of as many parameters as it passes, before the package's own come first: the package's `Full(String)` leaves `Full("c", 3, true)` to an imported `Other.Full/3`;
  - of these, the expected enum's (`let b: Other = Full(…)` takes `Other`'s over the package's own), else the package's own, **though their types fit not**: the package's `Part(String, Int64, Int64)` hides an imported `Part(String, Int64, Bool)` from `Part("d", 4, true)`, "cannot convert a boolean literal", where a function of the package that fits not leaves the call to an imported one (D63, N115);
  - the arguments' types choose among those left, `V(1)` of `A.V(String)` and `B.V(Int64)` is `B`'s; two that fit are "find multiple constructor" (N120);
  - not called, a name of two constructors of one enum is no value ("undeclared identifier"), whatever is expected;
  - a pattern takes the constructor of as many parameters as it has patterns.

## Decision

- **Narrowed, then tried**: `ctorCandidates` keeps, in N172's order, those of as many type parameters as written, of as many parameters as the call passes, the expected enum's if any, else the package's own if any; a call tries all that are left as the overloads of a function are (`chooseOverload`, D63), a value takes only one. Not a chooser of its own: the types of the arguments, lambdas and type arguments not written are tried by the one machinery a call has.
- **Constructors of two enums hide none**: `overriding` (N107) leaves them both, so two that fit are ambiguous, not the first.
- **The constructor taken is the callee** (`calleeOf`), of one left too: go to definition and hover go to it, not to every constructor of the name.

## Consequences

- The gate finds no new diagnostic, on this repository or std's sources. 30 error roots of this repository are gone (`error_roots_known.txt`), all its `name not found`: `None<…>` in `cjls.handlers` beside `TextDocumentSyncKind.None`, std.argopt's `ArgumentSpec.Full` in `command.cj`, and 3 locals of `to_proto.cj` made of them.
- Not yet: the error cjc reports of a name of several constructors (`find multiple constructor`) is 8c′'s, as the other names not found are (#175).
