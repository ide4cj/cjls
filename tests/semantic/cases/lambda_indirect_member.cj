// ISSUE: 248
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: mismatched types
// CJC: audit error: mismatched types
// SOURCE: src/main.cj %f
// KNOWN-MISSING: alias_mismatch issue=248
// KNOWN-MISSING: call_mismatch issue=248
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/lambda_indirect_member/fixed.cj
// STEP: restored FROM broken
package audit
class Holder {
    public let lambdaIndirect: Int64 = 1
}
func identity<T>(value: T): T { value }
func test(): Unit {
    let viaAlias = {x => let alias = x; alias.lambdaIndirect}
    let viaCall = {x => identity(x).lambdaIndirect}
    let aliasWrong: (Int64) -> Int64 = viaAlias
//                                     ^^^^^^^^ alias_mismatch error: mismatched types: expected '(Int64) -> Int64', found '(Holder) -> Int64'
    let callWrong: (Int64) -> Int64 = viaCall
//                                    ^^^^^^^ call_mismatch error: mismatched types: expected '(Int64) -> Int64', found '(Holder) -> Int64'
}
