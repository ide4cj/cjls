// ISSUE: 544
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: mismatched types
// SOURCE: src/main.cj %f
// EXPECT: d0 s0 error: mismatched types: expected 'Int64', found 'Unit'
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/return_missing_path/fixed/src/main.cj
// STEP: restored FROM broken
package audit
func f(b: Bool): Int64 { /*@s0*/if (b) { return 1 }/*@/s0*/ }
