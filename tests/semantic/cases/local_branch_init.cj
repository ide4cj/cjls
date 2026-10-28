// ISSUE: 534
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: variable 'x' is used before initialization
// SOURCE: src/main.cj %f
// EXPECT: d0 s0 error: variable 'x' is used before initialization
// KNOWN-MISSING: d0 issue=534
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/local_branch_init/fixed/src/main.cj
// STEP: restored FROM broken
package audit
func f(b: Bool): Int64 { var x: Int64; if (b) { x = 1 }; /*@s0*/x/*@/s0*/ }
