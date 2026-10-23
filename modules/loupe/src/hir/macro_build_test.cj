package loupe.hir

import std.unittest.*
import std.unittest.testmacro.*
import loupe.db.*
import loupe.fixture.*

/**
 * What cjls builds for the macro server (#176).
 */
@Test
class MacroBuildPlanTest {
    @TestCase
    func aMacroPackageIsBuiltAfterThePackagesItImportsDirectlyOrNot() {
        // arrange
        let fixture =
            Fixture
                .parse(
                    #"
            //- /base/base.cj module=m package=m.base
            package m.base
            public func one(): Int64 { 1 }
            //- /util/util.cj module=m package=m.util
            package m.util
            import m.base.one
            public func two(): Int64 { one() + one() }
            //- /ms/ms.cj module=m package=m.ms
            macro package m.ms
            import std.ast.*
            import m.util.*
            public macro A(input: Tokens): Tokens { input }
            //- /user/user.cj module=m package=m.user
            package m.user
            import m.ms.*
            @A class C {}
            "#
                )
        let db = fixture.database()

        // act
        let plan = macroBuildPlan(db)

        // assert
        @Expect(plan.map {unit => "${unit.pkg.name(db)}${if (unit.isMacro) {"!"} else {""}}"},
            ["m.base", "m.util", "m.ms!"])
        @Expect(plan[2].deps.map {pkg => pkg.name(db)}, ["m.base", "m.util"])
        @Expect(plan[2].module, "m")
    }

    @TestCase
    func aWorkspaceWithoutMacroPackagesBuildsNothing() {
        // arrange
        let fixture =
            Fixture
                .parse(
                    #"
            //- /main.cj module=m package=m
            package m
            func f() {}
            "#
                )

        // act
        let plan = macroBuildPlan(fixture.database())

        // assert
        @Expect(plan.size, 0)
    }
}
