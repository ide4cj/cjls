// ISSUE: 534
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: variable 'x' is used before initialization
// SOURCE: src/main.cj %f
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/local_uninitialized/fixed/src/main.cj
// STEP: restored FROM broken
package audit
func f(): Int64 { var x: Int64; x }
//                              ^ d0 error: variable 'x' is used before initialization
