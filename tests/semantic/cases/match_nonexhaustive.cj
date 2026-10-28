// ISSUE: 537
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: non-exhaustive patterns
// SOURCE: src/main.cj %f
// EXPECT: d0 s0 error: non-exhaustive patterns
// KNOWN-MISSING: d0 issue=537
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/match_nonexhaustive/fixed/src/main.cj
// STEP: restored FROM broken
package audit
func f(b: Bool): Int64 { match (/*@s0*/b/*@/s0*/) { case true => 1 } }
