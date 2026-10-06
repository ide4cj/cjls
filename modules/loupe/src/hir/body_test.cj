package loupe.hir

import std.collection.*
import std.sync.AtomicInt64
import std.unittest.*
import std.unittest.testmacro.*
import calca.*
import calca.macros.*
import rope.Rope
import loupe.db.{AnalysisDatabase, SourceFile}
import loupe.fixture.*
import loupe.vfs.CjoFileRead

/**
 * The database of `fixture`, its only file, and the declaration named `name` among its items.
 */
func declOf(fixture: String, name: String, binaries!: Array<CjoFileRead> = []): (AnalysisDatabase, SourceFile, DefId) {
    let parsed = Fixture.parse(fixture)
    let db = parsed.database(binaries: binaries)
    let source = db.sourceFile(parsed.files[0].fileId).getOrThrow()
    let item = named(itemTree(db, source).items, name)
    (db, source, DefId(db, ItemFile.Source(source), item.id))
}

/**
 * The first expression of the body of `def` that uses the name `name`.
 */
func useOf(db: AnalysisDatabase, def: DefId, name: String): ExprId {
    let lowered = body(db, def)
    for (i in 0..lowered.exprs.size) {
        if (let PathExpr(used, _) <- lowered.exprs[i] && used == name) {
            return ExprId(i)
        }
    }
    throw IllegalStateException("no use of ${name}")
}

let bodyReaderRuns = AtomicInt64(0)

/**
 * A query reading a declaration's body, as inference will; it counts its runs.
 */
@CalcaTracked
func exprCount(db: AnalysisDatabase, def: DefId): Int64 {
    bodyReaderRuns.fetchAdd(1)
    body(db, def).exprs.size
}

@Test
class BodyTest {
    @TestCase
    func everyExpressionOfTheLanguageIsLowered() {
        // arrange
        let (db, _, f) = declOf(#"
            package m
            enum E { A(Int64) | B }
            class R {}
            func f(o: ?Int64, xs: Array<Int64>, e: E): Unit {
                let (a, b) = (1, "s${a}")
                var c: Int64 = -a + 2 * 3 ** 2 % 4
                c += 1
                c++
                let arr = [1, 2, 3][0..2 : 1]
                let g = {x: Int64, _ => x}
                g(1, 2)
                xs.size
                o?.toString()
                if (let Some(v) <- o && v > 0) { v } else if (true) { 0 } else { 1 }
                while (let Some(v) <- o) { break }
                do { continue } while (false)
                for (i in xs where i > 0) { i }
                match (e) { case A(n) | B => () case _ => () }
                match { case c > 0 => () case _ => () }
                try (r = R()) { throw Exception() } catch (x: Exception | Error) { () } finally { () }
                spawn { => () }
                synchronized (r) { () }
                unsafe { () }
                let t = Int64(1.5)
                let u = Int64.Max
                let w: VArray<Int64, $2> = VArray<Int64, $2>(repeat: 0)
                o is Int64
                o as Int64
                this
                return
            }
            "#, "f")
        // act
        let lowered = body(db, f)
        // assert
        @Expect(lowered.exprs.filter {expr => expr == Expr.MissingExpr}.size, 0)
        @Expect(lowered.pats.filter {pat => pat == Pat.MissingPat}.size, 0)
        @Expect(lowered.locals.map {local => local.name}, ["o", "xs", "e", "a", "b", "c", "arr", "x", "g", "v", "v", "i", "n", "B",
            "r", "x", "t", "u", "w"])
    }

    @TestCase
    func aCommentInTheBodyLeavesItEqualAndWhatReadItAlone() {
        // arrange
        let parsed = Fixture.parse(#"
            package m
            func f(x: Int64): Int64 { x + 1 }
            func g(): Int64 { 2 }
            "#)
        let db = parsed.database()
        let fileId = parsed.files[0].fileId
        let source = db.sourceFile(fileId).getOrThrow()
        let f = DefId(db, ItemFile.Source(source), itemTree(db, source).items[0].id)
        exprCount(db, f)
        let before = bodyReaderRuns.load()
        // act
        db.setFileText(fileId, Rope("package m\n\nfunc f(x: Int64): Int64 {\n    // one more\n    x + 1\n}\nfunc g(): Int64 { 3 }\n"))
        exprCount(db, f)
        // assert
        @Expect(bodyReaderRuns.load(), before)
    }

    @TestCase
    func anEditOfTheBodyRunsAgainWhatReadIt() {
        // arrange
        let parsed = Fixture.parse(#"
            package m
            func f(x: Int64): Int64 { x }
            "#)
        let db = parsed.database()
        let fileId = parsed.files[0].fileId
        let source = db.sourceFile(fileId).getOrThrow()
        let f = DefId(db, ItemFile.Source(source), itemTree(db, source).items[0].id)
        exprCount(db, f)
        let before = bodyReaderRuns.load()
        // act
        db.setFileText(fileId, Rope("package m\nfunc f(x: Int64): Int64 { x + 1 }\n"))
        // assert
        @Expect(exprCount(db, f), 4)
        @Expect(bodyReaderRuns.load(), before + 1)
    }

    @TestCase
    func aLetOpensAScopeForWhatFollowsIt() {
        // arrange
        let (db, _, f) = declOf(#"
            package m
            func f(): Int64 {
                let x = 1
                let y = x
                y
            }
            "#, "f")
        let scopes = exprScopes(db, f)
        let lowered = body(db, f)
        // act
        let names = scopes.chain(scopes.scopeOf(useOf(db, f, "y"))).map {
            scope => scopes[scope].entries.map {local => lowered[local].name}
        }
        // assert
        let expected: Array<Array<String>> = [["y"], ["x"], [], []]
        @Expect(names, expected)
    }

    @TestCase
    func aMemberOfAClassOfStdIsFoundThroughItsSupertypes() {
        // N69: `message` is `Exception`'s, which `IllegalArgumentException` inherits from
        // arrange
        let (db, _, x) = declOf(#"
            package m
            class X <: IllegalArgumentException {
                func f(): String { message }
            }
            "#, "X", binaries: [stdCjoRead("std.core", stdCjo("std.core"))])
        let f = DefId(db, x.file(db), named(itemOf(db, x).getOrThrow().members, "f").id)
        // act
        let resolution = resolveBodyName(db, f, exprScopes(db, f).scopeOf(useOf(db, f, "message")), "message")
        // assert
        let targets = match (resolution) {
            case Values(targets) => targets
            case InFile(_) => Array<ValueTarget>()
        }
        @Assert(targets.size, 1)
        let owner = match (targets[0]) {
            case MemberOf(MemberDecl(id)) where id.file(db) != x.file(db) =>
                itemOf(db, parentOf(db, id).getOrThrow()).flatMap {item => item.names.get(0)}
            case _ => None<String>
        }
        @Expect(owner, Some("Exception"))
    }
}
