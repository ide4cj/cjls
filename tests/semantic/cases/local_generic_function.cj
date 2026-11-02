// ISSUE: 241
// PACKAGE: audit .
// STEP: clean
// CJC: audit clean
// SOURCE: src/main.cj %f
// STEP: wrong_consumer
// CJC: audit error: mismatched types
// SOURCE: src/main.cj inputs/local_generic_function/wrong_consumer.cj
// STEP: restored FROM clean
package audit

interface I {}
func check(): Unit {
    func id<T>(x: T): T { x }
    func make<T>(): ?T where T <: I { None }
    let byte = id(1u8)
    let text = id<String>("s")
    let fallback = make()
    let checkedByte: UInt8 = byte
    let checkedText: String = text
    let checkedFallback: ?I = fallback
}
