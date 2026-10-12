package loupe

import std.unittest.*
import std.unittest.testmacro.*

@Test
class WhenDiagnosticsTest {
    @TestCase
    func codeAFalseWhenIsOnIsInactiveWithTheReason() {
        checkDiagnostics(#"
            //- /main.cj cfg=os:Linux
              @When[os == "Windows"] func f() {}
            //^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ hint: code is inactive due to @When: os is "Linux"
              @When[os == "Linux"] func f() {}
            "#)
    }

    @TestCase
    func eachConditionMakingItFalseIsAReason() {
        checkDiagnostics(#"
            //- /main.cj cfg=os:Linux,arch:x86_64
              @When[os == "Windows" || arch == "arm"] let a = 1
            //^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ hint: code is inactive due to @When: os is "Linux" and arch is "x86_64"
              @When[os == "Linux" && arch == "arm"] let b = 1
            //^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ hint: code is inactive due to @When: arch is "x86_64"
            "#)
    }

    @TestCase
    func testAndDebugAreFlags() {
        checkDiagnostics(#"
            //- /main.cj cfg=test:true
              @When[!test] let a = 1
            //^^^^^^^^^^^^^^^^^^^^^^ hint: code is inactive due to @When: test is set
              @When[debug] let b = 1
            //^^^^^^^^^^^^^^^^^^^^^^ hint: code is inactive due to @When: debug is not set
              @When[test && !debug] let c = 1
            "#)
    }

    @TestCase
    func aVersionIsComparedByItsNumbers() {
        checkDiagnostics(#"
            //- /main.cj cfg=cjc_version:1.3.0-alpha.20261002
              @When[cjc_version >= "1.4.0"] let a = 1
            //^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ hint: code is inactive due to @When: cjc_version is "1.3.0-alpha.20261002"
              @When[cjc_version == "1.3.0"] let b = 1
              @When[cjc_version < "1.10.0"] let c = 1
            "#)
    }

    @TestCase
    func aConditionOfACfgTomlIsKnown() {
        checkDiagnostics(#"
            //- /main.cj cfg=feature:fast
              @When[feature == "slow"] let a = 1
            //^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ hint: code is inactive due to @When: feature is "fast"
              @When[feature == "fast"] let b = 1
            "#)
    }

    @TestCase
    func nothingInsideInactiveCodeIsReported() {
        checkDiagnostics(#"
            //- /main.cj cfg=os:Linux
              @When[os == "Windows"] class A { @When[os == "linux"] func f() {} }
            //^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ hint: code is inactive due to @When: os is "Linux"
            "#)
    }

    @TestCase
    func aConditionNoValueIsKnownOfIsActive() {
        checkDiagnostics(#"
            //- /main.cj cfg=os:Linux
              @When[env == "ohos"] let a = 1
              @When[os == "Windows" && env == "ohos"] let b = 1
            //^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ hint: code is inactive due to @When: os is "Linux"
            "#)
    }

    @TestCase
    func whatCjcRejectsIsAnErrorAndItsCodeOutButNotGreyed() {
        checkDiagnostics(#"
            //- /main.cj cfg=os:Linux
            @When[os == "linux"] let a = 1
            //    ^^^^^^^^^^^^^ error: builtin condition 'os' do not support 'linux', supported listed: 'Windows Linux macOS iOS'
            @When[os < "Linux"] let b = 1
            //    ^^^^^^^^^^^^ error: conditional compilation 'os' not support this op '<'
            @When[!(os == "Linux")] let c = 1
            //    ^^^^^^^^^^^^^^^^ error: conditional compilation not support this expression
            @When[os == "Lin${"ux"}"] let d = 1
            //          ^^^^^^^^^^^^ error: conditional compilation's condition value should be string literal without interpolation
            @When[cjc_version > "1.3"] let e = 1
            //    ^^^^^^^^^^^^^^^^^^^ error: cjc version's format should be 'xx.xx.xx'
            @When[debug == "true"] let f = 1
            //    ^^^^^^^^^^^^^^^ error: conditional compilation 'debug' not support this op '=='
            @When[feature] let g = 1
            //    ^^^^^^^ error: conditional compilation not support this expression
            @When[os == "linux" || os == "Linux"] let h = 1
            //    ^^^^^^^^^^^^^ error: builtin condition 'os' do not support 'linux', supported listed: 'Windows Linux macOS iOS'
            "#)
    }

    @TestCase
    func aConditionTheCfgDoesNotSetIsActiveAndNoError() {
        checkDiagnostics(#"
            //- /main.cj cfg=os:Linux
            @When[feature == "fast"] let a = 1
            "#)
    }

    @TestCase
    func aWhenOnAParameterOrALocalIsChecked() {
        checkDiagnostics(#"
            //- /main.cj cfg=os:Linux
            func f(@When[os == "Windows"] a: Int64, b: Int64) {
            //     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ hint: code is inactive due to @When: os is "Linux"
                @When[os == "Windows"] let x = 1
            //  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ hint: code is inactive due to @When: os is "Linux"
            }
            "#)
    }
}

@Test
class WhenResolutionTest {
    @TestCase
    func aCallTakesTheTwinOfTheCfg() {
        checkDefinition(#"
            //- /main.cj module=m package=m cfg=os:Linux
            package m
            @When[os == "Windows"]
            func f(): Int64 { 1 }
            @When[os == "Linux"]
            func f(): Int64 { 2 }
            //   ^ def
            func g() { $0f() }
            "#)
    }

    @TestCase
    func aTypeTakesTheTwinOfTheCfg() {
        checkDefinition(#"
            //- /main.cj module=m package=m cfg=os:Linux
            package m
            @When[os == "Windows"]
            class C {}
            @When[os != "Windows"]
            class C {}
            //    ^ def
            func g(c: $0C) {}
            "#)
    }

    @TestCase
    func anImportAFalseWhenIsOnBringsNothing() {
        checkDefinition(#"
            //- /m/a/a.cj module=m package=m.a
            package m.a
            public func h(): Int64 { 1 }
            //          ^ def
            //- /m/b/b.cj module=m package=m.b
            package m.b
            public func h(): Int64 { 2 }
            //- /m/main.cj module=m package=m cfg=os:Linux
            package m
            @When[os == "Linux"]
            import m.a.*
            @When[os == "Windows"]
            import m.b.*
            func g() { $0h() }
            "#)
    }

    @TestCase
    func aMemberTakesTheTwinOfTheCfg() {
        checkDefinition(#"
            //- /main.cj module=m package=m cfg=os:Linux
            package m
            class C {
                @When[os == "Linux"]
                func m(): Int64 { 1 }
            //       ^ def
                @When[os == "Windows"]
                func m(): Int64 { 2 }
            }
            func g(c: C) { c.$0m() }
            "#)
    }

    @TestCase
    func aLocalTakesTheTwinOfTheCfg() {
        checkDefinition(#"
            //- /main.cj module=m package=m cfg=os:Linux
            package m
            func g(): Int64 {
                @When[os == "Linux"]
                let x = 1
            //      ^ def
                @When[os == "Windows"]
                let x = 2
                $0x
            }
            "#)
    }

    @TestCase
    func aTwinWhoseConditionCjcRejectsIsOutAsInCjc() {
        checkDefinition(#"
            //- /main.cj module=m package=m cfg=os:Linux
            package m
            @When[os == "linux"]
            func f(): Int64 { 1 }
            @When[os == "Linux"]
            func f(): Int64 { 2 }
            //   ^ def
            func g() { $0f() }
            "#)
    }

    @TestCase
    func aParameterTakesTheTwinOfTheCfg() {
        checkDefinition(#"
            //- /main.cj module=m package=m cfg=os:Linux
            package m
            func g(@When[os == "Linux"] x: Int64, @When[os == "Windows"] x: String): Int64 { $0x }
            //                          ^ def
            "#)
    }
}
