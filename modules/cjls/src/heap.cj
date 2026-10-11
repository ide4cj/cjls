package cjls

import std.env.{getCommandLine, getVariable, setVariable}
import stdx.log.Logger
@When[os == "Windows"]
import std.env.getCommand
@When[os == "Windows"]
import std.process.{launch, ProcessRedirect}

/**
 * The runtime reads the heap's limit from this variable, once, before `main`.
 */
const HEAP_SIZE_VARIABLE = "cjHeapSize"

/**
 * The heap the server asks for when nobody chose one: the runtime's own 256 MiB does not hold a
 * large workspace, and an editor starts the server without the variable. A limit takes no memory
 * until it is used; one over the machine's memory is refused by the runtime, which then keeps its
 * default and says so on stderr.
 */
const HEAP_SIZE = "2GB"

@When[os != "Windows"]
foreign func execvp(file: CString, argv: CPointer<CString>): Int32

/**
 * Starts the server over again with `HEAP_SIZE`, unless `cjHeapSize` is set already (by the user,
 * or by this very step before). On POSIX the process is replaced, keeping its id and its stdio, and
 * this returns only if that failed; on Windows the server runs as a child on the same stdio, and
 * this returns its exit code.
 *
 * @return the exit code of the child the server ran as, or `None` to run in this process
 */
func relaunchWithLargerHeap(logger: Logger): ?Int64 {
    if (getVariable(HEAP_SIZE_VARIABLE).isSome()) {
        return None
    }
    setVariable(HEAP_SIZE_VARIABLE, HEAP_SIZE)
    try {
        relaunch(logger)
    } catch (e: Exception) {
        logger.warn("could not start over with a larger heap: running on the default one",
            [(HEAP_SIZE_VARIABLE, HEAP_SIZE), ("cause", e)])
        None
    }
}

/**
 * `execvp` with the process's own command line: the same program, found the way the editor found
 * it, under the environment just changed.
 *
 * @throws Exception - if `execvp` returns, which it does only when it failed
 */
@When[os != "Windows"]
func relaunch(_: Logger): ?Int64 {
    let args = getCommandLine()
    unsafe {
        let argv = LibC.malloc<CString>(count: args.size + 1)
        for (i in 0..args.size) {
            argv.write(i, LibC.mallocCString(args[i]))
        }
        argv.write(args.size, CString(CPointer()))
        execvp(argv.read(), argv)
    }
    throw Exception("execvp failed")
}

/**
 * Windows replaces no process: the child shares stdin, stdout and stderr, and this waits for it.
 * Before the child starts, this process goes into a job that terminates what is in it when its
 * last handle closes, so the child is born in it; the handle is this process's alone, so the child
 * dies with it however it ends, `TerminateProcess` included (D78). If the job cannot be had, a
 * `WARN`, and a child whose parent is killed lives on until its stdin reaches EOF.
 */
@When[os == "Windows"]
func relaunch(logger: Logger): ?Int64 {
    try {
        KillOnCloseJob().assign(unsafe { GetCurrentProcess() })
    } catch (e: Exception) {
        logger.warn("the server's child will not die with this process", [("cause", e)])
    }
    let child = launch(getCommand(), getCommandLine()[1..], stdIn: ProcessRedirect.Inherit,
        stdOut: ProcessRedirect.Inherit, stdErr: ProcessRedirect.Inherit)
    child.wait()
}

@When[os == "Windows"]
foreign func CreateJobObjectW(attributes: CPointer<Unit>, name: CPointer<UInt16>): CPointer<Unit>

@When[os == "Windows"]
foreign func SetInformationJobObject(job: CPointer<Unit>, infoClass: Int32, info: CPointer<JobExtendedLimits>,
    size: UInt32): Int32

@When[os == "Windows"]
foreign func AssignProcessToJobObject(job: CPointer<Unit>, process: CPointer<Unit>): Int32

@When[os == "Windows"]
foreign func GetCurrentProcess(): CPointer<Unit>

@When[os == "Windows"]
foreign func CloseHandle(handle: CPointer<Unit>): Int32

@When[os == "Windows"]
foreign func GetLastError(): UInt32

