// ISSUE: 530
// PACKAGE: audit .
// STEP: control
// CJC: audit clean
// SOURCE: src/main.cj %f
// SOURCE: src/declarations.cj inputs/audit.cj
package audit
open class B { init(x: Int64) {} }; class C <: B { init() { super(1) } }
