// ISSUE: 540
// PACKAGE: audit .
// STEP: control
// CJC: audit clean
// SOURCE: src/main.cj %f
// SOURCE: src/declarations.cj inputs/audit.cj
package audit
class Box<T> where T <: ToString {}; func f(): Unit { let b = Box<Int64>() }
