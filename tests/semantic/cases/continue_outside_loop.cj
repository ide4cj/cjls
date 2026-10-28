// ISSUE: 536
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: 'break' or 'continue' must be used inside a loop
// SOURCE: src/main.cj %f
// KNOWN-MISSING: d0 issue=536
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/continue_outside_loop/fixed/src/main.cj
// STEP: restored FROM broken
package audit
func f(): Unit { continue }
//               ^ d0 error: 'break' or 'continue' must be used inside a loop
