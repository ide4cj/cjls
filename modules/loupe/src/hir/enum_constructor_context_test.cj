package loupe.hir

import std.unittest.*
import std.unittest.testmacro.*

@Test
class EnumConstructorContextTest {
    @TestCase
    func unqualifiedConstructorsInferTheirOwnEnumArgumentsInsideTheEnum() {
        // arrange
        // cjc accepts this specialization-changing method, as std.core's Option.map does.
        let (db, _, owner) =
            declOf(
                #"
            package probe
            public enum Box<T> {
                Item(T) | Empty
                public func map<R>(transform: (T) -> R): Box<R> {
                    match (this) {
                        case Item(v) => Item(transform(v))
                        case Empty => Empty
                    }
                }
                public func explicit(): Box<Int64> { Item<Int64>(1) }
                public func inferred(): Box<Int64> {
                    let other = Item(1)
                    other
                }
            }
            "#,
                "Box"
            )
        for (member in itemOf(db, owner).getOrThrow().members where member.kind == ItemKind.Func) {
            let method = DefId(db, owner.file(db), member.id)

            // act
            let result = inferBody(db, method)

            // assert
            @Expect(result.diagnostics.size, 0)
        }
    }

    @TestCase
    func anExtendsReceiverDoesNotFixAnUnqualifiedConstructorsArguments() {
        // arrange
        let (db, file, _) =
            declOf(
                #"
            package probe
            public enum Box<T> { Item(T) | Empty }
            extend<T> Box<Box<T>> {
                public func flatten(): Box<T> {
                    match (this) {
                        case Item(v) => v
                        case Empty => Empty
                    }
                }
            }
            "#,
                "Box"
            )
        let extended = itemTree(db, file).items.filter { item => item.kind == ItemKind.Extend }[0]
        let method = DefId(db, ItemFile.Source(file), extended.members[0].id)

        // act
        let result = inferBody(db, method)

        // assert
        @Expect(result.diagnostics.size, 0)
    }

    @TestCase
    func anExplicitEnumQualifierStillFixesTheConstructorArguments() {
        // arrange
        let (db, _, method) =
            declOf(
                #"
            package probe
            public enum Box<T> { Item(T) | Empty }
            func wrong(): Box<Int64> { Box<Bool>.Item(true) }
            "#,
                "wrong"
            )

        // act
        let diagnostics = inferBody(db, method).diagnostics

        // assert
        // Duplicate expression/body reports are tracked separately in #544.
        @Expect(diagnostics.size, 2)
        for (diagnostic in diagnostics) {
            match (diagnostic) {
                case TypeMismatch(_, expected, found) =>
                    @Expect(expected.text(db), "Box<Int64>")
                    @Expect(found.text(db), "Box<Bool>")
                case _ => @Expect(false)
            }
        }
    }
}
