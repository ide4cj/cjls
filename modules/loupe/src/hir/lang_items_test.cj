package loupe.hir

import std.unittest.*
import std.unittest.testmacro.*
import loupe.fixture.*

@Test
class LangItemTest {
    @TestCase
    func eachLangItemIsADeclarationOfTheSdksStdCore() {
        // arrange
        let parsed = Fixture.parse(#"
            package m
            class Option {}
            "#)
        let db = parsed.database(binaries: [stdCjoRead("std.core", stdCjo("std.core"))])
        let source = db.sourceFile(parsed.files[0].fileId).getOrThrow()
        let from = PackageRef.Source(packageOfFile(db, source).getOrThrow())
        let items = [LangItem.OptionEnum, LangItem.CompositionFunc, LangItem.ObjectClass, LangItem.StringStruct,
            LangItem.FutureClass, LangItem.IterableInterface, LangItem.RangeStruct, LangItem.ArrayStruct]

        // act
        let found = items.map {item => langItem(db, from, item)}

        // assert: of `std.core`, whatever the package declares (its own `Option`)
        for (i in 0..items.size) {
            let id = found[i]
            @Expect(id.map {one => one.item(db).kind}, Some(items[i].kind()))
            @Expect(id.flatMap {one => packageRefOf(db, one)}.map {one => nameOf(db, one)}, Some("std.core"))
        }
    }
}
