// ISSUE: 423
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: cannot use custom annotation
// CJC: audit error: cannot use custom annotation
// CJC: audit error: cannot use custom annotation
// CJC: audit error: cannot use custom annotation
// CJC: audit error: cannot use custom annotation
// CJC: audit error: cannot use custom annotation
// CJC: audit error: cannot use custom annotation
// CJC: audit error: cannot use custom annotation
// SOURCE: src/main.cj %f
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/declaration_validation/custom_arguments_fixed.cj
// STEP: restored FROM broken
package audit
@Annotation public class A {
    const init(x: Int64) {}
    const init(x: String) {}
}
@Annotation public class B { const init(x!: Int64 = 1) {} }
@A[1] class C {}
@A["global"] let global = 1
func f() {
    let value = 1
    @A[value] func g() {}
//                 ^ local_function error: cannot use custom annotation
    @A["local"] let variable = 1
//                  ^^^^^^^^ local_variable error: cannot use custom annotation
    @A[1] let (a, b) = (1, 2)
//            ^^^^^^ tuple error: cannot use custom annotation
    @B[x: 1] let named = 1
//               ^^^^^ named error: cannot use custom annotation
    @A[1] let _ = 1
//            ^ wildcard error: cannot use custom annotation
    @A[1] let (_, _) = (1, 2)
//            ^^^^^^ wildcard_tuple error: cannot use custom annotation
    @A[1] @A[1] let multiple = 1
//                  ^^^^^^^^ multiple error: cannot use custom annotation
    @B let defaulted = 1
//         ^^^^^^^^^ defaulted error: cannot use custom annotation
}
