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

// ------------------------------------------------------------ the queue (turntable.md 4.3)
//
// A single-producer, single-consumer queue of `capacity` slots (a power of two), whose storage the caller keeps; this
// holds only the two counts. The deck's messages need every one, in order - a hand's knots are a path, not a newest
// value - which the triple buffer can't give. The producer `reserve`s the next slot, writes it, and `commit`s it
// (release); the consumer `peek`s the oldest (acquire), reads it, and `release`s it. A full queue refuses the
// reserve: the producer drops and counts, never waits.

typedef struct audio_fifo audio_fifo;

/// Empty, `capacity` slots - a power of two, at least 2. NULL if it isn't, or out of memory.
audio_fifo *audio_fifo_make(uint32_t capacity);
void audio_fifo_free(audio_fifo *fifo);

uint32_t audio_fifo_capacity(const audio_fifo *fifo);

/// The producer: the slot to write, in `*slot`, and true - or false when the queue is full.
bool audio_fifo_reserve(const audio_fifo *fifo, uint32_t *slot);
/// The producer: the slot reserved is written; the consumer may read it.
void audio_fifo_commit(audio_fifo *fifo);

/// The consumer: the oldest slot written, in `*slot`, and true - or false when there is none.
bool audio_fifo_peek(const audio_fifo *fifo, uint32_t *slot);
/// The consumer: done with the slot peeked; the producer may write it again.
void audio_fifo_release(audio_fifo *fifo);

/// How many are written and not yet released (from either side: a moment's answer).
uint32_t audio_fifo_count(const audio_fifo *fifo);

#ifdef __cplusplus
}
#endif

#endif
