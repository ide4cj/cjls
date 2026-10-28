package extensions
import api.C
public interface I { }
extend C <: I { public static func e(): Int64 { 1 } }
