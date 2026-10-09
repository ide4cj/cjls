package loupe

import std.unittest.*
import std.unittest.testmacro.*
import loupe.fixture.*
import loupe.hir.*
import loupe.syntax.parse

/**
 * Checks where the name at the cursor of `fixture` is declared is its annotations: `//^ def` under
 * the name of each declaration found, `//^ no definition` under the name at the cursor if none is;
 * the packages of std `std` read from the SDK.
 */
func checkDefinition(fixture: String, std!: Array<String> = []): Unit {
    let parsed = Fixture.parse(fixture)
    let db = parsed.database(binaries: std.map {name => stdCjoRead(name, stdCjo(name))})
    let cursor = parsed.cursor ?? throw FixtureException("no $0 in the fixture")
    let targets = definitionAt(db, cursor.fileId, cursor.offset)
    let annotations = if (targets.isEmpty()) {
        let source = db.sourceFile(cursor.fileId).getOrThrow()
        let token = tokenAt(parse(db, source).syntaxNode(), cursor.offset) ?? throw FixtureException("no name at $0")
        [Annotation(cursor.fileId, token.textRange, "no definition")]
    } else {
        targets.map {target => Annotation(target.fileId, target.focusRange, "def")}
    }
    expectAnnotations(fixture, annotations)
}

