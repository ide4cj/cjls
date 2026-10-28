// ISSUE: 542
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: the number '-129' exceeds the value range of type 'Int8'
// SOURCE: src/main.cj %f
// EXPECT: d0 s0 error: the number '-129' exceeds the value range of type 'Int8'
// KNOWN-MISSING: d0 issue=542
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/integer_underflow/fixed/src/main.cj
// STEP: restored FROM broken
package audit
func f(): Int8 { /*@s0*/-129/*@/s0*/ }
