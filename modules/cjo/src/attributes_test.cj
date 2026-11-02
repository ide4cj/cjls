package cjo

import std.unittest.*
import std.unittest.testmacro.*
import fbs.*

@Test
class AttributesTest {
    @TestCase
    func interopMappingBitsDoNotAliasLaterAttributes() {
        // arrange
        // Fixed wire bits catch accidental aliasing when the SDK inserts interop attributes.
        let bytes = Array<Byte>(16, repeat: 0)
        writeUInt64(bytes, 8, (1u64 << 20) | (1u64 << 28))
        let attributes = Attributes(FbVector<UInt64>(bytes, 0, 2, 8, readUInt64))

        // act
        let actual =
            [
                Attribute.JavaCjMapping,
                Attribute.AlreadyLoaded,
                Attribute.DesugaredForeignField,
                Attribute.ObjCExportMovedMemberProxy
            ]
                .map { attribute => attributes.has(attribute) }

        // assert
        @Expect(actual, [true, true, false, false])
    }
}
