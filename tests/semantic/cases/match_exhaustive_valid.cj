// ISSUE: 537
// PACKAGE: audit .
// STEP: control
// CJC: audit clean
// SOURCE: src/main.cj %f
// SOURCE: src/declarations.cj inputs/audit.cj
package audit
func f(b: Bool): Int64 { match (b) { case true => 1; case false => 2 } }
