package cjo

import std.env.getVariable
import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*

/**
 * The bytes of `<name>.cjo` of the SDK's std, of whichever target it has first.
 */
func stdCjo(name: String): Array<Byte> {
    let home = match (getVariable("CANGJIE_HOME")) {
        case Some(h) => Path(h)
        case _ => throw IllegalStateException("CANGJIE_HOME names no SDK, whose std these tests read")
    }
    for (target in Directory.readFrom(home.join("modules")) where target.isDirectory()) {
        let file = target.path.join("std").join("${name}.cjo")
        if (exists(file)) {
            return File.readFrom(file)
        }
    }
    throw IllegalStateException("no ${name}.cjo under ${home.join("modules")}")
}

func opened(bytes: Array<Byte>): Package {
    match (openCjo(bytes)) {
        case Ok(pkg) => pkg
        case Err(e) => throw IllegalStateException("not opened: ${e}")
    }
}

func topLevel(pkg: Package, name: String): Decl {
    for (d in pkg.allDecls where d.isTopLevel && d.identifier == Some(name)) {
        return d
    }
    throw IllegalStateException("${pkg.fullPkgName} has no top-level ${name}")
}

func errorOf(bytes: Array<Byte>): String {
    match (openCjo(bytes)) {
        case Ok(_) => "opened"
        case Err(e) => e.toString()
    }
}

func writeUInt16(bytes: Array<Byte>, pos: Int64, value: UInt16): Unit {
    bytes[pos] = UInt8(value & 0xff)
    bytes[pos + 1] = UInt8(value >> 8)
}

@Test
class OpenCjoTest {
    @TestCase
    func stringIsAPublicStructOfStdCoreInItsFile() {
        // arrange
        let pkg = opened(stdCjo("std.core"))

        // act
        let string = topLevel(pkg, "String")

        // assert
        @Expect(pkg.fullPkgName, Some("std.core"))
        @Expect(string.kind, DeclKind.StructDecl)
        @Expect(string.attributes.has(Attribute.Public))
        @Expect(!string.attributes.has(Attribute.Private))
        @Expect(string.exportId, Some("_CNat6StringE"))
        let begin = string.begin.getOrThrow()
        @Expect(begin.pkgId, 0u32)
        // a file of the package itself is counted from 1
        @Expect(pkg.allFiles[Int64(begin.file) - 1], "std.core/string.cj")
        let isStruct = match (string.info) {
            case Some(DeclInfo.AsStructInfo(info)) => !info.body.isEmpty()
            case _ => false
        }
        @Expect(isStruct)
    }

    @TestCase
    func aBuiltInTypeIsABuiltInDecl() {
        // arrange
        let pkg = opened(stdCjo("std.core"))

        // act
        let pointer = topLevel(pkg, "CPointer")

        // assert
        @Expect(pointer.kind, DeclKind.BuiltInDecl)
        let builtIn = match (pointer.info) {
            case Some(DeclInfo.AsBuiltInInfo(info)) => info.builtInType
            case _ => BuiltInType.CFunc
        }
        @Expect(builtIn, BuiltInType.CPointer)
    }

    @TestCase
    func bytesThatAreNotACjoAreRefused() {
        // arrange
        let text = "not a cjo, whatever it is".toArray()
        let renamed = stdCjo("std.core")
        renamed[4] = b'X'

        // act, assert
        @Expect(errorOf(text), "not a .cjo")
        @Expect(errorOf(Array<Byte>()), "not a .cjo")
        @Expect(errorOf(renamed), "not a .cjo")
    }

    @TestCase
    func aCjoOfAnotherMajorIsRefused() {
        // arrange
        let bytes = stdCjo("std.core")
        let version = opened(bytes).cjoVersion.getOrThrow()
        bytes[version.pos] = CJO_MAJOR + 1

        // act, assert
        @Expect(errorOf(bytes), "a .cjo of format ${CJO_MAJOR + 1}.x, not ${CJO_MAJOR}.x")
    }

    @TestCase
    func aCjoWithNoVersionIsRefused() {
        // arrange
        let bytes = stdCjo("std.core")
        let pkg = opened(bytes)
        // the vtable says the version, field 1, is not stored
        writeUInt16(bytes, pkg.fb.vtable + 4 + 2 * 1, 0)

        // act, assert
        @Expect(errorOf(bytes), "a .cjo with no format version")
    }

    @TestCase
    func aDeclKindThisReaderDoesNotKnowIsKeptAsItsValue() {
        // arrange
        let bytes = stdCjo("std.core")
        let string = topLevel(opened(bytes), "String")
        writeUInt16(bytes, string.fb.pos + string.fb.offset(0), 0x7fff)

        // act
        let kind = topLevel(opened(bytes), "String").kind

        // assert
        @Expect(kind, DeclKind.Unknown(0x7fff))
        @Expect(kind.toString(), "Unknown(32767)")
    }

    @TestCase
    func aUnionMemberThisReaderDoesNotKnowIsKeptAsItsType() {
        // arrange
        let bytes = stdCjo("std.core")
        let string = topLevel(opened(bytes), "String")
        // `info` is field 17, its type 16
        bytes[string.fb.pos + string.fb.offset(16)] = 200

        // act
        let info = topLevel(opened(bytes), "String").info

        // assert
        let tag = match (info) {
            case Some(DeclInfo.Unknown(t)) => t
            case _ => 0u8
        }
        @Expect(tag, 200u8)
    }

    @TestCase
    func aValueAClosedEnumDoesNotHaveThrows() {
        @AssertThrows[CjoException](AccessLevel.fromValue(200))
    }

    @TestCase
    func aVectorLongerThanTheFileThrowsWhenItIsRead() {
        // arrange
        let bytes = stdCjo("std.core")
        let pkg = opened(bytes)
        // `allFiles` is field 5: its offset, then its length where that points
        let at = follow(bytes, pkg.fb.pos + pkg.fb.offset(5))
        writeUInt16(bytes, at + 2, 0x7fff)

        // act, assert
        @AssertThrows[CjoException](opened(bytes).allFiles)
    }
}

@Test
class CjoFindingsTest {
    @TestCase
    func aReExportIsAnImportOfItsFileNotADecl() {
        // arrange
        let pkg = opened(stdCjo("std.unittest"))

        // act
        var reExport = Option<ImportSpec>.None
        for (imports in pkg.allFileImports) {
            for (spec in imports.importSpecs where spec.identifier == Some("Arbitrary")) {
                reExport = spec
            }
        }

        // assert
        let spec = reExport.getOrThrow()
        @Expect(spec.reExport, AccessModifier.Public)
        @Expect(spec.prefixPaths.toArray(), ["std", "unittest", "prop_test"])
        for (d in pkg.allDecls where d.isTopLevel) {
            @Expect(d.identifier != Some("Arbitrary"))
        }
    }

    @TestCase
    func aConstructorTheCompilerAddedIsMarkedSo() {
        // arrange
        let pkg = opened(stdCjo("std.argopt"))

        // act
        var added = 0
        for (d in pkg.allDecls where d.identifier == Some("init") && d.kind == DeclKind.FuncDecl) {
            if (d.attributes.has(Attribute.CompilerAdd)) {
                added++
            }
        }

        // assert
        @Expect(added > 0)
    }
}
