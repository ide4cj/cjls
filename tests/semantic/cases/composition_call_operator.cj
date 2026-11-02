// ISSUE: 247
// PACKAGE: audit .
// STEP: control
// CJC: audit clean
// SOURCE: src/main.cj %f
package audit
class K {
    operator func ()(x: Int64): Bool { true }
    operator func ()(x: String): String { x }
}
class L<T> {
    L(let value: T) {}
    operator func ()(x: Int64): T { value }
}
class Holder {
    Holder(public let k: K) {}
}
func s(x: String): Bool { true }
func test(k: K, l: L<String>, h: Holder): Unit {
    let left: (Int64) -> Bool = l ~> s
    let both: (Int64) -> String = l ~> k
    let overloadedLeft: (String) -> Bool = k ~> s
    let overloadedBoth: (String) -> String = k ~> k
    let field: (Int64) -> String = l ~> h.k
    let constructed: (Int64) -> String = L<String>("") ~> K()
    let grouped: (Int64) -> String = (l) ~> (k)
    let chained: (Int64) -> Bool = l ~> k ~> s
    let applied: String = (l ~> k)(1)
    let original: K = k
}
