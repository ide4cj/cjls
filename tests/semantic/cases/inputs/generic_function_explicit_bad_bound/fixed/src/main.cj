package audit
func g<T>(x: T): Unit where T <: ToString {}; func f(): Unit { g<Int64>(1) }
