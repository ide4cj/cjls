features {os.windows}
package platform

import std.env.getVariables
import std.fs.Path
import std.io.{InputStream, IOException, OutputStream}

// A piped child on Windows (D87, D91): it reads and writes two pipe handles it inherits, named by number on its
// command line, which `std.process` cannot pass, so it is started by `CreateProcessW` as cjc's own client starts
// the macro server (`MacroEvaluationClient.cpp`), with two differences: it inherits those two handles and stderr
// alone (`PROC_THREAD_ATTRIBUTE_HANDLE_LIST`), never another child's pipe, which would keep it from seeing EOF; and
// it starts suspended, put in a kill-on-close job first, so it dies with this process even in a macro that loops.
// What it prints goes to stderr. None of these functions is `@FastNative`: `ReadFile` and
// `WaitForSingleObject` block (C5).

foreign func CreatePipe(
    read: CPointer<CPointer<Unit>>,
    write: CPointer<CPointer<Unit>>,
    attributes: CPointer<Unit>,
    size: UInt32
): Int32

foreign func SetHandleInformation(handle: CPointer<Unit>, mask: UInt32, flags: UInt32): Int32

foreign func GetStdHandle(which: UInt32): CPointer<Unit>

foreign func DuplicateHandle(
    sourceProcess: CPointer<Unit>,
    source: CPointer<Unit>,
    targetProcess: CPointer<Unit>,
    target: CPointer<CPointer<Unit>>,
    access: UInt32,
    inherit: Int32,
    options: UInt32
): Int32

foreign func InitializeProcThreadAttributeList(
    list: CPointer<Unit>,
    count: UInt32,
    flags: UInt32,
    size: CPointer<UIntNative>
): Int32

foreign func UpdateProcThreadAttribute(
    list: CPointer<Unit>,
    flags: UInt32,
    attribute: UIntNative,
    value: CPointer<CPointer<Unit>>,
    size: UIntNative,
    previous: CPointer<Unit>,
    returned: CPointer<UIntNative>
): Int32

foreign func DeleteProcThreadAttributeList(list: CPointer<Unit>): Unit

foreign func CreateProcessW(
    application: CPointer<UInt16>,
    commandLine: CPointer<UInt16>,
    processAttributes: CPointer<Unit>,
    threadAttributes: CPointer<Unit>,
    inheritHandles: Int32,
    flags: UInt32,
    environment: CPointer<UInt16>,
    directory: CPointer<UInt16>,
    startup: CPointer<StartupInfoEx>,
    information: CPointer<ProcessInformation>
): Int32

foreign func ResumeThread(thread: CPointer<Unit>): UInt32

foreign func TerminateProcess(process: CPointer<Unit>, code: UInt32): Int32

foreign func WaitForSingleObject(handle: CPointer<Unit>, milliseconds: UInt32): UInt32

foreign func ReadFile(
    file: CPointer<Unit>,
    buffer: CPointer<UInt8>,
    size: UInt32,
    read: CPointer<UInt32>,
    overlapped: CPointer<Unit>
): Int32

foreign func WriteFile(
    file: CPointer<Unit>,
    buffer: CPointer<UInt8>,
    size: UInt32,
    written: CPointer<UInt32>,
    overlapped: CPointer<Unit>
): Int32

const HANDLE_FLAG_INHERIT: UInt32 = 0x1

const STD_ERROR_HANDLE: UInt32 = 0xFFFF_FFF4

const DUPLICATE_SAME_ACCESS: UInt32 = 0x2

const PROC_THREAD_ATTRIBUTE_HANDLE_LIST: UIntNative = 0x20002

const CREATE_SUSPENDED: UInt32 = 0x4

const CREATE_UNICODE_ENVIRONMENT: UInt32 = 0x400

const EXTENDED_STARTUPINFO_PRESENT: UInt32 = 0x8_0000

const CREATE_NO_WINDOW: UInt32 = 0x800_0000

const STARTF_USESTDHANDLES: UInt32 = 0x100

const INFINITE: UInt32 = 0xFFFF_FFFF

/**
 * `STARTUPINFOEXW`: `STARTUPINFOW` and the attribute list.
 */
@C
struct StartupInfoEx {
    var cb: UInt32 = 0
    var reserved: CPointer<UInt16> = CPointer()
    var desktop: CPointer<UInt16> = CPointer()
    var title: CPointer<UInt16> = CPointer()
    var x: UInt32 = 0
    var y: UInt32 = 0
    var xSize: UInt32 = 0
    var ySize: UInt32 = 0
    var xCountChars: UInt32 = 0
    var yCountChars: UInt32 = 0
    var fillAttribute: UInt32 = 0
    var flags: UInt32 = 0
    var showWindow: UInt16 = 0
    var reserved2Size: UInt16 = 0
    var reserved2: CPointer<UInt8> = CPointer()
    var stdInput: CPointer<Unit> = CPointer()
    var stdOutput: CPointer<Unit> = CPointer()
    var stdError: CPointer<Unit> = CPointer()
    var attributeList: CPointer<Unit> = CPointer()
}

