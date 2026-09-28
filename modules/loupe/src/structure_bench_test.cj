package loupe

import std.unittest.*
import std.unittest.testmacro.*
import rope.Rope
import loupe.vfs.FileId
import loupe.db.AnalysisDatabase

// what tests/perf opens: its block of declarations, 36 times, about 2000 lines
let benchSource: String = {
    =>
    let text = StringBuilder("package bench\n\n")
    for (i in 0..36) {
        text.append(
            "/** A class, its members, and what uses them. */\n" +
            "public open class Shape${i} {\n" +
            "    public var name: String = \"shape${i}\"\n" +
            "    public init() {}\n" +
            "    public open func area(): Float64 {\n" +
            "        let sides = [1.0, 2.0, 3.0]\n" +
            "        var total = 0.0\n" +
            "        for (side in sides) {\n" +
            "            total += side * side\n" +
            "        }\n" +
            "        total\n" +
            "    }\n" +
            "}\n" +
            "\n" +
            "public struct Point${i} {\n" +
            "    public let x: Int64\n" +
            "    public let y: Int64\n" +
            "    public init(x: Int64, y: Int64) {\n" +
            "        this.x = x\n" +
            "        this.y = y\n" +
            "    }\n" +
            "    public func distance(other: Point${i}): Int64 {\n" +
            "        match ((this.x - other.x, this.y - other.y)) {\n" +
            "            case (0, dy) => dy\n" +
            "            case (dx, 0) => dx\n" +
            "            case (dx, dy) => dx * dx + dy * dy\n" +
            "        }\n" +
            "    }\n" +
            "}\n" +
            "\n" +
            "public interface Named${i} {\n" +
            "    func label(): String\n" +
            "}\n" +
            "\n" +
            "extend Shape${i} <: Named${i} {\n" +
            "    public func label(): String { \"\${name}: \${area()}\" }\n" +
            "}\n" +
            "\n" +
            "public enum Color${i} {\n" +
            "    | Red | Green | Blue(Int64)\n" +
            "}\n" +
            "\n" +
            "func use${i}(shape: Shape${i}, point: Point${i}): String {\n" +
            "    let color = Color${i}.Blue(point.distance(Point${i}(1, 2)))\n" +
            "    shape.label()\n" +
            "}\n" +
            "\n" +
            "")
    }
    text.toString()
}()

// parsed once: what is measured is the walk over the tree
let benchDb: AnalysisDatabase = {
    =>
    let db = AnalysisDatabase()
    db.setFileText(FileId(0), Rope(benchSource))
    fileStructure(db, FileId(0))
    db
}()

@Test
class StructureBench {
    @Bench
    func outlineOfAFile(): Int64 {
        fileStructure(benchDb, FileId(0)).size
    }
}