/**
 * `JOBOBJECTINFOCLASS`'s `JobObjectExtendedLimitInformation`: the information is a
 * `JobExtendedLimits`.
 */
@When[os == "Windows"]
const JOB_OBJECT_EXTENDED_LIMIT_INFORMATION: Int32 = 9

/**
 * The limit that terminates every process in a job when the job's last handle closes.
 */
@When[os == "Windows"]
const JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE: UInt32 = 0x2000

/**
 * `JOBOBJECT_BASIC_LIMIT_INFORMATION`, nothing but `limitFlags` set.
 */
@When[os == "Windows"]
@C
struct JobBasicLimits {
    var perProcessUserTimeLimit: Int64 = 0
    var perJobUserTimeLimit: Int64 = 0
    var limitFlags: UInt32
    var minimumWorkingSetSize: UIntNative = 0
    var maximumWorkingSetSize: UIntNative = 0
    var activeProcessLimit: UInt32 = 0
    var affinity: UIntNative = 0
    var priorityClass: UInt32 = 0
    var schedulingClass: UInt32 = 0

    init(limitFlags: UInt32) {
        this.limitFlags = limitFlags
    }
}

/**
 * `IO_COUNTERS`: a job's counters, which a limit leaves at zero.
 */
@When[os == "Windows"]
@C
struct IoCounters {
    var readOperationCount: UInt64 = 0
    var writeOperationCount: UInt64 = 0
    var otherOperationCount: UInt64 = 0
    var readTransferCount: UInt64 = 0
    var writeTransferCount: UInt64 = 0
    var otherTransferCount: UInt64 = 0
}

/**
 * `JOBOBJECT_EXTENDED_LIMIT_INFORMATION`, the form of a job's limits that takes
 * `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`.
 */
@When[os == "Windows"]
@C
struct JobExtendedLimits {
    var basicLimits: JobBasicLimits
    var ioInfo: IoCounters = IoCounters()
    var processMemoryLimit: UIntNative = 0
    var jobMemoryLimit: UIntNative = 0
    var peakProcessMemoryUsed: UIntNative = 0
    var peakJobMemoryUsed: UIntNative = 0

    init(limitFlags: UInt32) {
        this.basicLimits = JobBasicLimits(limitFlags)
    }
}

/**
 * A Job Object whose processes are all terminated when its last handle closes. A child does not
 * inherit the handle, so whoever holds this is the only one keeping the job, and the processes in
 * it, alive; a process in a job puts every process it starts from then on in the job too.
 */
@When[os == "Windows"]
class KillOnCloseJob <: Resource {
    private var handle: CPointer<Unit>

    /**
     * @throws Exception - if Windows makes no job or does not set its limit
     */
    init() {
        handle = unsafe { CreateJobObjectW(CPointer(), CPointer()) }
        if (handle.isNull()) {
            throw Exception("CreateJobObjectW failed with error ${unsafe { GetLastError() }}")
        }
        var limits = JobExtendedLimits(JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE)
        let limited = unsafe {
            SetInformationJobObject(handle, JOB_OBJECT_EXTENDED_LIMIT_INFORMATION, inout limits,
                UInt32(sizeOf<JobExtendedLimits>()))
        }
        if (limited == 0) {
            let error = unsafe { GetLastError() }
            close()
            throw Exception("SetInformationJobObject failed with error ${error}")
        }
    }

    /**
     * Puts a process in the job.
     *
     * @param process a handle to it with `PROCESS_SET_QUOTA` and `PROCESS_TERMINATE` access
     * @throws Exception - if Windows refuses
     */
    func assign(process: CPointer<Unit>): Unit {
        if (unsafe { AssignProcessToJobObject(handle, process) } == 0) {
            throw Exception("AssignProcessToJobObject failed with error ${unsafe { GetLastError() }}")
        }
    }

    public func isClosed(): Bool {
        handle.isNull()
    }

    /**
     * Closes the handle: when it was the job's last, every process in the job is terminated.
     */
    public func close(): Unit {
        if (!handle.isNull()) {
            unsafe { CloseHandle(handle) }
            handle = CPointer()
        }
    }
}
