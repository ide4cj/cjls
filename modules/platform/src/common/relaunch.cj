@NonProduct
features {}
package platform

/**
 * Starts this program over, with its own command line, under the environment as it is now. On
 * POSIX the process is replaced by `execvp`, keeping its id and its stdio, and this returns only if
 * that failed. On Windows nothing replaces a process: the program runs again as a child on the same
 * stdin, stdout and stderr, and this waits for it; `tieChildrenToThisProcess` first makes it die
 * with this process.
 *
 * @return the exit code of the child the program ran again as
 * @throws Exception - if the program could not be started over
 */
public common func relaunch(): Int64

/**
 * Makes every child this process starts from now on die with it, however it ends, `TerminateProcess`
 * included: on Windows this process goes into a job that terminates what is in it when its last
 * handle closes, and the handle is this process's alone (D78). On POSIX there is nothing to do:
 * `relaunch` replaces the process rather than starting a child.
 *
 * @throws ProcessStartException - if Windows gives no such job: a child whose parent is killed then lives on
 * until its stdin reaches EOF
 */
public common func tieChildrenToThisProcess(): Unit
