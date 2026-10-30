// ISSUE: 423
// PACKAGE: audit .
// STEP: control
// CJC: audit clean
// SOURCE: src/main.cj %f
package audit
import std.overflow.*
@OverflowThrowing main(): Int64 { 0 }
