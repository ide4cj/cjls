// ISSUE: 538
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: return type of 'f' is not identical or not a subtype of the overridden/redefined/implement function
// SOURCE: src/main.cj %f
// EXPECT: d0 s0 error: return type of 'f' is not identical or not a subtype of the overridden/redefined/implement function
// SOURCE: src/declarations.cj inputs/audit.cj
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/inherit_bad_override/fixed/src/main.cj
// STEP: restored FROM broken
package audit
open class B { public open func f(): Int64 { 1 } }; class C <: B { public override func /*@s0*/f/*@/s0*/(): String { "x" } }
