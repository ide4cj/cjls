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
}
