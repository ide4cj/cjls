features { user.platform.posix, os.darwin }
package platform

foreign func __error(): CPointer<Int32>

public specific func hostOs(): String {
    "macOS"
}

public specific func hostEnv(): String {
    ""
}

specific func utsnameFieldSize(): Int64 {
    256
}

public specific func sharedLibrarySuffix(): String {
    ".dylib"
}

public specific func libraryPathVariable(): String {
    "DYLD_LIBRARY_PATH"
}

specific func lastErrno(): Int32 {
    unsafe { __error().read() }
}
