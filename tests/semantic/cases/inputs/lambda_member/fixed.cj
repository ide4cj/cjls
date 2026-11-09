package audit
class Receiver {
    public let lambdaUnique: Int64 = 1
}
class Box<T> {
    public Box(public let lambdaGeneric: T) {}
    public func lambdaPut(value: T): T { value }
}
func test(): Unit {
    let inferred = {x => x.lambdaUnique}
    let field = {x => x.lambdaGeneric + 1}
    let argument = {x => x.lambdaPut(1i8)}
    let a: (Receiver) -> Int64 = inferred
    let b: (Box<Int64>) -> Int64 = field
    let c: (Box<Int8>) -> Int8 = argument
}
