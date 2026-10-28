package app
import api.identity
func f(): Int64 { let x = identity("wrong"); return /*@result*/x/*@/result*/ }
