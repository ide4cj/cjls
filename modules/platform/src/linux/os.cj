features { user.platform.posix, os.linux }
package platform

foreign func __errno_location(): CPointer<Int32>

public specific func hostOs(): String {
    "Linux"
}

public specific func hostEnv(): String {
    "gnu"
}

public specific func sharedLibrarySuffix(): String {
    ".so"
}

public specific func libraryPathVariable(): String {
    "LD_LIBRARY_PATH"
}

specific func lastErrno(): Int32 {
    unsafe { __errno_location().read() }
}
