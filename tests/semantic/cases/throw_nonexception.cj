// ISSUE: 543
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: the object thrown must derive from `core.Exception`
// SOURCE: src/main.cj %f
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/throw_nonexception/fixed/src/main.cj
// STEP: restored FROM broken
package audit
func f(): Unit { throw 1 }
//               ^ d0 error: the object thrown must derive from `core.Exception`
