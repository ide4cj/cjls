features { os.windows }
package platform

import std.env.{getCommand, getCommandLine}
import std.process.{launch, ProcessRedirect}

public specific func relaunch(): Int64 {
    let child = launch(getCommand(), getCommandLine()[1..], stdIn: ProcessRedirect.Inherit,
        stdOut: ProcessRedirect.Inherit, stdErr: ProcessRedirect.Inherit)
    child.wait()
}

public specific func tieChildrenToThisProcess(): Unit {
    KillOnCloseJob().assign(unsafe { GetCurrentProcess() })
}
