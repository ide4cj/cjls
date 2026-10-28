// ISSUE: 528
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: cannot convert an integer literal to type 'Bool'
// SOURCE: src/main.cj %f
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/condition_wrong_type/fixed/src/main.cj
// STEP: restored FROM broken
package audit
func f(): Unit { if (1) { println(1) } }
//                   ^ d0 error: cannot convert an integer literal to type 'Bool'
