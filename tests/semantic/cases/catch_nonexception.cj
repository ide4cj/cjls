// ISSUE: 543
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: the exception catch type must be class and extends from core.Exception or core.Error
// SOURCE: src/main.cj %f
// EXPECT: d0 s0 error: the exception catch type must be class and extends from core.Exception or core.Error
// KNOWN-MISSING: d0 issue=543
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/catch_nonexception/fixed/src/main.cj
// STEP: restored FROM broken
package audit
func f(): Unit { try { println(1) } catch (e: /*@s0*/I/*@/s0*/nt64) {} }
