// ISSUE: 539
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: redefinition of declaration 'x'
// SOURCE: src/main.cj %f
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/duplicate_local/fixed/src/main.cj
// STEP: restored FROM broken
package audit
func f(): Unit { let x = 1; let x = 2 }
//                              ^ d0 error: redefinition of declaration 'x'
