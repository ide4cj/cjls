// ISSUE: 535
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: lambda capturing mutable variables needs to be called directly
// SOURCE: src/main.cj %f
// KNOWN-MISSING: d0 issue=535
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/local_capture_var/fixed/src/main.cj
// STEP: restored FROM broken
package audit
func f(): Unit { var x = 0; let g = { => x }; println(g()) }
//                                  ^^^^^^^^ d0 error: lambda capturing mutable variables needs to be called directly
