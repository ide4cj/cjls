// ISSUE: 246
// PACKAGE: audit .
// STEP: clean
// CJC: audit clean
// SOURCE: src/main.cj %f
package audit

func identity<T>(): (T) -> T { {value => value} }
func curried<T>(): (T) -> (T) -> T { {left => {right => right}} }

func check(): Unit {
    let piped = 1 |> identity()
    let called = identity()("value")
    let chained = identity()(identity()(2))
    let curriedValue = curried()(1)(2)
    let pipedInt: Int64 = piped
    let calledString: String = called
    let chainedInt: Int64 = chained
    let curriedInt: Int64 = curriedValue
}
