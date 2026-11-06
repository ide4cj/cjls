// ISSUE: 248
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: mismatched types
// SOURCE: src/main.cj %f
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/lambda_member/fixed.cj
// STEP: restored FROM broken
package audit
class Receiver {
    public let lambdaUnique: Int64 = 1
}
func test(): Unit {
    let inferred = {x => x.lambdaUnique}
    let wrong: (Int64) -> Int64 = inferred
//                                ^^^^^^^^ wrong error: mismatched types: expected '(Int64) -> Int64', found '(Receiver) -> Int64'
}
