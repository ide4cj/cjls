// ISSUE: 542
// PACKAGE: audit .
// STEP: control
// CJC: audit clean
// SOURCE: src/main.cj %f
// SOURCE: src/declarations.cj inputs/audit.cj
package audit
func f(): Int8 { -128 }; func g(): Int8 { 127 }
