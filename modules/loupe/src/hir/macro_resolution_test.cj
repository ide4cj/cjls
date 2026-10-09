package loupe.hir

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import loupe.fixture.*

/**
 * What each macro called on the declaration `name` of the first file of `fixture` names, with std.deriving's `.cjo`
 * among its packages: `cjo Derive` for a macro of a compiled package, `source M` for one of the workspace.
 */
func macrosNamed(fixture: String, name: String): Array<String> {
    let parsed = Fixture.parse(fixture)
    let db = parsed.database(binaries: [stdCjoRead("std.deriving", stdCjo("std.deriving"))])
    let file = ItemFile.Source(db.sourceFile(parsed.files[0].fileId).getOrThrow())
    func find(items: Array<Item>): ?Item {
        for (item in items) {
            if (item.names.contains(name)) {
                return item
            }
            if (let Some(member) <- find(item.members)) {
                return member
            }
        }
        None
    }
    let item = find(itemTreeOf(db, file).items) ?? throw FixtureException("no ${name} in the fixture")
    macrosOf(db, DefId(db, file, item.id)).map {
        resolution => match (resolution) {
            case Found(ids) => String.join(ids.map {
                id =>
                let origin = match (id.file(db)) {
                    case Binary(_, _) => "cjo"
                    case Source(_) => "source"
                    case Expansion(_) => "expansion"
                }
                "${origin} ${nameOfDef(db, id)}"
            }, delimiter: ", ")
            case other => other.toString()
        }
    }
}

@Test
class MacroResolutionTest {
    @TestCase
    func stdsDeriveThroughAGlob() {
        // act
        let macros = macrosNamed(#"
            //- /main.cj module=m package=m
            package m
            import std.deriving.*
            @Derive[Equatable]
            class C {}
            "#, "C")

        // assert
        @Expect(macros, ["cjo Derive"])
    }

    @TestCase
    func aMacroOfAPackageImportedByItsName() {
        // act
        let macros = macrosNamed(#"
            //- /main.cj module=m package=m
            package m
            import std.deriving
            @deriving.Derive[Equatable]
            class C {}
            "#, "C")

        // assert
        @Expect(macros, ["cjo Derive"])
    }

    @TestCase
    func aPathWithSpacesAndBackquotesIsItsNames() {
        // act
        let macros = macrosNamed(#"
            //- /main.cj module=m package=m
            package m
            import std.deriving
            import std.deriving.*
            @ deriving . `Derive`[Equatable]
            @`Derive`[Hashable]
            class C {}
            "#, "C")

        // assert
        @Expect(macros, ["cjo Derive", "cjo Derive"])
    }

    @TestCase
    func aMacroUnderAnAlias() {
        // act
        let macros = macrosNamed(#"
            //- /main.cj module=m package=m
            package m
            import std.deriving.Derive as D
            @D[Equatable]
            class C {}
            "#, "C")

        // assert
        @Expect(macros, ["cjo Derive"])
    }

    @TestCase
    func aMacroNotImportedIsNotFound() {
        // act
        let macros = macrosNamed(#"
            //- /main.cj module=m package=m
            package m
            @Derive[Equatable]
            class C {}
            "#, "C")

        // assert
        @Expect(macros, ["not found"])
    }

    @TestCase
    func aFunctionOfTheMacrosNameHidesNothing() {
        // act
        let macros = macrosNamed(#"
            //- /main.cj module=m package=m
            package m
            import std.deriving.*
            func Derive(): Unit {}
            @Derive[Equatable]
            class C {}
            "#, "C")

        // assert
        @Expect(macros, ["cjo Derive"])
    }

    @TestCase
    func aUsersDeriveIsNotStds() {
        // act
        let macros = macrosNamed(#"
            //- /main.cj module=m package=m
            package m
            import m.ms.*
            @Derive[Equatable]
            class C {}
            //- /ms/ms.cj module=m package=m.ms
            macro package m.ms
            import std.ast.*
            public macro Derive(attr: Tokens, input: Tokens): Tokens { input }
            public macro M(input: Tokens): Tokens { input }
            "#, "C")

        // assert
        @Expect(macros, ["source Derive"])
    }

    @TestCase
    func theMacrosOfADeclarationOutermostFirst() {
        // act
        let macros = macrosNamed(#"
            //- /main.cj module=m package=m
            package m
            import std.deriving.*
            import m.ms.M
            @M
            @Derive[Equatable]
            class C {}
            //- /ms/ms.cj module=m package=m.ms
            macro package m.ms
            import std.ast.*
            public macro Derive(attr: Tokens, input: Tokens): Tokens { input }
            public macro M(input: Tokens): Tokens { input }
            "#, "C")

        // assert
        @Expect(macros, ["source M", "cjo Derive"])
    }

    @TestCase
    func aMacroOnAMember() {
        // act
        let macros = macrosNamed(#"
            //- /main.cj module=m package=m
            package m
            import m.ms.M
            class C {
                @M
                func f(): Unit {}
            }
            //- /ms/ms.cj module=m package=m.ms
            macro package m.ms
            import std.ast.*
            public macro Derive(attr: Tokens, input: Tokens): Tokens { input }
            public macro M(input: Tokens): Tokens { input }
            "#, "f")

        // assert
        @Expect(macros, ["source M"])
    }
}
