// ISSUE: 530
// PACKAGE: audit .
// STEP: control
// CJC: audit clean
// SOURCE: src/main.cj %f
// SOURCE: src/declarations.cj inputs/audit.cj
package audit
class C { let x: Int64; init() { this(1) }; init(x: Int64) { this.x = x } }
