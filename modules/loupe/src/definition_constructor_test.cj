package loupe

import std.unittest.*
import std.unittest.testmacro.*

@Test
class ConstructorDefinitionTest {
    @TestCase
    func aCallGoesToTheConstructorItsArgumentsChoose() {
        for (argument in ["1", "true"]) {
            let chosen = if (argument == "1") { "Int64" } else { "Bool" }
            let other = if (argument == "1") { "Bool" } else { "Int64" }
            checkDefinition(#"
                //- /main.cj module=m package=m
                package m
                class C {
                    init(x: OTHER) {}
                    init(x: CHOSEN) {}
                //  ^^^^ def
                }
                func f() { $0C(ARGUMENT) }
                "#.replace("OTHER", other).replace("CHOSEN", chosen).replace("ARGUMENT", argument))
        }
    }

    @TestCase
    func aSingleConstructorIsRecordedToo() {
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            struct C {
                init(x: Int64) {}
            //  ^^^^ def
            }
            func f() { $0C(1) }
            "#)
    }

    @TestCase
    func aPrimaryConstructorGoesToItsName() {
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            class C {
                C(x: Int64) {}
            //  ^ def
            }
            func f() { $0C(1) }
            "#)
    }

    @TestCase
    func aQualifiedGenericCallGoesToItsConstructor() {
        checkDefinition(#"
            //- /a/a.cj module=m package=m.a
            package m.a
            public class C<T> {
                public init(x: T) {}
            //         ^^^^ def
                public init() {}
            }
            //- /main.cj module=m package=m
            package m
            import m.a
            func f() { a.$0C<Int64>(1) }
            "#)
    }

    @TestCase
    func anAliasCallGoesToTheUnderlyingConstructor() {
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            class C {
                init(x: Int64) {}
            //  ^^^^ def
            }
            type A = C
            func f() { $0A(1) }
            "#)
    }

    @TestCase
    func anImplicitConstructorGoesToItsType() {
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            class C {}
            //    ^ def
            func f() { $0C() }
            "#)
    }

    @TestCase
    func anAmbiguousCallGoesToItsType() {
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            class C {
            //    ^ def
                init(x: Int8) {}
                init(x: Int16) {}
            }
            func f() { $0C(1) }
            "#)
    }

    @TestCase
    func aCallWithNoMatchingConstructorGoesToItsType() {
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            class C {
            //    ^ def
                init(x: Int64) {}
                init(x: Bool) {}
            }
            func f() { $0C(1, 2) }
            "#)
    }

    @TestCase
    func aTypeAnnotationStillGoesToTheType() {
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            class C {
            //    ^ def
                init(x: Int64) {}
            }
            func f(x: $0C) {}
            "#)
    }

    @TestCase
    func anInitDeclarationGoesToItsType() {
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            class C {
            //    ^ def
                init() {}
                public $0init(x: Int64) {}
            }
            "#)
    }

    @TestCase
    func aPrimaryConstructorDeclarationGoesToItsType() {
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            struct C {
            //     ^ def
                $0C(x: Int64) {}
            }
            "#)
    }

    @TestCase
    func constructorCallsRemainReferencesToTheType() {
        checkReferences(#"
            //- /main.cj module=m package=m
            package m
            class $0C {
            //    ^ text decl
                init(x: Int64) {}
                init(x: Bool) {}
            }
            func f(x: C) { C(1); C(true) }
            //        ^ text
            //             ^ read
            //                   ^ read
            "#)
    }

    @TestCase
    func aConstructorCallStillHoversTheType() {
        checkHover(#"
            //- /main.cj module=m package=m
            package m
            class C {
                init(x: Int64) {}
            }
            func f() { $0C(1) }
            //         ^ class C in m
            "#)
    }

    @TestCase
    func enumConstructorOverloadsAreChosenByArgumentTypeAndArity() {
        for ((call, index) in [("C(1)", 0), ("C(true)", 1), ("C(1, true)", 2),
            ("E.C(1)", 0), ("E.C(true)", 1), ("E.C(1, true)", 2)]) {
            let constructors = ["    | C(Int64)", "    | C(Bool)", "    | C(Int64, Bool)"]
            let declarations = String.join(constructors.map {
                one => if (one == constructors[index]) { one + "\n//    ^ def" } else { one }
            }, delimiter: "\n")
            checkDefinition(#"
                //- /main.cj module=m package=m
                package m
                enum E {
                CONSTRUCTORS
                }
                func f() { CALL }
                "#.replace("CONSTRUCTORS", declarations.replace("\n", "\n                ")).replace("CALL", call.replace("C(", "$0C(")))
        }
    }

    @TestCase
    func anExpectedEnumTypeChoosesBetweenConstructorsOfDifferentEnums() {
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            enum A { C(Int64) }
            enum B { C(Int64) }
            //       ^ def
            func f(): B { $0C(1) }
            "#)
    }

    @TestCase
    func anEnumConstructorDeclarationGoesToItsEnum() {
        checkDefinition(#"
            //- /main.cj module=m package=m
            package m
            enum E {
            //   ^ def
                | C(Int64)
                | $0C(Bool)
            }
            "#)
    }

    @TestCase
    func aBinaryConstructorGoesToItsAttachedSource() {
        checkDefinitionInStd(#"
            //- /main.cj module=m package=m
            package m
            import std.collection.ArrayList
            func f() { $0ArrayList<Int64>() }
            "#, ["std.core", "std.collection"],
            ["collection/array_list.cj: init in `public init() {`"])
    }

}
