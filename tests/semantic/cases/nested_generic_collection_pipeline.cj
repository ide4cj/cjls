// ISSUE: 246
// PACKAGE: audit .
// STEP: clean
// CJC: audit clean
// SOURCE: src/main.cj %f
package audit

import std.collection.*

func check(): Unit {
    let joined = [1, 2].map {value => value.toString()} |> collectString(delimiter: ", ")
    let result: String = joined
}
