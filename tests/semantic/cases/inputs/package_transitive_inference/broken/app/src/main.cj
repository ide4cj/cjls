package app
import bridge.value
func f(): Int64 { let x = value(); return x }
//                                        ^ result error: mismatched types: expected 'Int64', found 'String'
