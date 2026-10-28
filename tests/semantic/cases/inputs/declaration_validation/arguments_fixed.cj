package audit
@Frozen func f() {}
@C struct S {}
@C func generic() {}
foreign {
    @CallingConv[CDECL] func missing(): Unit
    @CallingConv[CDECL] func g(): Unit
    @CallingConv[CDECL] func h(): Unit
}
