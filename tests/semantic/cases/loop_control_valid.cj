// ISSUE: 536
// PACKAGE: audit .
// STEP: control
// CJC: audit clean
// SOURCE: src/main.cj %f
// SOURCE: src/declarations.cj inputs/audit.cj
package audit
func f(b: Bool): Unit { while (b) { if (b) { break } else { continue } } }
