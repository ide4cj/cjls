// Run: cjc --static -O2 k29-option-exception.cj -o repro && ./repro
// Expected: correct (exit 0). Nightly 20261030: wrong: Exception: bad (exit 1).
class E <: Exception {
    init() { super("bad") }
}
func load(x: ?String): String {
    let value = x.getOrThrow { => E() }
    "${value}.suffix"
}
main() {
    try {
        println(load(None))
        2
    } catch (e: E) {
        println("correct")
        0
    } catch (e: Exception) {
        println("wrong: ${e}")
        1
    }
}
