package audit

func first<T>(label: String): (Iterable<T>) -> T where T <: ToString {
    {values => values.iterator().next().getOrThrow()}
}

func check(): Unit {
    let called = first("x")([1, 2])
    let wrong: String = called
//                      ^^^^^^ inferred_result error: mismatched types: expected 'String', found 'Int64'
}
