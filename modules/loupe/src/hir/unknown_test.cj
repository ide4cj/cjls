package loupe.hir

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import loupe.db.{AnalysisDatabase, SourceFile}
import loupe.fixture.*
import loupe.syntax.parse

/**
 * Checks what each expression of the bodies of `fixture` of no type known is is its annotations:
 * `//^ error` under one of an error type, `//^ todo(reason)` under one the analysis cannot type,
 * `//^ no value` under a type or package before a `.`. An expression of a type known, if one
 * holding an unknown one, has none. `binaries` are the packages of std's of the project.
 */
func checkUnknowns(fixture: String, binaries!: Array<String> = ["std.core"]): Unit {
    let parsed = Fixture.parse(fixture)
    let db = parsed.database(binaries: binaries.map {name => stdCjoRead(name, stdCjo(name))})
    let actual = ArrayList<Annotation>()
    for (file in parsed.files) {
        let source = db.sourceFile(file.fileId).getOrThrow()
        for (item in itemTree(db, source).items) {
            annotateUnknowns(source, item, actual, db)
        }
    }
    expectAnnotations(fixture, actual.toArray())
}

func annotateUnknowns(source: SourceFile, item: Item, actual: ArrayList<Annotation>, db: AnalysisDatabase): Unit {
    let root = parse(db, source).syntaxNode()
    let def = DefId(db, ItemFile.Source(source), item.id)
    match (item.kind) {
        case Func | Main | Var | Prop | Init | PrimaryInit =>
            let lowered = bodyWithSourceMap(db, def)
            let result = inferBody(db, def)
            // a node's expression is its first: those after it are a desugaring's (A29)
            let seen = HashSet<Int64>()
            for (i in 0..lowered.body.exprs.size) {
                let ptr = lowered.sourceMap.exprs.get(i) ?? continue
                let node = (ptr ?? continue).tryToNode(root) ?? continue
                if (!seen.add(node.textRange.start * 1_000_000 + node.textRange.end)) {
                    continue
                }
                let text = match (result[ExprId(i)].map {ty => ty.kind(db)}) {
                    case None => "no value"
                    case Some(ErrorTy) => "error"
                    case Some(TodoTy(why)) => "todo(${why})"
                    case _ => continue
                }
                actual.add(Annotation(source.fileId(db), node.textRange, text))
            }
        case _ => ()
    }
    for (member in item.members) {
        annotateUnknowns(source, member, actual, db)
    }
}

/**
 * What an expression of no type known is (#53, D76): an error the user made, which cjc reports, and
 * whatever is made of it; a type the analysis cannot find, and why, and whatever is made of it; no
 * value, a type or package before a `.`. Each case compiled with cjc 1.3.0-alpha.20261002 first:
 * one of no `cjc:` comment compiles.
 */
