package loupe

import std.unittest.*
import std.unittest.testmacro.*

/**
 * A file of no package of the project, as the server sets it: a module of its own rooted at the
 * file, compiled alone as `cjc file.cj` compiles it (#293).
 */
@Test
class FileAloneTest {
    @TestCase
    func itsOwnNamesAndAnImportedPackageOfStdAreTypedAndNoneOfTheProjects() {
        checkDiagnostics(
            #"
            //- /src/app.cj
            public func rootFn(): Int64 { 1 }
            //- /scripts/x.cj root=/scripts/x.cj
            import std.collection.ArrayList

            func own(): Int64 { 2 }

            main() {
                let local = own()
                let list = ArrayList<Int64>()
                list.add(local)
                println(local)
                // a type known is told from the one written: unknown, nothing is reported
                let a: String = local
            //                  ^^^^^ error: mismatched types: expected 'String', found 'Int64'
                let b: String = list.size
            //                  ^^^^^^^^^ error: mismatched types: expected 'String', found 'Int64'
                let c: String = rootFn()
            }
            "#,
            binaries: ["std.core", "std.collection"]
        )
    }

    @TestCase
    func aFunctionOfTheProjectGoesNowhere() {
        checkDefinition(
            #"
            //- /src/app.cj
            public func rootFn(): Int64 { 1 }
            //- /scripts/x.cj root=/scripts/x.cj
            main() {
                let local = root$0Fn()
            //              ^^^^^^^^ no definition
            }
            "#
        )
    }

    @TestCase
    func aFunctionOfItsOwnIsTheOneItGoesToWhereTheProjectHasOneOfItsName() {
        checkDefinition(
            #"
            //- /src/app.cj
            public func own(): Int64 { 1 }
            //- /scripts/x.cj root=/scripts/x.cj
            func own(): Int64 { 2 }
            //   ^^^ def
            main() {
                let local = own$0()
            }
            "#
        )
    }

    @TestCase
    func aFileAloneOfAModulesNameLeavesThatModuleItsDeps() {
        checkDiagnostics(
            #"
            //- /lib/lib.cj module=lib package=lib
            package lib
            public func helper(): Int64 { 1 }
            //- /app/app.cj module=app package=app deps=lib
            package app
            import lib.helper
            // resolved: its type is told from the one written
            func f(): Unit {
                let s: String = helper()
            //                  ^^^^^^^^ error: mismatched types: expected 'String', found 'Int64'
            }
            //- /x.cj module=app package=app.x root=/x.cj
            package app.x
            func g(): Int64 { 1 }
            "#,
            binaries: ["std.core"]
        )
    }
}
