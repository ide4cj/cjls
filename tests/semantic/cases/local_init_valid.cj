// ISSUE: 534
// PACKAGE: audit .
// STEP: control
// CJC: audit clean
// SOURCE: src/main.cj %f
// SOURCE: src/declarations.cj inputs/audit.cj
package audit
func f(): Int64 { let x: Int64; x = 1; x }
