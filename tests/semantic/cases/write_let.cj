// ISSUE: 532
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: cannot assign to immutable value
// SOURCE: src/main.cj %f
// KNOWN-MISSING: d0 issue=532
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/write_let/fixed/src/main.cj
// STEP: restored FROM broken
package audit
func f(): Unit { let x = 1; x = 2 }
//                          ^^^^^ d0 error: cannot assign to immutable value
