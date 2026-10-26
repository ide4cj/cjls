package loupe

import std.unittest.*
import std.unittest.testmacro.*

/**
 * An annotation of the workspace's (`@A[1]` of an `@Annotation class A`), which the parser reads as a macro call: the
 * class, rather than the constructor a regular call of the class would choose.
 */
@Test
class AnnotationDefinitionTest {
    @TestCase
    func anAnnotationGoesToItsClass() {
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            @Annotation
            public class A {
            //           ^ def
                public const init() {}
                public const init(x: Int64) {}
            }
            @$0A[1]
            class C {}
            "#)
    }

    @TestCase
    func anAnnotationOfAnotherPackageAfterItsName() {
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            import m.a
            class C {
                @a.$0A
                func f(): Unit {}
            }
            //- /a/a.cj module=m package=m.a
            package m.a
            @Annotation
            public class A {
            //           ^ def
                public const init() {}
            }
            "#)
    }

    @TestCase
    func anAnnotationOnAParameter() {
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            @Annotation
            public class A {
            //           ^ def
                public const init() {}
            }
            class C {
                C(@$0A let x: Int64) {}
            }
            "#)
    }

    @TestCase
    func aMacroOfTheNameIsTheMacro() {
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            import m.ms.*
            @Annotation
            public class A {
                public const init() {}
            }
            @$0A
            class C {}
            //- /ms/ms.cj module=m package=m.ms
            macro package m.ms
            import std.ast.*
            public macro A(input: Tokens): Tokens { input }
            //           ^ def
            "#)
    }

    @TestCase
    func aCallInABodyIsNoAnnotation() {
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            @Annotation
            public class A {
                public const init() {}
            }
            func f(): Unit {
                @$0A(1)
            //   ^ no definition
            }
            "#)
    }
}
