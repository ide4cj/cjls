package loupe.hir

import std.unittest.*
import std.unittest.testmacro.*
import loupe.fixture.*

@Test
class LangItemTest {
    @TestCase[item in [LangItem.OptionEnum, LangItem.OptionSome, LangItem.OptionNone, LangItem.CompositionFunc,
        LangItem.ObjectClass, LangItem.StringStruct, LangItem.FutureClass, LangItem.IterableInterface,
        LangItem.RangeStruct, LangItem.ArrayStruct, LangItem.ExceptionClass, LangItem.TokensClass]]
    func eachLangItemIsADeclarationOfTheSdksStd(item: LangItem) {
        // arrange
        let parsed =
            Fixture
                .parse(
                    #"
            package m
            class Option {}
            enum E { Some(Int64) | None }
            "#
                )
        let db =
            parsed
                .database(
                    binaries: [
                        stdCjoRead("std.core", stdCjo("std.core")),
                        stdCjoRead("std.ast", stdCjo("std.ast"))
                    ]
                )
        let source = db.sourceFile(parsed.files[0].fileId).getOrThrow()
        let from = PackageRef.Source(packageOfFile(db, source).getOrThrow())

        // act
        let id = langItem(db, from, item)

        // assert: of std, whatever the package declares (its own `Option`, `Some` and `None`)
        @Expect(id.map {one => one.item(db).kind}, Some(item.kind()))
        @Expect(id.flatMap {one => packageRefOf(db, one)}.map {one => nameOf(db, one)}, Some(item.pkg()))
    }
}
