package audit
@Annotation public class A {
    const init(x: Int64) {}
    const init(x: String) {}
}
@Annotation public class B { const init(x!: Int64 = 1) {} }
@A[1] class C {}
@A["global"] let global = 1
func f() {
    let value = 1
    func g() {}
    let variable = 1
    let (a, b) = (1, 2)
    let named = 1
    let _ = 1
    let (_, _) = (1, 2)
    let multiple = 1
    let defaulted = 1
}
