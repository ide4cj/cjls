// ISSUE: 540
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: type argument's number does not match type parameter's number
// SOURCE: src/main.cj %f
// KNOWN-MISSING: d0 issue=540
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/generic_annotation_wrong_arity/fixed/src/main.cj
// STEP: restored FROM broken
package audit
class Box<T> {}; func f(x: Box<Int64, String>): Unit {}
//                         ^^^^^^^^^^^^^^^^^^ d0 error: type argument's number does not match type parameter's number
