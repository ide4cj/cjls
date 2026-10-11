package cjls

@When[os == "Windows"]
import std.unittest.*
@When[os == "Windows"]
import std.unittest.testmacro.*
@When[os == "Windows"]
import std.process.{launch, ProcessRedirect}

@When[os == "Windows"]
@Test
class JobExtendedLimitsTest {
    @TestCase
    func isAsLargeAsWindowsX64Struct() {
        // act
        let size = sizeOf<JobExtendedLimits>()

        // assert
        @Expect(size, 144)
    }

    @TestCase
    func holdsTheLimitFlagsWhereWindowsReadsThem() {
        // arrange
        let limits = unsafe { LibC.malloc<JobExtendedLimits>() }

        // act
        let flags = unsafe {
            limits.write(JobExtendedLimits(JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE))
            // `LimitFlags` is a `DWORD` 16 bytes in: after two `LARGE_INTEGER`s
            let read = CPointer<UInt32>(limits).read(4)
            LibC.free(limits)
            read
        }

        // assert
        @Expect(flags, JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE)
    }
}

@When[os == "Windows"]
foreign func OpenProcess(access: UInt32, inheritHandle: Int32, processId: UInt32): CPointer<Unit>

@When[os == "Windows"]
const PROCESS_TERMINATE: UInt32 = 0x0001

@When[os == "Windows"]
const PROCESS_SET_QUOTA: UInt32 = 0x0100

@When[os == "Windows"]
@Test
class KillOnCloseJobTest {
    @TestCase
    func closingTheLastHandleTerminatesTheProcessesInTheJob() {
        // arrange: `cmd` reads commands from a stdin that never ends, since its pipe stays open
        let child = launch("cmd.exe", [], stdIn: ProcessRedirect.Pipe, stdOut: ProcessRedirect.Discard,
            stdErr: ProcessRedirect.Discard)
        let job = KillOnCloseJob()
        let process = unsafe { OpenProcess(PROCESS_SET_QUOTA | PROCESS_TERMINATE, 0, UInt32(child.pid)) }
        @Assert(!process.isNull())
        job.assign(process)
        unsafe { CloseHandle(process) }

        // act
        job.close()

        // assert: `wait` returns, which it does only once the child is gone
        child.wait()
        @Expect(job.isClosed())
        @Expect(!child.isAlive())
    }
}
