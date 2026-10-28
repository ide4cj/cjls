package audit
enum E { A | B }; func f(e: E): Int64 { match (e) { case A => 1; case B => 2 } }
