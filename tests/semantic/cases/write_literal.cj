// ISSUE: 532
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: invalid left-hand expression of assignment '='
// SOURCE: src/main.cj %f
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/write_literal/fixed/src/main.cj
// STEP: restored FROM broken
package audit
func f(): Unit { 1 = 2 }
//                 ^ d0 error: invalid left-hand expression of assignment '='
