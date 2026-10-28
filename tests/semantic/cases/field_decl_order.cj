// ISSUE: 529
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: variable 'b' is used before initialization
// SOURCE: src/main.cj %f
// KNOWN-MISSING: d0 issue=529
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/field_decl_order/fixed/src/main.cj
// STEP: restored FROM broken
package audit
class C { let a = b; let b = 1 }
//                ^ d0 error: variable 'b' is used before initialization
