package loupe

import std.unittest.*
import std.unittest.testmacro.*

@Test
class GenericBoundsDiagnosticsTest {
    @TestCase
    func anInterfacesWhereAllowsOperatorsAndSubtypeConversions() {
        checkDiagnostics(#"
            package m
            interface Step<T> where T <: Comparable<T> {}
            interface R<T> where T <: Step<T> {}
            func f<T>(a: T, b: T): Bool where T <: R<T> { a > b }
            func g<T>(a: T): Comparable<T> where T <: R<T> { a }
            "#, binaries: ["std.core"])
    }

    @TestCase
    func incompleteBoundsDoNotProduceOperatorOrConversionDiagnostics() {
        checkDiagnostics(#"
            package m
            interface Box<X> {}
            interface R<A, B> where A <: R<A, Box<B>> {}
            func make<T, U>(): T where T <: R<T, U> { throw Exception() }
            func f<T, U>(x: T): Unit where T <: R<T, U> {
                let sum = x + x
                let member = x.missing
                let call = x.missing()
                let fromType = T.missing()
                let made = make()
                let value: Int64 = x
                let nested: (Int64, Int64) = (x, x)
            }
            "#, binaries: ["std.core"])
    }
}
