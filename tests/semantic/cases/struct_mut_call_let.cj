// ISSUE: 533
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: cannot use mutable function on immutable value
// SOURCE: src/main.cj %f
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/struct_mut_call_let/fixed/src/main.cj
// STEP: restored FROM broken
package audit
struct S { var x = 0; mut func f(): Unit { x = 1 } }; func g(): Unit { let s = S(); s.f() }
//                                                                                  ^ d0 error: cannot use mutable function on immutable value
