package audit
func extra(): Int64 { return "wrong" }
//                           ^^^^^^^ extra_return error: mismatched types: expected 'Int64', found 'String'
