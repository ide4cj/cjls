package loupe.hir

import std.unittest.*
import std.unittest.testmacro.*

@Test
class PrivateVisibilityTest {
    @TestCase
    func packageVisibilityNeverGrantsAccessToPrivateDeclarations(): Unit {
        // arrange
        let relations: Array<PackageRelation> = [SamePackage, Child, SameModule, Unrelated]
        let own = PackageRelation.SamePackage
        let nonPrivate = [Visibility.Internal, Visibility.Protected, Visibility.Public]

        // act
        let privateAccess = relations.map { relation => Visibility.Private.isSeen(by: relation) }
        let packageAccess = nonPrivate.map { visibility => visibility.isSeen(by: own) }

        // assert
        @Expect(privateAccess, [false, false, false, false])
        @Expect(packageAccess, [true, true, true])
    }

    @TestCase
    func aPrivateEnumsConstructorIsSeenInItsOwnFile(): Unit {
        checkLookUp(
            #"
            private enum Secret { | Hidden }
            //                      ^^^^^^ def
            func useHere(): Unit { let value = $0Hidden }
            "#
        )
    }

    @TestCase
    func theFileScopeDoesNotResolveAnotherFilesPrivateFunction(): Unit {
        checkScope(
            #"
            //- /a.cj
            private func hidden(): Int64 { 1 }
            //- /b.cj
            func useOther() { $0hidden }
            //                  ^^^^^^ not found
            "#
        )
    }

    @TestCase
    func aPrivateEnumsBareConstructorRemainsVisibleInAnotherFileOfItsPackage(): Unit {
        checkScope(
            #"
            //- /a.cj
            private enum Secret { | Hidden }
            //                      ^^^^^^ ctor
            //- /b.cj
            func useOther(): Unit { let value = $0Hidden }
            "#
        )
    }

    @TestCase
    func aPrivateEnumAndItsConstructorAreAbsentFromAnotherPackagesExports(): Unit {
        checkImport(
            #"
            //- /a.cj module=m package=m.api
            package m.api
            private enum Secret { | Hidden }
            public class Shown {}
            //           ^^^^^ def
            //- /b.cj module=m package=m
            package m
            import m.api.$0*
            "#
        )
        checkScope(
            #"
            //- /a.cj module=m package=m.api
            package m.api
            private enum Secret { | Hidden }
            //- /b.cj module=m package=m
            package m
            import m.api.*
            func useOther() { $0Hidden }
            //                  ^^^^^^ not found
            "#
        )
    }
}
