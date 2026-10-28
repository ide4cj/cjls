package app
import api.C
import contracts.I
extend C <: I {}
//     ^ orphan error: imported type 'C' cannot extend imported interface
