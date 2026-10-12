features { user.platform.posix, os.linux }
package platform

foreign func __errno_location(): CPointer<Int32>

public specific func hostOs(): String {
    "Linux"
}

public specific func hostEnv(): String {
    "gnu"
}

specific func lastErrno(): Int32 {
    unsafe { __errno_location().read() }
}
