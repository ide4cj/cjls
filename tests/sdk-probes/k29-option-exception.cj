// Run: cjc --static -O2 k29-option-exception.cj -o repro && ./repro
// Expected: correct (exit 0). Verified on nightly 20261030: wrong: Exception: bad (exit 1).
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
    try {
        println(load(None))
        2
    } catch (e: ProbeException) {
        println("correct")
        0
    } catch (e: Exception) {
        println("wrong: ${e}")
        1
    }
}
