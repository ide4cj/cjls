// ISSUE: 529
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: 'this' is not allowed to be accessed before all member variables are initialized
// SOURCE: src/main.cj %f
// KNOWN-MISSING: d0 issue=529
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/field_this_escape/fixed/src/main.cj
// STEP: restored FROM broken
package audit
class C { let x: Int64; init() { use(this); x = 1 } }; func use(c: C): Unit {}
//                                   ^ d0 error: 'this' is not allowed to be accessed before all member variables are initialized
