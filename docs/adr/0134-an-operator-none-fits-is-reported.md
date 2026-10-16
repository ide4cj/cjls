# ADR-0134: An operator none of whose candidates fits is reported at the operator; of one declared candidate it is of its return type, as a call of one, and between the language's types an error

Status: proposed. Supersedes D64's consequence of an operator of one candidate.

## Context

- D64 took a type's one operator untried, so `3 * "s"` was a `Duration` (`Int64`'s one `*`, an `extend` of std's `*(Duration)`) and `t + "s"` of a `T` with one `+` its `Bool`, the operand reported as a mismatch against that `+`'s parameter; an operator none of several fits, or of none, was quiet (#244, #48).
- D55 keeps a call of one function its return type whatever its arguments, as R1 does, a mismatch reported at the argument: `one("s")` a `Bool`. cjc (R3) types such a call an error, so a use of it is no further error.
- cjc 1.3.0-alpha.20261014, checked in #244's PR:
  - N168: a binary operator none of whose candidates fits its operands, of one, two or none, is "invalid binary operator '+' on type 'Class-T' and 'Struct-String'" at the operator, the expression an error; a `[]` is "mismatched types" at its argument, against the first; a candidate the type expected rejects is taken without it, the result "mismatched types" at the expression (`let a: String = t + 1`).
  - N169: a number of no suffix is of the other side's type through an arithmetic of two such but `**`, bitwise ones included, and as the left of a shift: `(1 << UInt64(k)) | m` and `(1 & 2) + m` of `m: UInt64` are `UInt64`, `(2 ** 3u64) | m` invalid.

## Decision

- **An operator is a call of its candidates, the language's own one of them**: one a type declares, alone, is taken untried as a call of one is (D55), its return type kept; between the language's types (numbers, `Bool`, tuples) the language's operator is a candidate too, so `3 * "s"` is of two, of which none fits: an error type. The user's choice: a candidate as unambiguous as a function called by name gives what it returns, as R1; of several, cjc's error.
- **Several are tried with the type expected, failing that without it**, as cjc checks and then synthesizes: what the one taken returns is then checked against what is expected, as any value is.
- **`InvalidBinaryOperator(expr, left, right)`**, an `InferenceDiagnostic` (D90), at the operator token: when the language's fails and no declared candidate takes the right's type synthesized alone (a number any number type), both known wholly, and the left's type no macro whose expansion is not read may declare an operator of. Taking the operand's type, not whether a try counted a mismatch, keeps a gap inside the operand (`alias.map {…} ?? ""` of an `Option<{unknown}>`) from reporting the operator. `x op= v` is #245's; a `[]` stays a call, its argument reported.
- **N169 is closed here**: a number written, negated, an arithmetic of two but a power, or a shift of one is of the other side's type, which was a root of an error type in `fnum`'s Ryu.

## Consequences

- D64's last consequence is replaced: an operator of one candidate is its return type only if that candidate is a type's own and the language has none between its operands.
- The gate finds no diagnostic on this repository; on std's sources one, a `>` of a `T <: ArbitraryRange<T>`, whose `Comparable<T>` comes from `ArbitraryRange`'s own `where`, which cjls does not read yet: listed under #437. The error roots of `fnum/src/ryu.cj` (2 locals, 2 `|`) are gone.
- Not yet: a call of several none of which fits stays quiet (cjc reports against the first), as does a unary operator of none.
