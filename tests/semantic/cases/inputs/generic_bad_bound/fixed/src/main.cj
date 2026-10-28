package audit
class Box<T> where T <: ToString {}; func f(): Unit { let b = Box<Int64>() }
