// Run: cjc --static -O2 k29-option-exception.cj -o repro && ./repro
// Expected: correct (exit 0). Nightlies 20261030 and 20261102: wrong: Exception: bad (exit 1).
class ProbeException <: Exception {
    ProbeException() {
        super("bad")
    }

    protected override func getClassName(): String {
        "ProbeException"
    }
}
/**
 * Keep the unwrap and interpolation in a helper: moving them to main hides the SDK defect.
 */
func load(x: ?String): String {
    let value = x.getOrThrow { => ProbeException() }
    "${value}.suffix"
}
main() {
    // arrange
    let input: ?String = None

    try {
        // act
        let result = load(input)

        // assert
        println(result)
        2
    } catch (e: ProbeException) {
        // assert
        println("correct")
        0
    } catch (e: Exception) {
        // assert
        println("wrong: ${e}")
        1
    }
}
