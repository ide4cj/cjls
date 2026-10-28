// ISSUE: 529
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: variable 'x' is used before initialization
// SOURCE: src/main.cj %f
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/field_read_before_init/fixed/src/main.cj
// STEP: restored FROM broken
package audit
class C { let x: Int64; let y: Int64; init() { y = x; x = 1 } }
//                                                 ^ d0 error: variable 'x' is used before initialization
