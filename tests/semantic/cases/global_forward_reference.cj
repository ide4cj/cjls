// ISSUE: 534
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: variable 'b' is used before being defined
// SOURCE: src/main.cj %f
// KNOWN-MISSING: d0 issue=534
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/global_forward_reference/fixed/src/main.cj
// STEP: restored FROM broken
package audit
let a = b; let b = 1
//      ^ d0 error: variable 'b' is used before being defined
