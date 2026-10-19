# ADR-0136: `a[i] op= v` and `a[i]++` are desugared in the HIR into the value they give a `[]` taking it

Status: proposed

## Context

- D64 typed `a[i] op= v` as `x op= v`, through the `[]` reading `a[i]`, and D134 left it as #245's; `x++` inferred its operand alone. Each is `Unit` to cjc too, but a lambda holding one fitted every candidate of a call: `run {x => x++}` and `idx {a => a[0] += 1}` were ambiguous where cjc takes one (#245, #48).
- cjc (R3) desugars both before it checks them:
  - `x++` is `x += 1` (`DesugarIncOrDecExpr`), and `SynIncOrDecExpr` first wants the place to be of an integer type ("the base of increment or decrement expressions should be of integer type"), a type's `+` no matter.
  - `a[i] op= v` of a type's `[]` is `a.[](i, value: a.[](i) op v)` (`DesugarSubscriptOverloadExpr`, `CreateArgumentForCompoundAssignOverload`): the outer call is chosen among the `[]`s taking `value!`, its last argument checked against each one's parameter; the inner one is a clone of the reading call. A type of none, or whose `value!` takes not what `op` gives, is "cannot assign to this subscript expression".
- cjc 1.3.0-alpha.20261014, checked in #245's PR:
  - N170: a lambda of `x++`, `a[0] += 1` or `a[0]++` fits only the candidate whose parameter makes it valid: of an `Int64` not a `String`, of a type with a `[](i, value!: Int64)` not one without, of an `ArrayList<Int64>` not an `ArrayList<String>`; a `[](i, value!: Int8)` of a `[]` reading an `Int64` takes no `a[0] += 1`.
  - N171: an operator of the language's types that the language's own does not take and the type declares none of, `x + "s"` or `y += "s"` of an `Int64`, makes a candidate a misfit too: `run {x => var y = x; y += "s"}` takes `(String) -> Unit`.
- loupe's HIR is a tree whose expressions all come from the syntax, but the `match`es an optional chain is lowered into (8g, A29); the outer call's last argument is an expression no syntax writes, and the candidates of the `[]` taking it are tried with it as any argument is.

## Decision

- **Desugared in the HIR** (option A of #245), as an optional chain is: `a[i] op= v` is `BinaryExpr(op=, a[i], AssignedExpr(op, a[i], v))`, `a[i]++` `PostfixExpr(a[i], ++, AssignedExpr(+, a[i], 1))`, the `AssignedExpr` and the `1` of no syntax. The place is the holder's child, not the value's: what walks a body walks it once. Option B, inference given an argument of a type and no expression, would have threaded a second kind of argument through every candidate tried, and checked `a[i] op v` without the type the candidate expects.
- **Inference calls the `[]` taking a value with it**, the `[]` reading `a[i]` called inside it, once per candidate; a type of no such `[]`, known wholly, is a misfit, as cjc's error. A tuple's or a `VArray`'s element stays the language's.
- **`x++` needs an integer**, read through the `[]` of `a[i]++`; another type, known wholly, is a misfit and an error type.
- **The `[]` taking a value is a second callee of `a[i]`** (`InferenceResult.calleesOf`), the reading one `calleeOf`, the operator the assignment's: go to definition on the bracket offers both, on `+=` the operator.
- **N171 holds for every operator**: the language's operator between its types, of none the type declares, that fails is a misfit, both sides known wholly.

## Consequences

- The gate finds no new diagnostic, on this repository or std's sources. 13 error roots of this repository are gone (`error_roots_known.txt`): `fixture/expect.cj`'s 8 locals and a member, `fixture/fixture.cj`'s 2 members, and a member of each generator's `code_writer.cj`.
- Not yet: reporting what fails (cannot assign, not an integer) is 8c′'s. A lambda whose body ends in a value not `Unit` (`run {x => x + "s"}`) fits no `(T) -> Unit` candidate, where cjc drops that value.
