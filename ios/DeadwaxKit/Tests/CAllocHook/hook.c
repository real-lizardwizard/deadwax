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

// The byte count: an open-addressed table of the watched thread's live allocations, touched only by that thread
// (the hook returns for every other before it gets here), so plain memory - static, allocating nothing.
#define TABLE_SIZE (1u << 16)
#define TOMBSTONE ((uintptr_t)1)
static _Atomic(bool) counting_bytes;
static uintptr_t table_ptr[TABLE_SIZE];
static uint64_t table_size[TABLE_SIZE];
static int64_t bytes_held;
static int64_t bytes_peak;
static uint64_t bytes_untracked;

static uint32_t slot_of(uintptr_t ptr) { return (uint32_t)(((ptr >> 4) * 0x9E3779B97F4A7C15ull) >> 48) & (TABLE_SIZE - 1); }

static void remember(uintptr_t ptr, uint64_t size) {
    if (ptr == 0) return;
    uint32_t at = slot_of(ptr);
    for (uint32_t probe = 0; probe < TABLE_SIZE; probe++, at = (at + 1) & (TABLE_SIZE - 1)) {
        if (table_ptr[at] == 0 || table_ptr[at] == TOMBSTONE) {
            table_ptr[at] = ptr;
            table_size[at] = size;
            bytes_held += (int64_t)size;
            if (bytes_held > bytes_peak) bytes_peak = bytes_held;
            return;
        }
    }
    bytes_untracked++;
}

static void forget(uintptr_t ptr) {
    if (ptr == 0) return;
    uint32_t at = slot_of(ptr);
    for (uint32_t probe = 0; probe < TABLE_SIZE; probe++, at = (at + 1) & (TABLE_SIZE - 1)) {
        if (table_ptr[at] == 0) return;
        if (table_ptr[at] == ptr) {
            table_ptr[at] = TOMBSTONE;
            bytes_held -= (int64_t)table_size[at];
            return;
        }
    }
}

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
    if (!atomic_load_explicit(&counting_bytes, memory_order_relaxed)) return;
    // libmalloc's arguments: an allocation (zone, size, -, pointer); a free (zone, pointer); a realloc - both bits -
    // (zone, old pointer, new size, new pointer)
    if ((type & LOG_ALLOCATE) && (type & LOG_DEALLOCATE)) {
        forget(arg2);
        remember(result, arg3);
    } else if (type & LOG_ALLOCATE) {
        remember(result, arg2);
    } else if (type & LOG_DEALLOCATE) {
        forget(arg2);
    }
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

void alloc_hook_bytes_begin(void) {
    atomic_store(&counting_bytes, false);
    for (uint32_t i = 0; i < TABLE_SIZE; i++) table_ptr[i] = 0;
    bytes_held = 0;
    bytes_peak = 0;
    bytes_untracked = 0;
    atomic_store(&counting_bytes, true);
}

void alloc_hook_bytes_end(void) { atomic_store(&counting_bytes, false); }

int64_t alloc_hook_bytes_held(void) { return bytes_held; }

int64_t alloc_hook_bytes_peak(void) { return bytes_peak; }

uint64_t alloc_hook_bytes_untracked(void) { return bytes_untracked; }

void alloc_hook_bytes_canary(uint64_t size) {
    char *volatile canary = malloc((size_t)size);
    if (canary) {
        for (uint64_t i = 0; i < size; i += 4096) canary[i] = 1;
    }
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
void alloc_hook_bytes_begin(void) {}
void alloc_hook_bytes_end(void) {}
int64_t alloc_hook_bytes_held(void) { return 0; }
int64_t alloc_hook_bytes_peak(void) { return 0; }
uint64_t alloc_hook_bytes_untracked(void) { return 0; }
void alloc_hook_bytes_canary(uint64_t size) { (void)size; }

#endif
