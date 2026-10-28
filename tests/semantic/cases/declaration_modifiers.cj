// ISSUE: 423
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: the visibility of an 'abstract' function must be 'public' or 'protected'
// CJC: audit error: the visibility of an 'open' function must be 'public' or 'protected'
// CJC: audit error: non-abstract class cannot be modified by 'sealed'
// SOURCE: src/main.cj %f
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/declaration_validation/modifiers_fixed.cj
// STEP: restored FROM broken
package audit
abstract class A {
    private func f(): Unit
//               ^ abstract_visibility error: the visibility of an 'abstract' function must be 'public' or 'protected'
}
open class B {
    open func f() {}
//            ^ open_visibility error: the visibility of an 'open' function must be 'public' or 'protected'
}
sealed class C {}
//           ^ sealed_class error: non-abstract class cannot be modified by 'sealed'
