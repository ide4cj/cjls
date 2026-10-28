// ISSUE: 529
// PACKAGE: audit .
// STEP: control
// CJC: audit clean
// SOURCE: src/main.cj %f
// SOURCE: src/declarations.cj inputs/audit.cj
package audit
class C { let x: Int64; init() { x = 1; use(this) } }; func use(c: C): Unit {}
