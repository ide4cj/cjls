package app
import api.*
func f(): Int64 { return value() }
//                       ^^^^^^^ return error: mismatched types: expected 'Int64', found 'String'
