package audit

func identity<T>(): (T) -> T { {value => value} }

func check(): Unit {
    let called = identity()(1)
    let wrong: String = called
//                      ^^^^^^ inferred_result error: mismatched types: expected 'String', found 'Int64'
}
