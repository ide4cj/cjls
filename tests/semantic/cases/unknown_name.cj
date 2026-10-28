// ISSUE: 541
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: undeclared identifier 'missing'
// SOURCE: src/main.cj %f
// EXPECT: d0 s0 error: undeclared identifier 'missing'
// KNOWN-MISSING: d0 issue=541
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/unknown_name/fixed/src/main.cj
// STEP: restored FROM broken
package audit
func f(): Unit { /*@s0*/m/*@/s0*/issing() }
