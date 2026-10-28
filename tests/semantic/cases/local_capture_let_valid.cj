// ISSUE: 535
// PACKAGE: audit .
// STEP: control
// CJC: audit clean
// SOURCE: src/main.cj %f
// SOURCE: src/declarations.cj inputs/audit.cj
package audit
func f(): Unit { let x = 0; let g = { => x }; println(g()) }
