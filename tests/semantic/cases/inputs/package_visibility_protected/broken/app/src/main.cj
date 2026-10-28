package app
import api.C
func f(c: C): Int64 { c.x }
//                    ^ access error: can not access field 'x'
