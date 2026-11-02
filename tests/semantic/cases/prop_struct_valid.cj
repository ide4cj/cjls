// ISSUE: 531
// PACKAGE: audit .
// STEP: control
// CJC: audit clean
// SOURCE: src/main.cj %f
// SOURCE: src/declarations.cj inputs/audit.cj
package audit
struct C { mut prop x: Int64 { get() { 1 } set(v) {} } }
