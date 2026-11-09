package audit
class Holder {
    public let lambdaIndirect: Int64 = 1
}
func identity<T>(value: T): T { value }
func test(): Unit {
    let viaAlias = {x => let alias = x; alias.lambdaIndirect}
    let viaCall = {x => identity(x).lambdaIndirect}
    let aliasWrong: (Holder) -> Int64 = viaAlias
    let callWrong: (Holder) -> Int64 = viaCall
}
