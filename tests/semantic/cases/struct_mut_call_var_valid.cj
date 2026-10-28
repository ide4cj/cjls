// ISSUE: 533
// PACKAGE: audit .
// STEP: control
// CJC: audit clean
// SOURCE: src/main.cj %f
// SOURCE: src/declarations.cj inputs/audit.cj
package audit
struct S { var x = 0; mut func f(): Unit { x = 1 } }; func g(): Unit { var s = S(); s.f() }
