features { os.windows }
package platform

foreign func CreateJobObjectW(attributes: CPointer<Unit>, name: CPointer<UInt16>): CPointer<Unit>

foreign func SetInformationJobObject(job: CPointer<Unit>, infoClass: Int32, info: CPointer<JobExtendedLimits>,
    size: UInt32): Int32

foreign func AssignProcessToJobObject(job: CPointer<Unit>, process: CPointer<Unit>): Int32

foreign func GetCurrentProcess(): CPointer<Unit>

foreign func CloseHandle(handle: CPointer<Unit>): Int32

foreign func GetLastError(): UInt32

/**
 * `JOBOBJECTINFOCLASS`'s `JobObjectExtendedLimitInformation`: the information is a
 * `JobExtendedLimits`.
 */
const JOB_OBJECT_EXTENDED_LIMIT_INFORMATION: Int32 = 9

/**
 * The limit that terminates every process in a job when the job's last handle closes.
 */
const JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE: UInt32 = 0x2000

/**
 * `JOBOBJECT_BASIC_LIMIT_INFORMATION`, nothing but `limitFlags` set.
 */
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
class KillOnCloseJob <: Resource {
    private var handle: CPointer<Unit>

    /**
     * @throws ProcessStartException - if Windows makes no job or does not set its limit
     */
    init() {
        handle = unsafe { CreateJobObjectW(CPointer(), CPointer()) }
        if (handle.isNull()) {
            throw windowsError("CreateJobObjectW")
        }
        var limits = JobExtendedLimits(JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE)
        let limited = unsafe {
            SetInformationJobObject(handle, JOB_OBJECT_EXTENDED_LIMIT_INFORMATION, inout limits,
                UInt32(sizeOf<JobExtendedLimits>()))
        }
        if (limited == 0) {
            let e = windowsError("SetInformationJobObject")
            close()
            throw e
        }
    }

    /**
     * Puts a process in the job.
     *
     * @param process a handle to it with `PROCESS_SET_QUOTA` and `PROCESS_TERMINATE` access
     * @throws ProcessStartException - if Windows refuses
     */
    func assign(process: CPointer<Unit>): Unit {
        if (unsafe { AssignProcessToJobObject(handle, process) } == 0) {
            throw windowsError("AssignProcessToJobObject")
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

func windowsError(what: String): ProcessStartException {
    ProcessStartException("${what} failed with error ${unsafe { GetLastError() }}")
}

func closeHandle(handle: CPointer<Unit>): Unit {
    if (!handle.isNull()) {
        unsafe { CloseHandle(handle) }
    }
}
