// ISSUE: 539
// PACKAGE: audit .
// STEP: control
// CJC: audit clean
// SOURCE: src/main.cj %f
// SOURCE: src/declarations.cj inputs/audit.cj
package audit
func f(x: Int64): Int64 { x }; func f(x: String): String { x }
