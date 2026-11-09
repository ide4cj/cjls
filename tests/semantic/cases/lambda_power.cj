// ISSUE: 248
// PACKAGE: audit .
// STEP: broken
// CJC: audit error: mismatched types
// SOURCE: src/main.cj %f
// STEP: fixed
// CJC: audit clean
// SOURCE: src/main.cj inputs/lambda_power/fixed.cj
// STEP: restored FROM broken
package audit
func test(): Unit {
    let power = {x => x ** 2}
    let wrong: (Int64) -> Int64 = power
//                                ^^^^^ wrong error: mismatched types: expected '(Int64) -> Int64', found '(Float64) -> Float64'
}
