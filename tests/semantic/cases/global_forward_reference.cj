// ISSUE: 534
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: variable 'b' is used before being defined
// SOURCE: src/main.cj %f
// EXPECT: d0 s0 error: variable 'b' is used before being defined
// KNOWN-MISSING: d0 issue=534
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/global_forward_reference/fixed/src/main.cj
// STEP: restored FROM broken
package audit
let a = /*@s0*/b/*@/s0*/; let b = 1