@Test
class UnknownTest {
    @TestCase
    func anErrorOfTheUserIsAnErrorAndSoIsWhatIsMadeOfIt() {
        checkUnknowns(#"
            package m
            class C {
                func f(): Int64 { 1 }
                func h(a: Int64): Int64 { a }
                func h(a: String): Int64 { 1 }
                func m(): Unit {
                    // cjc: 'nope' is not a member of class 'C'
                    let n = this.nope
            //              ^^^^^^^^^ error
                }
            }
            func g(c: C): Unit {
                // cjc: 'nope' is not a member of class 'C'
                let a = c.nope
            //          ^^^^^^ error
                let b = a.f()
            //          ^ error
            //          ^^^ error
            //          ^^^^^ error
                // cjc: undeclared identifier 'undeclared'
                let u = undeclared + 1
            //          ^^^^^^^^^^ error
            //          ^^^^^^^^^^^^^^ error
                // cjc: the type Int64 of expression in for-in expression does not implement Iterator
                for (x in 1) {
                    let y = x
            //              ^ error
                }
                // cjc: ambiguous use of 'h'
                let f = c.h
            //          ^^^ error
            }
            "#)
    }

    @TestCase
    func aMacroCallIsOfATypeNotKnownAndSoIsWhatIsMadeOfIt() {
        checkUnknowns(#"
            //- /main.cj module=m package=m
            package m
            import m.ms.M
            func f(): Unit {
                let a = @M(1)
            //          ^^^^^ todo(macro call)
                // cjc: undeclared identifier 'size': `M` gives what it is given, `1`
                let b = a.size
            //          ^ todo(macro call)
            //          ^^^^^^ todo(macro call)
                // cjc: undeclared identifier 'undeclared'
                let c = a + undeclared
            //          ^ todo(macro call)
            //              ^^^^^^^^^^ error
            //          ^^^^^^^^^^^^^^ todo(macro call)
            }
            //- /ms/ms.cj module=m package=m.ms
            macro package m.ms
            import std.ast.*
            public macro M(input: Tokens): Tokens { input }
            "#)
    }

    @TestCase
    func aMacroOfTheUserNamedAsStdsIsNotStds() {
        checkUnknowns(#"
            //- /main.cj module=m package=m
            package m
            import m.ms.Expect
            func f(): Unit {
                let a = @Expect(1)
            //          ^^^^^^^^^^ todo(macro call)
            }
            //- /ms/ms.cj module=m package=m.ms
            macro package m.ms
            import std.ast.*
            public macro Expect(input: Tokens): Tokens { input }
            "#)
    }

    @TestCase
    func aMemberOfATypeAMacroIsCalledOnMayBeTheMacros() {
        checkUnknowns(#"
            //- /main.cj module=m package=m
            package m
            import m.ms.M
            @M
            class C {
                func g(a: Int64): Unit {}
                func g(a: String): Unit {}
            }
            class D {
                func h(a: Int64): Unit {}
                func h(a: String): Unit {}
            }
            func k(a: Int64): Unit {}
            func k(a: String): Unit {}
            func f(c: C, d: D): Unit {
                // cjc: 'added' is not a member of class 'C': `M` adds none
                let a = c.added
            //          ^^^^^^^ todo(macro member)
                // cjc: 'added' is not a member of class 'D'
                let b = d.added
            //          ^^^^^^^ error
                // cjc: undeclared identifier 'undeclared': `M` declares none
                let u = undeclared
            //          ^^^^^^^^^^ todo(macro member)
                // cjc: 'nope' is not a member of class 'C'
                let s = C.nope
            //          ^ no value
            //          ^^^^^^ todo(macro member)
                // cjc: 'nope' is not a member of class 'D'
                let t = D.nope
            //          ^ no value
            //          ^^^^^^ error
                // cjc: cannot convert a boolean literal to type 'Int64'
                c.g(true)
            //  ^^^ todo(macro member)
            //  ^^^^^^^^^ todo(macro member)
                // cjc: cannot convert a boolean literal to type 'Int64'
                d.h(true)
            //  ^^^ error
            //  ^^^^^^^^^ error
                // cjc: cannot convert a boolean literal to type 'Int64'
                k(true)
            //  ^ todo(macro member)
            //  ^^^^^^^ todo(macro member)
                let z = 0
            }
            //- /ms/ms.cj module=m package=m.ms
            macro package m.ms
            import std.ast.*
            public macro M(input: Tokens): Tokens { input }
            "#)
    }

    @TestCase
    func aTypeOrPackageBeforeADotIsNoValue() {
        checkUnknowns(#"
            //- /main.cj module=m package=m
            package m
            import m.p
            enum E {
                | A | B
            }
            class C {
                static func s(): Int64 { 1 }
            }
            func f(): Unit {
                let a = E.A
            //          ^ no value
                let b = C.s()
            //          ^ no value
                let c = Int64.Max
            //          ^^^^^ no value
                let d = p.g()
            //          ^ no value
                let e = p.C2.s()
            //          ^ no value
            //          ^^^^ no value
            }
            //- /p/p.cj module=m package=m.p
            package m.p
            public func g(): Int64 { 1 }
            public class C2 {
                public static func s(): Int64 { 1 }
            }
            "#)
    }

    @TestCase
    func aLocalFunctionsTypeParameterIsNotKnownYet() {
        checkUnknowns(#"
            package m
            func f(): Unit {
                func id<T>(x: T): T {
                    return x
            //             ^ todo(local generic)
                }
                let a = id(1)
            //          ^^^^^ todo(local generic)
            }
            "#)
    }

    @TestCase
    func whatStdsCoreWouldTypeIsNotKnownWithoutIt() {
        checkUnknowns(#"
            package m
            func f(): Unit {
                let a = "s"
            //          ^^^ todo(no std)
                let b = [1]
            //          ^^^ todo(no std)
            }
            "#, binaries: [])
    }

    @TestCase
    func aQuoteWithoutStdAstImportedIsAnError() {
        checkUnknowns(#"
            package m
            func f(): Unit {
                // cjc: import 'std.ast' to use the 'quote' expression
                let a = quote(1)
            //          ^^^^^^^^ error
            }
            "#, binaries: ["std.core", "std.ast"])
    }

    @TestCase
    func anIfOrMatchWhoseValueIsNotUsedNeedsNoJoin() {
        checkUnknowns(#"
            package m
            func a(): Int64 { 1 }
            func b(): String { "" }
            func f(c: Bool): Unit {
                if (c) { a() } else { b() }
                match (c) {
                    case true => a()
                    case false => b()
                }
                while (c) {
                    if (c) { a() } else { b() }
                }
                // cjc: types Int64 and Struct-String of the two branches of this 'if' expression mismatch
                let y = if (c) { a() } else { b() }
            //          ^^^^^^^^^^^^^^^^^^^^^^^^^^^ error
            }
            "#)
    }

    @TestCase
    func aCallOfOverloadsByNameIsNotMatchedYet() {
        checkUnknowns(#"
            package m
            class C {
                func r(at!: Int64): Int64 { at }
                func r(range: Range<Int64>): Unit {}
            }
            func f(c: C): Unit {
                let x = c.r(at: 1)
            //          ^^^ todo(arg matching)
            //          ^^^^^^^^^^ todo(arg matching)
            }
            "#)
    }

    @TestCase
    func anOperatorOfATypeAMacroIsCalledOnMayBeTheMacros() {
        checkUnknowns(#"
            //- /main.cj module=m package=m
            package m
            import m.ms.M
            @M
            class C {}
            class D {}
            func f(a: C, b: C, d: D): Unit {
                // cjc: invalid binary operator '==' on type 'Class-C' and 'Class-C': `M` adds none
                let x = a == b
            //          ^^^^^^ todo(macro member)
                // cjc: invalid binary operator '==' on type 'Class-D' and 'Class-D'
                let y = d == d
            //          ^^^^^^ error
            }
            //- /ms/ms.cj module=m package=m.ms
            macro package m.ms
            import std.ast.*
            public macro M(input: Tokens): Tokens { input }
            "#)
    }

    @TestCase
    func aCallWithATrailingLambdaIsOneCallOfIt() {
        // cjc: `k(1) {y => y}` is an `Int64`
        checkUnknowns(#"
            package m
            func k(a: Int64, f: (Int64) -> Int64): Int64 { f(a) }
            func t(): Unit {
                let x = k(1) {y => y}
            }
            "#)
    }

    @TestCase
    func aMacrosAttributeOfAnythingButIdentifiersBetweenBarsIsNotRead() {
        checkUnknowns(#"
            package m
            import std.unittest.*
            import std.unittest.testmacro.*
            func t(): Unit {
                // cjc: undeclared type name 'std'
                let e = @AssertThrows[std.core.Exception](throw Exception())
            //          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ todo(macro call)
            }
            "#, binaries: ["std.core", "std.unittest", "std.unittest.testmacro"])
    }
}