/** `PROCESS_INFORMATION`. */
@C
struct ProcessInformation {
    var process: CPointer<Unit> = CPointer()
    var thread: CPointer<Unit> = CPointer()
    var processId: UInt32 = 0
    var threadId: UInt32 = 0
}

/**
 * A pipe: its read end, its write end, neither inherited.
 */
func createPipe(): (CPointer<Unit>, CPointer<Unit>) {
    var read = CPointer<Unit>()
    var write = CPointer<Unit>()
    if (
        unsafe {
            CreatePipe(inout read, inout write, CPointer(), 0)
        } ==
            0
    ) {
        throw windowsError("CreatePipe")
    }
    (read, write)
}

/**
 * `units` and a 0, in memory of its own the caller frees.
 */
unsafe func wideString(units: Array<UInt16>): CPointer<UInt16> {
    let p = LibC.malloc<UInt16>(count: units.size + 1)
    for (i in 0..units.size) {
        p.write(i, units[i])
    }
    p.write(units.size, 0)
    p
}

/**
 * What the server writes, read from the end of its pipe this process holds.
 */
class HandleInputStream <: InputStream {
    HandleInputStream(let handle: CPointer<Unit>) {}

    /**
     * What `ReadFile` reads; 0, EOF, when it fails. A read of this end fails when the server has closed its
     * own, which is how its exit shows: `GetLastError`, a call of its own, does not tell why, as the runtime
     * may have set the thread's last error between the two (0 on CI's Windows, not `ERROR_BROKEN_PIPE`).
     */
    public func read(buffer: Array<Byte>): Int64 {
        if (buffer.isEmpty()) {
            return 0
        }
        let size = min(buffer.size, 1 << 16)
        unsafe {
            let memory = LibC.malloc<UInt8>(count: size)
            var read: UInt32 = 0
            let ok = ReadFile(handle, memory, UInt32(size), inout read, CPointer())
            for (i in 0..Int64(read)) {
                buffer[i] = memory.read(i)
            }
            LibC.free(memory)
            if (ok == 0) {
                0
            } else {
                Int64(read)
            }
        }
    }
}

/**
 * What the server reads, written to the end of its pipe this process holds.
 */
class HandleOutputStream <: OutputStream {
    HandleOutputStream(let handle: CPointer<Unit>) {}

    /**
     * @throws IOException - if the pipe fails, the server gone
     */
    public func write(buffer: Array<Byte>): Unit {
        if (buffer.isEmpty()) {
            return
        }
        unsafe {
            let memory = LibC.malloc<UInt8>(count: buffer.size)
            for (i in 0..buffer.size) {
                memory.write(i, buffer[i])
            }
            var at = 0
            while (at < buffer.size) {
                var written: UInt32 = 0
                if (
                    WriteFile(
                        handle,
                        memory + at,
                        UInt32(buffer.size - at),
                        inout written,
                        CPointer()
                    ) ==
                        0
                ) {
                    let error = GetLastError()
                    LibC.free(memory)
                    throw IOException("WriteFile failed with error ${error}")
                }
                at += Int64(written)
            }
            LibC.free(memory)
        }
    }
}

/**
 * The child's process, its job, and the ends of its pipes this process holds, all let go of once it has
 * exited.
 */
class WindowsChild <: PipedChild {
    WindowsChild(
        let process: CPointer<Unit>,
        let job: ?KillOnCloseJob,
        let ownRead: CPointer<Unit>,
        let ownWrite: CPointer<Unit>
    ) {}

    public prop fromChild: InputStream {
        get() {
            HandleInputStream(ownRead)
        }
    }

    public prop toChild: OutputStream {
        get() {
            HandleOutputStream(ownWrite)
        }
    }

    public func wait(): Unit {
        unsafe {
            WaitForSingleObject(process, INFINITE)
        }
        closeHandle(ownRead)
        closeHandle(ownWrite)
        closeHandle(process)
        job?.close()
    }

    public func kill(): Unit {
        unsafe {
            TerminateProcess(process, 1)
        }
    }
}

/**
 * A job `process` is in, which ends it when the job's handle, which no child inherits, closes; `None` if
 * Windows gives none, and the child then exits only when it next reads, at EOF.
 */
func jobFor(process: CPointer<Unit>): ?KillOnCloseJob {
    let job =
        try {
            KillOnCloseJob()
        } catch (_: ProcessStartException) {
            return None
        }
    try {
        job.assign(process)
    } catch (_: ProcessStartException) {}
    job
}

