package audit
func test(): Unit {
    let floating = {x => x ** 2}
    let integer = {x => x ** 2u64}
    let decimal = {x => x ** 2.0}
    let exponent = {x => 2 ** x}
    let floatExponent = {x => 2.0 ** x}
    let a: (Float64) -> Float64 = floating
    let b: (Int64) -> Int64 = integer
    let c: (Float64) -> Float64 = decimal
    let d: (UInt64) -> Int64 = exponent
    let e: (Int64) -> Float64 = floatExponent
}
