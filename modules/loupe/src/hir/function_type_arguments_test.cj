package loupe.hir

import std.unittest.*
import std.unittest.testmacro.*

@Test
class FunctionTypeArgumentsTest {
    @TestCase
    func explicitTypeArgumentsSelectTheGenericArityOfFreeAndMemberFunctions() {
        // Compiler-checked on Linux, cjc 1.3.0-alpha.20261014001050 (#564).
        checkInference(
            #"
            package m
            func read(value: Int64): ?Int64 { None }
            //        ^^^^^ Int64
            func read<T>(value: T): ?T { None }
            //           ^^^^^ T
            func read<T, U>(value: (T, U)): ?(T, U) { None }
            //              ^^^^^ (T, U)
            class Reader {
                static func read(value: Int64): ?Int64 { None }
            //                   ^^^^^ Int64
                static func read<T>(value: T): ?T { None }
            //                      ^^^^^ T
                static func read<T, U>(value: (T, U)): ?(T, U) { None }
            //                         ^^^^^ (T, U)
            }
            func test(): Unit {
                let a = read<Bool>(true)
            //      ^ Option<Bool>
                let b = Reader.read<Bool>(true)
            //      ^ Option<Bool>
                let c = read<Bool, Int64>((true, 1))
            //      ^ Option<(Bool, Int64)>
                let d = Reader.read<Bool, Int64>((true, 1))
            //      ^ Option<(Bool, Int64)>
            }
            "#
        )
    }
}
