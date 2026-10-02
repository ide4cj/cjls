package syntax_codegen

import std.unittest.*
import std.unittest.testmacro.*

let DECLS = """
    D = F | V | X
    F = Mods? 'if' N
    V = Mods? N
    X = Mods?
    N = 'Int'
    Mods = 'else'*
    """

func implementorsOf(method: InterfaceMethod): Array<String> {
    interfacesOf(modelOf(DECLS), [InterfaceSpec("HasIt", "", method)])[0].implementors
}

@Test
class InterfacesTest {
    @TestCase
    func aNodeImplementsAnInterfaceWhenItHasItsAccessorAndAnEnumWhenAllItsVariantsDo() {
        // act & assert
        @Expect(implementorsOf(Accessor("n", "N", false)), ["F", "V"])
        @Expect(implementorsOf(Accessor("mods", "Mods", false)), ["D", "F", "V", "X"])
    }

    @TestCase
    func anAccessorReturningOneIsNotOneReturningSeveral() {
        // act & assert
        @AssertThrows[GrammarException](implementorsOf(Accessor("n", "N", true)))
    }

    @TestCase
    func anInterfaceWithABodyIsImplementedByTheViewsItNamesAndTheirVariants() {
        // act & assert
        @Expect(implementorsOf(Provided("", "func it(): Unit", "()", ["D"])), ["D", "F", "V", "X"])
        @Expect(implementorsOf(Provided("", "func it(): Unit", "()", ["N"])), ["N"])
    }

    @TestCase
    func anInterfaceNothingImplementsOrNamingWhatHasNoRuleIsRefused() {
        // act & assert
        @AssertThrows[GrammarException](implementorsOf(Accessor("missing", "N", false)))
        @AssertThrows[GrammarException](implementorsOf(Provided("", "func it(): Unit", "()", ["Missing"])))
    }
}
