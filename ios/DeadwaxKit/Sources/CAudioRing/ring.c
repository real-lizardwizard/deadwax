// CAudioRing's few lines: see include/CAudioRing.h. Integers only.

#include "CAudioRing.h"

#include <stdatomic.h>
#include <stdlib.h>

#define AUDIO_TRIPLE_INDEX 3u
#define AUDIO_TRIPLE_FRESH 4u

struct audio_triple {
    /// the middle slot's index, and AUDIO_TRIPLE_FRESH while it holds something published and not yet taken
    _Atomic(uint32_t) middle;
    /// the producer's own (only ever touched under the producers' lock)
    uint32_t back;
    /// the consumer's own (only ever touched by the one rendering)
    uint32_t front;
};

audio_triple *audio_triple_make(void) {
    audio_triple *triple = malloc(sizeof(audio_triple));
    if (triple == NULL) return NULL;
    atomic_init(&triple->middle, 1u);
    triple->back = 2u;
    triple->front = 0u;
    return triple;
}

void audio_triple_free(audio_triple *triple) { free(triple); }

uint32_t audio_triple_back(const audio_triple *triple) { return triple->back; }

bool audio_triple_publish(audio_triple *triple) {
    // release: the slot's contents, written before this, are seen by whoever takes it; acquire: the slot handed back
    // is the consumer's no longer
    uint32_t old = atomic_exchange_explicit(&triple->middle, triple->back | AUDIO_TRIPLE_FRESH, memory_order_acq_rel);
    triple->back = old & AUDIO_TRIPLE_INDEX;
    return (old & AUDIO_TRIPLE_FRESH) != 0;
}

bool audio_triple_take(audio_triple *triple) {
    if ((atomic_load_explicit(&triple->middle, memory_order_relaxed) & AUDIO_TRIPLE_FRESH) == 0) return false;
    // acquire: the producer's writes to the slot taken are seen; release: the front given back is done with
    uint32_t old = atomic_exchange_explicit(&triple->middle, triple->front, memory_order_acq_rel);
    triple->front = old & AUDIO_TRIPLE_INDEX;
    return true;
}

uint32_t audio_triple_front(const audio_triple *triple) { return triple->front; }

struct audio_counters {
    uint32_t count;
    _Atomic(uint64_t) words[];
};

audio_counters *audio_counters_make(uint32_t count) {
    audio_counters *counters = malloc(sizeof(audio_counters) + (size_t)count * sizeof(_Atomic(uint64_t)));
    if (counters == NULL) return NULL;
    counters->count = count;
    for (uint32_t i = 0; i < count; i++) atomic_init(&counters->words[i], 0u);
    return counters;
}

void audio_counters_free(audio_counters *counters) { free(counters); }

void audio_counters_store(audio_counters *counters, uint32_t index, uint64_t value) {
    if (index < counters->count) atomic_store_explicit(&counters->words[index], value, memory_order_relaxed);
}

uint64_t audio_counters_load(const audio_counters *counters, uint32_t index) {
    if (index >= counters->count) return 0;
    // a relaxed load of a const object: C11's atomic_load takes a pointer to non-const before C17's DR 459
    return atomic_load_explicit((_Atomic(uint64_t) *)&counters->words[index], memory_order_relaxed);
}
