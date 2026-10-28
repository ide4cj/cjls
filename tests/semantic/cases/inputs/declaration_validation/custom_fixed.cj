package audit
@Annotation
public class A { const init() {} }
@A class C {}
func f() {
    func g() {}
    let x = 1
}
