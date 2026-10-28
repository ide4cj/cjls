// ISSUE: 534
// PACKAGE: audit .
// STEP: control
// CJC: audit clean
// SOURCE: src/main.cj %f
// SOURCE: src/declarations.cj inputs/audit.cj
package audit
func f(b: Bool): Int64 { let x: Int64; if (b) { x = 1 } else { x = 2 }; x }
