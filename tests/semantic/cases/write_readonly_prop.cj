// ISSUE: 532
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: cannot assign to immutable value
// SOURCE: src/main.cj %f
// KNOWN-MISSING: d0 issue=532
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/write_readonly_prop/fixed/src/main.cj
// STEP: restored FROM broken
package audit
class C { prop x: Int64 { get() { 1 } }; func f(): Unit { x = 2 } }
//                                                        ^^^^^ d0 error: cannot assign to immutable value
