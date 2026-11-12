// CAllocHook: the tests' allocation detector (turntable.md 4.3, built first for the EQ - eq.md 1.5, 1.7 test 5).
//
// macOS's malloc calls `malloc_logger`, when one is set, for every allocation and free in the process - the hook
// Instruments' allocation tracking uses. This one counts only those made on ONE thread, the rendering thread a test
// names: the test runner allocates on its own threads throughout, and a count of the whole process would fail for
// them. A test proves the hook is called with a canary - an allocation made on purpose on the rendering thread -
// before trusting a count of nothing.
//
// Test-only: nothing the app links depends on it. Elsewhere than Apple's platforms it builds to stubs that say they
// can't (`alloc_hook_available` false).

#ifndef CALLOCHOOK_H
#define CALLOCHOOK_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// True where the hook can be installed (macOS).
bool alloc_hook_available(void);

/// Installs the hook, counting nothing until a thread is watched.
void alloc_hook_install(void);
/// Takes it out again.
void alloc_hook_remove(void);

/// From now on, the calling thread's allocations and frees are counted (the counts start at 0).
void alloc_hook_watch_this_thread(void);
/// Stops counting.
void alloc_hook_unwatch(void);

uint64_t alloc_hook_allocations(void);
uint64_t alloc_hook_frees(void);

/// One deliberate malloc and free, in C, on the calling thread: the canary.
void alloc_hook_canary(void);

#ifdef __cplusplus
}
#endif

#endif
