// ISSUE: 537
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: non-exhaustive patterns
// SOURCE: src/main.cj %f
// KNOWN-MISSING: d0 issue=537
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/match_enum_nonexhaustive/fixed/src/main.cj
// STEP: restored FROM broken
package audit
enum E { A | B }; func f(e: E): Int64 { match (e) { case A => 1 } }
//                                             ^ d0 error: non-exhaustive patterns
