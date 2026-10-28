// ISSUE: 539
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: redefinition of declaration 'x'
// CJC: audit error: the pattern in this variable declaration can not match its type
// SOURCE: src/main.cj %f
// EXPECT: d0 s0 error: redefinition of declaration 'x'
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/pattern_duplicate_binding/fixed/src/main.cj
// STEP: restored FROM broken
package audit
func f(): Unit { let (x, /*@s0*/x/*@/s0*/) = (1, 2) }
