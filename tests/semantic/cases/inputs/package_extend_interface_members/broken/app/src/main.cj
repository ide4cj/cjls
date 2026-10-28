package app
import api.C
import extensions.I
func f(): Int64 { C.e() }
//                  ^ member error: 'e' is not a member of class 'C'
