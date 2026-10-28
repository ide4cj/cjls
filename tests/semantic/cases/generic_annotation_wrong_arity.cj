// ISSUE: 540
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: type argument's number does not match type parameter's number
// SOURCE: src/main.cj %f
// EXPECT: d0 s0 error: type argument's number does not match type parameter's number
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/generic_annotation_wrong_arity/fixed/src/main.cj
// STEP: restored FROM broken
package audit
class Box<T> {}; func f(x: /*@s0*/Box<Int64, String>/*@/s0*/): Unit {}
