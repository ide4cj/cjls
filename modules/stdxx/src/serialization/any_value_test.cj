package stdxx.serialization

import std.collection.ArrayList
import std.unittest.*
import std.unittest.testmacro.*
import stdx.serialization.serialization.*
import fjson.fromJsonBytes

@Test
class AnyValueTest {
    @TestCase[dm in [
        DataModelNull(),
        DataModelSeq(ArrayList<DataModel>([DataModelInt(1), DataModelNull()])),
        DataModelStruct().add(field("k", "v"))
    ]]
    func whateverIsReadIsWrittenBackAsIs(dm: DataModel) {
        // act
        let written = AnyValue.deserialize(dm).serialize()

        // assert
        @Expect(refEq(dm, written))
    }

    @TestCase
    func anIntegerPastInt64ReadsAsTheNearestFloat() {
        // act
        let value = fromJsonBytes<AnyValue>("[9223372036854775807, 100000000000000000000]".toArray())

        // assert
        let items = (value.data as DataModelSeq).getOrThrow().getItems()
        @Expect((items[0] as DataModelInt).getOrThrow().getValue(), Int64.Max)
        @Expect((items[1] as DataModelFloat).getOrThrow().getValue(), 1e20)
    }
}
