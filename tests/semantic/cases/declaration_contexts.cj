// ISSUE: 423
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: finalizer is forbidden in class 'C' that is open
// CJC: audit error: finalizer is forbidden in class 'D' that is abstract
// CJC: audit error: 'mut' modifier is illegal in extend body of 'C'
// SOURCE: src/main.cj %f
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/declaration_validation/contexts_fixed.cj
// STEP: restored FROM broken
package audit
open class C { ~init() {} }
//             ^ finalizer_open error: finalizer is forbidden in class 'C' that is open
abstract class D { ~init() {} }
//                 ^ finalizer_abstract error: finalizer is forbidden in class 'D' that is abstract
extend C { public mut func f() {} }
//                ^^^ mut_class error: 'mut' modifier is illegal in extend body of 'C'
