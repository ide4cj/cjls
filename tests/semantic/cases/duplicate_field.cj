// ISSUE: 539
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: redefinition of declaration 'x'
// SOURCE: src/main.cj %f
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/duplicate_field/fixed/src/main.cj
// STEP: restored FROM broken
package audit
class C { let x = 1; let x = 2 }
//                       ^ d0 error: redefinition of declaration 'x'
