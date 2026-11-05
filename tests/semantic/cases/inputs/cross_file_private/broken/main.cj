package audit
func useOther(value: Secret): Unit {}
//                   ^^^^^^ hidden_type error: undeclared type name 'Secret'
func callOther(): Int64 { hidden() }
//                        ^^^^^^ hidden_value error: undeclared identifier 'hidden'
func constructorOther(): Unit { let value = HiddenCtor }
