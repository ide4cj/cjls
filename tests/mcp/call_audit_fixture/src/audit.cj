package audit_sample

import calca.macros.CalcaTracked as Track
import std.env.getProcessId as external
import std.env.getCommand

@Track
public func query(): Unit {
    let never = { => external() }
    via()
}

func via(): Unit {
    if (false) { loop() }
    external()
    getCommand()
}

func loop(): Unit { via() }
