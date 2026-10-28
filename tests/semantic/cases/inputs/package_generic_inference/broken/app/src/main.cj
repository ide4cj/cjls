package app
import api.identity
func f(): Int64 { let x = identity("wrong"); return x }
//                                                  ^ result error: mismatched types: expected 'Int64', found 'String'
