package audit
func f(x: Box<() -> Unit>): Unit {}
//            ^ d0 error: generics type arguments do not match the constraint of 'Class-Box<Generics-T>'
