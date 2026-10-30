package cjo

import fbs.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
class AttributesTest {
    @TestCase
    func interopMappingBitsDoNotAliasLaterAttributes() {
        // AttributePack.h at 69a4a1ac3baa inserts mapping flags before desugared fields.
        let bytes = Array<Byte>(16, repeat: 0)
        writeUInt64(bytes, 8, (1u64 << 20) | (1u64 << 28))
        let attributes = Attributes(FbVector<UInt64>(bytes, 0, 2, 8, readUInt64))

        @Expect(attributes.has(Attribute.JavaCjMapping))
        @Expect(attributes.has(Attribute.AlreadyLoaded))
        @Expect(!attributes.has(Attribute.DesugaredForeignField))
        @Expect(!attributes.has(Attribute.ObjCExportMovedMemberProxy))
    }
}
