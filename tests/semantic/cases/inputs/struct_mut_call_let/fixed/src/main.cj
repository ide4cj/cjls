package audit
struct S { var x = 0; mut func f(): Unit { x = 1 } }; func g(): Unit { var s = S(); s.f() }
