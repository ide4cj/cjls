// ISSUE: 544
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: mismatched types
// SOURCE: src/main.cj %f
// EXPECT: d0 s0 error: mismatched types: expected 'Int64', found 'String'
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/return_wrong_type/fixed/src/main.cj
// STEP: restored FROM broken
package audit
func f(): Int64 { return /*@s0*/"wrong"/*@/s0*/ }