public specific func startPiped(
    program: Path,
    libDirs: Array<Path>,
    args: (ChildPipes) -> Array<String>
): PipedChild {
    // the child reads `childRead` and writes `childWrite`; this process the other ends
    let (childRead, ownWrite) = createPipe()
    let (ownRead, childWrite) = createPipe()
    try {
        let pipes =
            ChildPipes(
                read: "${childRead.toUIntNative()}",
                write: "${childWrite.toUIntNative()}",
                parent: None
            )
        let information =
            createChildProcess(
                windowsCommandLine([program.toString()].concat(args(pipes))),
                windowsEnvironment(getVariables(), libraryPathOf(libDirs)),
                childRead,
                childWrite
            )
        let job = jobFor(information.process)
        let resumed =
            unsafe {
                ResumeThread(information.thread)
            }
        closeHandle(information.thread)
        let child = WindowsChild(information.process, job, ownRead, ownWrite)
        if (resumed == 0xFFFF_FFFF) {
            let e = windowsError("ResumeThread")
            child.kill()
            child.wait()
            throw e
        }
        child
    } catch (e: Exception) {
        closeHandle(ownRead)
        closeHandle(ownWrite)
        throw e
    } finally {
        // the child has its own: with these closed, its exit is EOF here
        closeHandle(childRead)
        closeHandle(childWrite)
    }
}

/**
 * This process's stderr, duplicated so that a child may inherit it; null if there is none.
 */
func inheritableStderr(): CPointer<Unit> {
    unsafe {
        let stderr = GetStdHandle(STD_ERROR_HANDLE)
        // `INVALID_HANDLE_VALUE` is -1
        if (stderr.isNull() || stderr.toUIntNative() == UIntNative.Max) {
            return CPointer<Unit>()
        }
        var duplicate = CPointer<Unit>()
        let current = GetCurrentProcess()
        if (
            DuplicateHandle(
                current,
                stderr,
                current,
                inout duplicate,
                0,
                1,
                DUPLICATE_SAME_ACCESS
            ) ==
                0
        ) {
            return CPointer<Unit>()
        }
        duplicate
    }
}

/**
 * A child of `commandLine` and `environment`, started suspended on `childRead` and `childWrite`, inheriting
 * them and stderr alone.
 */
func createChildProcess(
    commandLine: String,
    environment: Array<UInt16>,
    childRead: CPointer<Unit>,
    childWrite: CPointer<Unit>
): ProcessInformation {
    for (h in [childRead, childWrite]) {
        if (
            unsafe {
                SetHandleInformation(h, HANDLE_FLAG_INHERIT, HANDLE_FLAG_INHERIT)
            } ==
                0
        ) {
            throw windowsError("SetHandleInformation")
        }
    }
    let stderr = inheritableStderr()
    let inherited =
        if (stderr.isNull()) {
            [childRead, childWrite]
        } else {
            [childRead, childWrite, stderr]
        }
    unsafe {
        let handles = LibC.malloc<CPointer<Unit>>(count: inherited.size)
        for (i in 0..inherited.size) {
            handles.write(i, inherited[i])
        }
        var listSize: UIntNative = 0
        InitializeProcThreadAttributeList(CPointer(), 1, 0, inout listSize)
        let listMemory = LibC.malloc<UInt8>(count: Int64(listSize))
        let list = CPointer<Unit>(listMemory)
        let command = wideString(utf16(commandLine))
        let environmentBlock = wideString(environment)
        try {
            if (InitializeProcThreadAttributeList(list, 1, 0, inout listSize) == 0) {
                throw windowsError("InitializeProcThreadAttributeList")
            }
            try {
                if (
                    UpdateProcThreadAttribute(
                        list,
                        0,
                        PROC_THREAD_ATTRIBUTE_HANDLE_LIST,
                        handles,
                        UIntNative(inherited.size) * sizeOf<CPointer<Unit>>(),
                        CPointer(),
                        CPointer()
                    ) ==
                        0
                ) {
                    throw windowsError("UpdateProcThreadAttribute")
                }
                var startup = StartupInfoEx()
                startup.cb = UInt32(sizeOf<StartupInfoEx>())
                startup.flags = STARTF_USESTDHANDLES
                startup.stdOutput = stderr
                startup.stdError = stderr
                startup.attributeList = list
                var information = ProcessInformation()
                if (
                    CreateProcessW(
                        CPointer(),
                        command,
                        CPointer(),
                        CPointer(),
                        1,
                        CREATE_SUSPENDED | CREATE_UNICODE_ENVIRONMENT |
                            EXTENDED_STARTUPINFO_PRESENT |
                            CREATE_NO_WINDOW,
                        environmentBlock,
                        CPointer(),
                        inout startup,
                        inout information
                    ) ==
                        0
                ) {
                    throw windowsError("CreateProcessW")
                }
                information
            } finally {
                DeleteProcThreadAttributeList(list)
            }
        } finally {
            closeHandle(stderr)
            LibC.free(handles)
            LibC.free(listMemory)
            LibC.free(command)
            LibC.free(environmentBlock)
        }
    }
}
