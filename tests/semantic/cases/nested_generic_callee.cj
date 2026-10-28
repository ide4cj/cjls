// ISSUE: 246
// PACKAGE: audit .
// STEP: clean
// CJC: audit clean
// SOURCE: src/main.cj %f
package audit

func first<T>(label: String): (Iterable<T>) -> T where T <: ToString {
    {values => values.iterator().next().getOrThrow()}
}

func check(): Unit {
    let piped = [1, 2] |> first("x")
    let called = first("x")([1, 2])
    let alone = first("x")
    let pipedInt: Int64 = piped
    let calledInt: Int64 = called
    let standalone: (Iterable<ToString>) -> ToString = alone
}
