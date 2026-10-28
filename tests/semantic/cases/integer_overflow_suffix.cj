// ISSUE: 542
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: the number '128i8' exceeds the value range of type 'Int8'
// SOURCE: src/main.cj %f
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/integer_overflow_suffix/fixed/src/main.cj
// STEP: restored FROM broken
package audit
func f(): Unit { let n = 128i8 }
//                       ^^^^^ d0 error: the number '128i8' exceeds the value range of type 'Int8'
