package audit
func useOther(value: Secret): Unit {}
func callOther(): Int64 { hidden() }
func constructorOther(): Unit { let value = HiddenCtor }
