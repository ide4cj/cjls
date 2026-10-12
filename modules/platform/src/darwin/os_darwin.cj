features { user.platform.posix, os.darwin }
package platform

foreign func __error(): CPointer<Int32>

public specific func hostOs(): String {
    "macOS"
}

public specific func hostEnv(): String {
    ""
}

specific func lastErrno(): Int32 {
    unsafe { __error().read() }
}
