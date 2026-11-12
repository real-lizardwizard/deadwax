// CAudioRing: the C11 atomics a real-time render needs and Swift can't give before iOS 18 (Synchronization's
// Atomic) - notes/ios-specs/eq.md 1.6 and 8's question 1; turntable.md 4.3 uses it for the deck's rings.
//
// Indices and bits only: no floating point anywhere in this target (clang contracts `a * b + c` into one rounding by
// default, which Swift never does - turntable.md 4.2). A Double crosses it as its bit pattern. Plain C11
// <stdatomic.h>, nothing Apple's, so it builds on Linux too.
//
// Each object is made and freed off the audio thread (`_make` mallocs, `_free` frees); every other call is
// wait-free, allocates nothing and takes no lock.

#ifndef CAUDIORING_H
#define CAUDIORING_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// ------------------------------------------------------------ the triple buffer (eq.md 1.6)
//
// Three slots, whose storage the caller keeps; this holds which is which. The producer (one at a time - the caller
// serialises producers) writes the BACK slot, then `publish` swaps back and middle with a "fresh" bit, in one atomic
// exchange (acquire-release). The consumer, at a block's start, `take`s: if the bit is set it swaps front and middle
// the same way and owns the new front. The newest always wins; anything published in between is never seen.

typedef struct audio_triple audio_triple;

/// Front 0, middle 1, back 2, nothing fresh. NULL if out of memory.
audio_triple *audio_triple_make(void);
void audio_triple_free(audio_triple *triple);

/// The producer's slot: write it, then publish.
uint32_t audio_triple_back(const audio_triple *triple);

/// The back slot becomes the middle, marked fresh; the producer's back is now the old middle. True when the old
/// middle was still fresh - published and never taken, so coalesced.
bool audio_triple_publish(audio_triple *triple);

/// The consumer: true when something fresh was there, which is now the front slot.
bool audio_triple_take(audio_triple *triple);

/// The consumer's slot: what it last took.
uint32_t audio_triple_front(const audio_triple *triple);

// ------------------------------------------------------------ counters
//
// 64-bit words written by one thread and read by any (relaxed: each word is whole when read, the set of them is not
// a snapshot). For a render's counts, and a Double's bits.

typedef struct audio_counters audio_counters;

/// `count` words, each 0. NULL if out of memory.
audio_counters *audio_counters_make(uint32_t count);
void audio_counters_free(audio_counters *counters);

void audio_counters_store(audio_counters *counters, uint32_t index, uint64_t value);
uint64_t audio_counters_load(const audio_counters *counters, uint32_t index);

#ifdef __cplusplus
}
#endif

#endif
