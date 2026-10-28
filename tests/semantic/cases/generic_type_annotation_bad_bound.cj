// ISSUE: 540
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: generics type arguments do not match the constraint of 'Class-Box<Generics-T>'
// SOURCE: src/main.cj %f
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/generic_type_annotation_bad_bound/fixed/src/main.cj
// STEP: restored FROM broken
package audit
class Box<T> where T <: ToString {}; func f(x: Box<() -> Unit>): Unit {}
//                                                 ^ d0 error: generics type arguments do not match the constraint of 'Class-Box<Generics-T>'
