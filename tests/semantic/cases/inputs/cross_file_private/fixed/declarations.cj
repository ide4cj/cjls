package audit
class Secret {}
func hidden(): Int64 { 1 }
private func useHere(value: Secret): Int64 { hidden() }
private enum HiddenEnum { | HiddenCtor }
