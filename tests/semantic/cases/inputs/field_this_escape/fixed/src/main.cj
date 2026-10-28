package audit
class C { let x: Int64; init() { x = 1; use(this) } }; func use(c: C): Unit {}
