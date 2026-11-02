package audit

func check(): Unit {
    func id<T>(x: T): T { x }
    let byte = id(1u8)
    let wrong: String = byte
//                      ^^^^ inferred_result error: mismatched types: expected 'String', found 'UInt8'
}
