// ISSUE: 538
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: super class 'B' is not inheritable
// SOURCE: src/main.cj %f
// KNOWN-MISSING: d0 issue=538
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/inherit_final_class/fixed/src/main.cj
// STEP: restored FROM broken
package audit
class B {}; class C <: B {}
//                     ^ d0 error: super class 'B' is not inheritable
