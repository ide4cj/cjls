package audit
class C { public func missing(): Unit {} }; func f(c: C): Unit { c.missing() }
