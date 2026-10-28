// ISSUE: 533
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: instance member variable 'x' cannot be modified in immutable function
// SOURCE: src/main.cj %f
// EXPECT: d0 s0 error: instance member variable 'x' cannot be modified in immutable function
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/struct_mut_method_missing/fixed/src/main.cj
// STEP: restored FROM broken
package audit
struct S { var x = 0; func f(): Unit { /*@s0*/x/*@/s0*/ = 1 } }
