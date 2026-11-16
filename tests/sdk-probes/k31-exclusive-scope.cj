// Run with cjProcessorNum=1 so the completed child can enter this processor's pool.
// Exit 1 confirms a coroutine stack guard was restored inside exclusiveScope;
// exit 2 means this run did not reuse a coroutine and is inconclusive.
foreign {
    func reportExclusiveStackGuard(): Int64
}

main(): Int64 {
    let completed = spawn { 42 }
    completed.get()
    exclusiveScope {
        exclusiveScope { 42 }
        unsafe { reportExclusiveStackGuard() }
    }
}
