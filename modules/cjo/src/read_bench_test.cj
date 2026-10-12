package cjo

import std.unittest.*
import std.unittest.testmacro.*

let BENCH_CORE: Array<Byte> = stdCjo("std.core")

/**
 * Reading every declaration of std.core's `.cjo` through the views: a table, a scalar, a string, a struct, a
 * vector each, what loupe reads of a binary package.
 */
@Test
class CjoReadBench {
    @Bench
    func readEveryDeclOfStdCore(): Int64 {
        let pkg = openCjo(BENCH_CORE)
        var sum = 0
        for (d in pkg.allDecls) {
            sum += Int64(d.kind.value) + Int64(d.`type`) + (d.identifier?.size ?? 0)
            sum += Int64(d.begin?.line ?? 0) + d.annotations.size + d.dependencies.size
            if (d.isTopLevel) {
                sum++
            }
        }
        sum
    }
}
