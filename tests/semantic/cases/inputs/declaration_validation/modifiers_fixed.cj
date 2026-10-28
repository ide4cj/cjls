package audit
abstract class A {
    public func f(): Unit
}
open class B {
    public open func f() {}
}
sealed abstract class C {}
