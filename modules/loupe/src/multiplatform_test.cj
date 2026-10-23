package loupe

import std.unittest.*
import std.unittest.testmacro.*

/**
 * A multiplatform package as a fixture: its files are those of the chain of source sets the
 * build takes (`common` ⊂ `posix` ⊂ `linux`), each set a directory of its own, the package one
 * (#318).
 */
const PLAT =
    #"
            //- /plat/common/plat.cj module=plat package=plat
            @NonProduct
            features {}
            package plat

            public common func separator(): Rune

            public func segments(path: String): Array<String> {
                path.split(separator().toString())
            }

            public common class Host {
                public common init()
                public common func name(): String
                public func describe(): String { name() }
            }
            //- /plat/posix/posix.cj module=plat package=plat
            @NonProduct
            features { user.plat.posix }
            package plat

            public specific func separator(): Rune { r'/' }
            //- /plat/linux/linux.cj module=plat package=plat
            features { user.plat.posix, os.linux }
            package plat

            public specific class Host {
                public specific init() {}
                public specific func name(): String { "linux" }
            }
            "#

@Test
class MultiplatformDefinitionTest {
    @TestCase
    func aCommonClassGoesToItsSpecificAndItsCommon() {
        checkDefinition(
            #"
            //- /plat/common/plat.cj module=plat package=plat
            @NonProduct
            features {}
            package plat

            public common class Host {
            //                  ^^^^ def
                public common init()
            }
            //- /plat/linux/linux.cj module=plat package=plat
            features { user.plat.posix, os.linux }
            package plat

            public specific class Host {
            //                    ^^^^ def
                public specific init() {}
            }
            //- /app/main.cj module=app package=app deps=plat
            package app

            import plat.*

            main() { $0Host() }
            "#
        )
    }
    @TestCase
    func aMemberOfACommonClassGoesToItsSpecificAndItsCommon() {
        checkDefinition(
            #"
            //- /plat/common/plat.cj module=plat package=plat
            @NonProduct
            features {}
            package plat

            public common class Host {
                public common init()
                public common func name(): String
            //                     ^^^^ def
            }
            //- /plat/linux/linux.cj module=plat package=plat
            features { user.plat.posix, os.linux }
            package plat

            public specific class Host {
                public specific init() {}
                public specific func name(): String { "linux" }
            //                       ^^^^ def
            }
            //- /app/main.cj module=app package=app deps=plat
            package app

            import plat.*

            main() { Host().$0name() }
            "#
        )
    }

    @TestCase
    func aMemberOnlyTheCommonClassDeclaresIsFound() {
        checkDefinition(
            #"
            //- /plat/common/plat.cj module=plat package=plat
            @NonProduct
            features {}
            package plat

            public common class Host {
                public common init()
                public func describe(): String { "host" }
            //              ^^^^^^^^ def
            }
            //- /plat/linux/linux.cj module=plat package=plat
            features { user.plat.posix, os.linux }
            package plat

            public specific class Host {
                public specific init() {}
            }
            //- /app/main.cj module=app package=app deps=plat
            package app

            import plat.*

            main() { Host().$0describe() }
            "#
        )
    }

    @TestCase
    func aCommonFunctionGoesToItsSpecificAndItsCommon() {
        checkDefinition(
            #"
            //- /plat/common/plat.cj module=plat package=plat
            @NonProduct
            features {}
            package plat

            public common func separator(): Rune
            //                 ^^^^^^^^^ def
            //- /plat/posix/posix.cj module=plat package=plat
            @NonProduct
            features { user.plat.posix }
            package plat

            public specific func separator(): Rune { r'/' }
            //                   ^^^^^^^^^ def
            //- /app/main.cj module=app package=app deps=plat
            package app

            import plat.*

            main() { $0separator() }
            "#
        )
    }
}

