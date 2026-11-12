// CAllocHook: see include/CAllocHook.h.

#include "CAllocHook.h"

#if defined(__APPLE__)

#include <pthread.h>
#include <stdatomic.h>
#include <stdlib.h>

// libmalloc's own declaration (its stack_logging.h, not a public header): called for every allocation and free while
// set. `type` carries 2 for an allocation and 4 for a free (both for a realloc).
typedef void(malloc_logger_t)(uint32_t type, uintptr_t arg1, uintptr_t arg2, uintptr_t arg3, uintptr_t result,
                              uint32_t num_hot_frames_to_skip);
extern malloc_logger_t *malloc_logger;

#define LOG_ALLOCATE 2u
#define LOG_DEALLOCATE 4u

static _Atomic(uintptr_t) watched;
static _Atomic(uint64_t) allocations;
static _Atomic(uint64_t) frees;

// Called on every thread of the process, so it allocates nothing and takes no lock: a thread's identity and two
// counters.
static void hook(uint32_t type, uintptr_t arg1, uintptr_t arg2, uintptr_t arg3, uintptr_t result, uint32_t skip) {
    (void)arg1;
    (void)arg2;
    (void)arg3;
    (void)result;
    (void)skip;
    uintptr_t self = (uintptr_t)pthread_self();
    if (self != atomic_load_explicit(&watched, memory_order_relaxed)) return;
    if (type & LOG_ALLOCATE) atomic_fetch_add_explicit(&allocations, 1, memory_order_relaxed);
    if (type & LOG_DEALLOCATE) atomic_fetch_add_explicit(&frees, 1, memory_order_relaxed);
}

bool alloc_hook_available(void) { return true; }

void alloc_hook_install(void) { malloc_logger = hook; }

void alloc_hook_remove(void) {
    malloc_logger = NULL;
    atomic_store(&watched, 0);
}

void alloc_hook_watch_this_thread(void) {
    atomic_store(&allocations, 0);
    atomic_store(&frees, 0);
    atomic_store(&watched, (uintptr_t)pthread_self());
}

void alloc_hook_unwatch(void) { atomic_store(&watched, 0); }

uint64_t alloc_hook_allocations(void) { return atomic_load(&allocations); }

uint64_t alloc_hook_frees(void) { return atomic_load(&frees); }

void alloc_hook_canary(void) {
    // through a volatile pointer, so the compiler can't take the pair out
    void *volatile canary = malloc(16);
    free(canary);
}

#else

bool alloc_hook_available(void) { return false; }
void alloc_hook_install(void) {}
void alloc_hook_remove(void) {}
void alloc_hook_watch_this_thread(void) {}
void alloc_hook_unwatch(void) {}
uint64_t alloc_hook_allocations(void) { return 0; }
uint64_t alloc_hook_frees(void) { return 0; }
void alloc_hook_canary(void) {}

#endif
