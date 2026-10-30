// ISSUE: 423
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: cannot use custom annotation
// CJC: audit error: cannot use custom annotation
// SOURCE: src/main.cj %f
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/declaration_validation/custom_fixed.cj
// STEP: restored FROM broken
package audit
@Annotation
public class A { const init() {} }
@A class C {}
func f() {
    @A func g() {}
//          ^ local_function error: cannot use custom annotation
    @A let x = 1
//         ^ local_variable error: cannot use custom annotation
}
