package extensions
import api.C
public interface I { static func e(): Int64 }
extend C <: I { public static func e(): Int64 { 1 } }
