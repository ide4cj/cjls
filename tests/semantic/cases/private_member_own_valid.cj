// ISSUE: 541
// PACKAGE: audit .
// STEP: control
// CJC: audit clean
// SOURCE: src/main.cj %f
// SOURCE: src/declarations.cj inputs/audit.cj
package audit
class C { private let x = 1; func f(): Int64 { x } }
