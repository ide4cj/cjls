// Diagnostic helper for the Linux x86_64 SDK 1.3.0-alpha.20261102001050.
// This deliberately inspects internal runtime state; it is not an application API.
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>

extern void *MRT_GetThreadLocalData(void);
extern void *CJ_CJThreadStackAddrGet(void);
extern size_t CJ_CJThreadStackSizeGet(void);

int64_t reportExclusiveStackGuard(void)
{
    // ThreadLocalData::protectAddr is the sixth pointer on this SDK/architecture.
    const uintptr_t *tls = MRT_GetThreadLocalData();
    const uintptr_t guard = tls[5];
    const void *recorded_stack = CJ_CJThreadStackAddrGet();
    fprintf(stderr, "exclusiveScope: recorded coroutine stack=%p, guard=0x%" PRIxPTR "\n",
            recorded_stack, guard);
    if (recorded_stack == NULL) {
        fputs("INCONCLUSIVE: no coroutine was reused in this run\n", stderr);
        return 2;
    }
    const uintptr_t base = (uintptr_t)recorded_stack;
    if (guard >= base && guard - base < CJ_CJThreadStackSizeGet()) {
        fputs("REPRODUCED: exclusiveScope restored a coroutine stack guard\n", stderr);
        return 1;
    }
    fputs("No stale guard observed for the reused coroutine\n", stderr);
    return 0;
}
