package loupe

import std.unittest.*
import std.unittest.testmacro.*

@Test
class PointerConstructorTest {
    @TestCase
    func nullPointersCanBeReturnedAndPassedToForeignCalls() {
        checkDiagnostics(
            #"
            foreign func call(kwargs: CPointer<Unit>): Unit
            type Pointer = CPointer<Unit>
            func make<T>(): CPointer<T> where T <: CType { CPointer<T>() }
            func inferred(): CPointer<Unit> { CPointer() }
            func test(): Unit {
                let pointer = CPointer<Unit>()
                let alias = Pointer()
                let contextual: CPointer<Unit> = CPointer()
                let isNull: Bool = pointer.isNull()
                unsafe { call(CPointer<Unit>()) }
            }
            "#,
            binaries: ["std.core"]
        )
    }

    @TestCase
    func userTypesNamedCPointerKeepTheirOwnConstructors() {
        checkDiagnostics(
            #"
            struct CPointer<T> {
                init(value: T) {}
            }
            func test(): Unit {
                let pointer = CPointer<Int64>(1)
            }
            "#
        )
    }
}
