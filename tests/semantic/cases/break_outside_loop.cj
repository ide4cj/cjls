// ISSUE: 536
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: 'break' or 'continue' must be used inside a loop
// SOURCE: src/main.cj %f
// EXPECT: d0 s0 error: 'break' or 'continue' must be used inside a loop
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/break_outside_loop/fixed/src/main.cj
// STEP: restored FROM broken
package audit
func f(): Unit { /*@s0*/b/*@/s0*/reak }
