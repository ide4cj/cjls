// ISSUE: 532
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: invalid left-hand expression of assignment '='
// SOURCE: src/main.cj %f
// EXPECT: d0 s0 error: invalid left-hand expression of assignment '='
// KNOWN-MISSING: d0 issue=532
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/write_call/fixed/src/main.cj
// STEP: restored FROM broken
package audit
func g(): Int64 { 1 }; func f(): Unit { g() /*@s0*/=/*@/s0*/ 2 }
