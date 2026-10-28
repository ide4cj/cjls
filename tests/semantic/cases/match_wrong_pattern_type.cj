// ISSUE: 537
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: cannot convert an integer literal to type 'Bool'
// SOURCE: src/main.cj %f
// EXPECT: d0 s0 error: cannot convert an integer literal to type 'Bool'
// KNOWN-MISSING: d0 issue=537
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/match_wrong_pattern_type/fixed/src/main.cj
// STEP: restored FROM broken
package audit
func f(b: Bool): Int64 { match (b) { case /*@s0*/1/*@/s0*/ => 1; case _ => 2 } }
