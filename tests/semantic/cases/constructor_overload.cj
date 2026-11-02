// ISSUE: 539
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: constructor 'init' has overload conflicts
// SOURCE: src/main.cj %f
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/constructor_overload/fixed.cj
// STEP: restored FROM broken
package audit
class C {
    init(x: Int64) {}
    init(y: Int64) {}
//  ^^^^ conflict error: constructor 'init' has overload conflicts
}