@Test
class DefinitionTest {
    @TestCase
    func aTypeOfThePackageInAParameter() {
        checkDefinition(#"
            //- /a.cj module=m package=m
            package m
            class C {}
            //    ^ def
            //- /b.cj module=m package=m
            package m
            func f(x: $0C): Unit {}
            "#)
    }

    @TestCase
    func aTypeInEachPlaceOfASignature() {
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            interface I<T> {}
            class C {}
            //    ^ def
            class A<T> <: I<$0C> where T <: I<C> {}
            "#)
    }

    @TestCase
    func aTypeArgumentInsideAFunctionAndAnOptionType() {
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            struct S {}
            //     ^ def
            let v: ?((Int64, Array<$0S>) -> Unit) = None
            "#)
    }

    @TestCase
    func anAliasAndTheTypeItNames() {
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            class C<T> {}
            type L<T> = C<T>
            //   ^ def
            func f(x: $0L<Int64>): Unit {}
            "#)
    }

    @TestCase
    func aTypeParameterOfTheFunction() {
        // N55
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            func f<T>(x: $0T): T { x }
            //     ^ def
            "#)
    }

    @TestCase
    func aTypeParameterShadowsATypeOfThePackage() {
        // N55
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            class T {}
            func f<T>(x: T): $0T { x }
            //     ^ def
            "#)
    }

    @TestCase
    func aTypeParameterShadowsAnImportedType() {
        // N55
        checkDefinition(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class T {}
            //- /main.cj module=m package=m
            package m
            import m.a.T
            func f<T>(x: $0T): T { x }
            //     ^ def
            "#)
    }

    @TestCase
    func aMethodsTypeParameterShadowsItsClasss() {
        // N55
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            class A<T> {
                func g<T>(x: $0T): Unit {}
            //         ^ def
            }
            "#)
    }

    @TestCase
    func aClasssTypeParameterInAStaticMember() {
        // N55
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            class A<T> {
            //      ^ def
                static func s(x: $0T): Unit {}
            }
            "#)
    }

    @TestCase
    func anEnumsTypeParameterInAConstructor() {
        // N55
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            enum E<T> { | A($0T) | B }
            //     ^ def
            "#)
    }

    @TestCase
    func anExtendsTypeParameterInAMember() {
        // N55
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            class Box<T> {}
            extend<T> Box<T> {
            //     ^ def
                func g(x: $0T): Unit {}
            }
            "#)
    }

    @TestCase
    func aTypeOfAPackageImportedByItsName() {
        // N51
        checkDefinition(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class C {}
            //           ^ def
            //- /main.cj module=m package=m.b
            package m.b
            import m.a
            func f(x: a.$0C): Unit {}
            "#)
    }

    @TestCase
    func aPackageQualifierHasNoDefinition() {
        // N51
        checkDefinition(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class C {}
            //- /main.cj module=m package=m.b
            package m.b
            import m.a
            func f(x: $0a.C): Unit {}
            //          ^ no definition
            "#)
    }

    @TestCase
    func aPackageImportedUnderAnAlias() {
        // N51
        checkDefinition(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class C {}
            //           ^ def
            //- /main.cj module=m package=m.b
            package m.b
            import m.a as z
            func f(x: z.$0C): Unit {}
            "#)
    }

    @TestCase
    func theNameOfAPackageImportedUnderAnAliasQualifiesNothing() {
        // N51
        checkDefinition(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class C {}
            //- /main.cj module=m package=m.b
            package m.b
            import m.a as z
            func f(x: a.$0C): Unit {}
            //            ^ no definition
            "#)
    }

    @TestCase
    func aFullPathIsNoQualifier() {
        // N51
        checkDefinition(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class C {}
            //- /main.cj module=m package=m.b
            package m.b
            import m.a
            func f(x: m.a.$0C): Unit {}
            //              ^ no definition
            "#)
    }

    @TestCase
    func aSubPackageIsNotReachedThroughItsParent() {
        // N51
        checkDefinition(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class P {}
            //- /a/b/b.cj module=m package=m.a.b
            package m.a.b
            public class C {}
            //- /main.cj module=m package=m.c
            package m.c
            import m.a
            import m.a.b
            func f(x: a.b.$0C): Unit {}
            //              ^ no definition
            "#)
    }

    @TestCase
    func aGlobBringsNoPackageName() {
        // N51
        checkDefinition(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class C {}
            //- /main.cj module=m package=m.b
            package m.b
            import m.a.*
            func f(x: a.$0C): Unit {}
            //            ^ no definition
            "#)
    }

    @TestCase
    func anImportedTypeBringsNotItsPackage() {
        // N51
        checkDefinition(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class C {}
            //- /main.cj module=m package=m.b
            package m.b
            import m.a.C
            func f(x: a.$0C): Unit {}
            //            ^ no definition
            "#)
    }

    @TestCase
    func thePackageItselfIsNoQualifier() {
        // N51
        checkDefinition(#"
            //- /main.cj module=m package=m.a
            package m.a
            class C {}
            func f(x: a.$0C): Unit {}
            //            ^ no definition
            "#)
    }

    @TestCase
    func aQualifierIsThePackageOverATypeParameter() {
        // N52
        checkDefinition(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class C {}
            //           ^ def
            //- /main.cj module=m package=m.b
            package m.b
            import m.a
            func f<a>(x: a.$0C): Unit {}
            "#)
    }

    @TestCase
    func aQualifierIsThePackageOverADeclarationShadowingIt() {
        // N52
        checkDefinition(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class C {}
            //           ^ def
            //- /main.cj module=m package=m.b
            package m.b
            import m.a
            class a {}
            func f(x: a.$0C): Unit {}
            "#)
    }

    @TestCase
    func aQualifierIsThePackageOverAnImportedType() {
        // N52
        checkDefinition(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class C {}
            //           ^ def
            //- /n/n.cj module=n package=n
            package n
            public class a {}
            //- /main.cj module=m package=m.b deps=n
            package m.b
            import m.a
            import n.*
            func f(x: a.$0C): Unit {}
            "#)
    }

    @TestCase
    func packagesImportedByOneNameConflict() {
        // N52
        checkDefinition(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class C {}
            //- /x/a/a.cj module=m package=m.x.a
            package m.x.a
            public class C {}
            //- /main.cj module=m package=m.b
            package m.b
            import m.a
            import m.x.a
            func f(x: a.$0C): Unit {}
            //            ^ no definition
            "#)
    }

    @TestCase
    func aPackageIsNoType() {
        // N53
        checkDefinition(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class C {}
            //- /main.cj module=m package=m.b
            package m.b
            import m.a
            func f(x: $0a): Unit {}
            //          ^ no definition
            "#)
    }

    @TestCase
    func aTypeAndAPackageOfOneNameAreTheTypeAsAType() {
        // N53
        checkDefinition(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class C {}
            //- /n/n.cj module=n package=n
            package n
            public class a {}
            //           ^ def
            //- /main.cj module=m package=m.b deps=n
            package m.b
            import m.a
            import n.*
            func f(x: $0a): Unit {}
            "#)
    }

    @TestCase
    func aFunctionIsNoType() {
        // N41, N53
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            func Foo(): Unit {}
            func f(x: $0Foo): Unit {}
            //          ^^^ no definition
            "#)
    }

    @TestCase
    func aConstructorIsNoTypeAfterItsEnum() {
        // N54
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            enum E { | A | B }
            func f(x: E.$0A): Unit {}
            //            ^ no definition
            "#)
    }

    @TestCase
    func theTypeBeforeASegmentIsFound() {
        // N54
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            class A {}
            //    ^ def
            func f(x: $0A.B): Unit {}
            "#)
    }

    @TestCase
    func aTypeParameterHasNoTypesInIt() {
        // N54
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            func f<T>(x: T.$0U): Unit {}
            //               ^ no definition
            "#)
    }

    @TestCase
    func typeArgumentsOfAQualifierAreLeftAlone() {
        // N57
        checkDefinition(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class C<T> {}
            //           ^ def
            //- /main.cj module=m package=m.b
            package m.b
            import m.a
            func f(x: a<Int64>.$0C<Int64>): Unit {}
            "#)
    }

    @TestCase
    func aTypeReExportedByThePackageOfTheQualifier() {
        // N28, N51
        checkDefinition(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class C {}
            //           ^ def
            //- /b/b.cj module=m package=m.b
            package m.b
            public import m.a.C
            //- /main.cj module=m package=m.c
            package m.c
            import m.b
            func f(x: b.$0C): Unit {}
            "#)
    }

    @TestCase
    func typesOfTwoGlobsAreEachACandidate() {
        // N15
        checkDefinition(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class C {}
            //           ^ def
            //- /n/n.cj module=n package=n
            package n
            public class C {}
            //           ^ def
            //- /main.cj module=m package=m.b deps=n
            package m.b
            import m.a.*
            import n.*
            func f(x: $0C): Unit {}
            "#)
    }

    @TestCase
    func thisIsItsClass() {
        // N56
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            open class A {
            //         ^ def
                func f(): $0This { this }
            }
            "#)
    }

    @TestCase
    func aTypeOfACompiledPackageHasNoSourceToGoTo() {
        // arrange
        let parsed = Fixture.parse(#"
            //- /main.cj module=m package=m
            package m
            func f(x: $0String): Unit {}
            "#)
        let db = parsed.database(binaries: [stdCjoRead("std.core", stdCjo("std.core"))])
        let cursor = parsed.cursor.getOrThrow()
        let file = ItemFile.Source(db.sourceFile(cursor.fileId).getOrThrow())
        let f = DefId(db, file, itemTreeOf(db, file).items[0].id)

        // act
        let targets = definitionAt(db, cursor.fileId, cursor.offset)

        // assert
        let compiled = match (resolveTypePath(db, typeScopeOf(db, f).getOrThrow(), ["String"])[0]) {
            case Resolved(TypeOf(id)) => match (id.file(db)) {
                case Binary(_, _) => true
                case Source(_) => false
            }
            case _ => false
        }
        @Expect(compiled)
        @Expect(targets.isEmpty())
    }
}
