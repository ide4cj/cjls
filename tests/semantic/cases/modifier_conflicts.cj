// ISSUE: 423
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: 'open' and 'private' modifiers conflict on function declaration
// CJC: audit error: 'internal' and 'open' modifiers conflict on property declaration
// SOURCE: src/main.cj %f
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/declaration_validation/conflicts_fixed.cj
// STEP: restored FROM broken
package audit
open class C {
    private open func f() {}
//          ^^^^ open_private error: 'open' and 'private' modifiers conflict on function declaration
    open internal prop p: Int64 { get() { 1 } }
//       ^^^^^^^^ open_internal error: 'internal' and 'open' modifiers conflict on property declaration
}
