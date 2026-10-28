// ISSUE: 540
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: generics type arguments do not match the constraint of '(Generics-T) -> Unit'
// SOURCE: src/main.cj %f
// KNOWN-MISSING: d0 issue=540
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/generic_function_explicit_bad_bound/fixed/src/main.cj
// STEP: restored FROM broken
package audit
func g<T>(x: T): Unit where T <: ToString {}; func f(): Unit { g<() -> Unit>({ => }) }
//                                                               ^ d0 error: generics type arguments do not match the constraint of '(Generics-T) -> Unit'