@Test
class MultiplatformDiagnosticsTest {
    @TestCase
    func aCompletedPackageHasNoDiagnostics() {
        checkDiagnostics(
            PLAT +
                #"
            //- /app/main.cj module=app package=app deps=plat
            package app

            import plat.*

            main(): Int64 {
                let host: String = Host().name()
                let described: String = Host().describe()
                let sep: Rune = separator()
                0
            }
            "#
        )
    }

    @TestCase
    func aFileOfASourceSetTheBuildLeavesOutIsAllInactiveAndNotChecked() {
        checkDiagnostics(
            #"
            //- /plat/common/plat.cj module=plat package=plat
            @NonProduct
            features {}
            package plat

            public common func separator(): Rune
            //- /plat/posix/posix.cj module=plat package=plat
            @NonProduct
            features { user.plat.posix }
            package plat

            public specific func separator(): Rune { r'/' }
            //- /plat/windows/windows.cj module=plat package=plat inactive=windows
              public specific func separator(): Rune { undefined }
            //^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ hint: code is inactive: source set `windows` is left out
            "#
        )
    }

    @TestCase
    func aCommonOfNoBodyAndNoSpecificIsAnError() {
        // as cjc 1.3.0-alpha.20261002 reports them, at the declaration's name
        checkDiagnostics(
            #"
            //- /plat/common/plat.cj module=plat package=plat
            @NonProduct
            features {}
            package plat

            public common func missing(): Int64
            //                 ^^^^^^^ error: 'common' function 'missing' can not find 'specific' match
            public common func withDefault(): Int64 { 1 }

            public common class Lonely {
            //                  ^^^^^^ error: 'common' class 'Lonely' can not find 'specific' match
                public common init()
            //                ^^^^ error: 'common' constructor can not find 'specific' match
            }

            public common class WithBodies {
                public common init() {}
                public common func m(): Int64 { 2 }
            }

            public common struct S {
            //                   ^ error: 'common' struct 'S' can not find 'specific' match
                public common init()
            //                ^^^^ error: 'common' constructor can not find 'specific' match
            }

            public common enum E {
            //                 ^ error: 'common' enum 'E' can not find 'specific' match
                | A
            //    ^ error: 'common' enum 'E' constructor 'A' can not find 'specific' match
            }

            public common interface I {
            //                      ^ error: 'common' interface 'I' can not find 'specific' match
                common func g(): Int64
            }

            public common class WithProp {
            //                  ^^^^^^^^ error: 'common' class 'WithProp' can not find 'specific' match
                public common init() {}
                public common prop p: Int64
            //                     ^ error: 'common' property 'p' can not find 'specific' match
            }

            public common let v: Int64
            //                ^ error: 'common' variable 'v' can not find 'specific' match
            "#
        )
    }

    @TestCase
    func aMemberTheSpecificTypeLacksIsAnError() {
        checkDiagnostics(
            #"
            //- /plat/common/plat.cj module=plat package=plat
            @NonProduct
            features {}
            package plat

            public common class Host {
                public common init()
                public common func name(): String
                public common func os(): String
            //                     ^^ error: 'common' function 'os' can not find 'specific' match
            }
            //- /plat/linux/linux.cj module=plat package=plat
            features { user.plat.posix, os.linux }
            package plat

            public specific class Host {
                public specific init() {}
                public specific func name(): String { "linux" }
            }
            "#
        )
    }

    @TestCase
    func aTypeOfACommonTypeIsItsSpecific() {
        checkDiagnostics(
            #"
            //- /plat/common/plat.cj module=plat package=plat
            @NonProduct
            features {}
            package plat

            public common class Host {
                public common init()
                public common func name(): String
                public func me(): Host { this }
                public func shout(): String { name() + "!" }
            }

            public func make(): Host { Host() }
            //- /plat/linux/linux.cj module=plat package=plat
            features { user.plat.posix, os.linux }
            package plat

            public specific class Host {
                public specific init() {}
                public specific func name(): String { "linux" }
            }
            "#
        )
    }
}
