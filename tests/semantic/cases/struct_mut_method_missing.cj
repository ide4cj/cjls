// ISSUE: 533
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: instance member variable 'x' cannot be modified in immutable function
// SOURCE: src/main.cj %f
// KNOWN-MISSING: d0 issue=533
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/struct_mut_method_missing/fixed/src/main.cj
// STEP: restored FROM broken
package audit
struct S { var x = 0; func f(): Unit { x = 1 } }
//                                     ^ d0 error: instance member variable 'x' cannot be modified in immutable function
