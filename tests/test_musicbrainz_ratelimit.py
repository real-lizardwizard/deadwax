"""
The MusicBrainz rate limiter takes turns (2.0.0-player.55, "search like Apple Music").

RateLimit.wait() keeps deadwax inside MusicBrainz's budget - at most four requests in any five seconds.
Before this its waiters each read the same oldest send, computed the same wake time and fired together:
six sends in one five-second window, measured by the design's simulation - and the app's Search asks three
kinds at once, which would make that the normal case. wait() now runs under an asyncio.Lock held across its
sleep, so waiters take turns:

- eight waiters behind four recent sends, on a clock of the test's own, never put more than four in any five
  seconds;
- a waiter cancelled while it sleeps (a search the page abandoned) lets the lock go and takes no turn;
- the lock belongs to the running event loop: MusicBrainzClient.rate_limit is a class attribute shared by every
  loop in the process (each asyncio.run, each TestClient), and a lock that waited in one loop raises
  RuntimeError when contended from another - so one RateLimit contended from two asyncio.runs raises nothing.
"""

import asyncio
import heapq
import itertools
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src.api.musicbrainz_endpoint import RateLimit  # noqa: E402


class Clock:
    """Virtual time: sleepers wake in order as the test moves the clock to the next of them - concurrency as it is,
    every waiter asleep at once, and nobody waiting a real second."""

    def __init__(self, now=1000.0):
        self.now = now
        self.sleepers = []
        self.order = itertools.count()

    def monotonic(self):
        return self.now

    async def sleep(self, seconds):
        future = asyncio.get_running_loop().create_future()
        heapq.heappush(self.sleepers, (self.now + max(0.0, seconds), next(self.order), future))
        await future

    async def run(self, tasks):
        """Until every task is done: let them all run as far as they can, then wake the next sleeper."""
        while not all(task.done() for task in tasks):
            for _ in range(20):
                await asyncio.sleep(0)
            while self.sleepers and self.sleepers[0][2].cancelled():
                heapq.heappop(self.sleepers)
            if not self.sleepers:
                continue
            wake, _, future = heapq.heappop(self.sleepers)
            self.now = max(self.now, wake)
            future.set_result(None)


def limiter_on(clock, recent=4):
    limiter = RateLimit()
    limiter.clock = clock.monotonic
    limiter.sleep = clock.sleep
    for n in range(recent):
        limiter.request_times.append(clock.now - 0.1 * (recent - n))
    return limiter


def most_in_any_window(times, window=5.0):
    times = sorted(times)
    return max((sum(1 for t in times if start <= t < start + window) for start in times), default=0)


def test_eight_waiters_behind_four_recent_sends_never_put_more_than_four_in_any_window():
    clock = Clock()
    limiter = limiter_on(clock)
    sent = list(limiter.request_times)

    async def go():
        async def one():
            await limiter.wait()
            sent.append(clock.now)

        tasks = [asyncio.ensure_future(one()) for _ in range(8)]
        await clock.run(tasks)

    asyncio.run(go())
    assert len(sent) == 12, "every waiter had its turn"
    assert most_in_any_window(sent) <= RateLimit.max_requests, sent
    #? and they did go: the last of the eight within three windows of the first recent send
    assert sent[-1] - sent[0] < 3 * RateLimit.time_window


def test_a_waiter_cancelled_while_it_sleeps_gives_its_turn_back():
    clock = Clock()
    limiter = limiter_on(clock)
    before = list(limiter.request_times)

    async def go():
        sleeping = asyncio.ensure_future(limiter.wait())
        queued = asyncio.ensure_future(limiter.wait())
        for _ in range(20):
            await asyncio.sleep(0)
        assert not sleeping.done() and not queued.done(), "the first asleep holding the lock, the second waiting its turn"
        sleeping.cancel()
        await clock.run([queued])
        assert sleeping.cancelled()

    asyncio.run(go())
    assert len(limiter.request_times) == 4
    assert list(limiter.request_times)[:3] == before[1:], "one turn taken - the queued waiter's, never the cancelled one's"


def test_one_limiter_contended_from_two_event_loops_raises_nothing():
    """The class-attribute limiter is shared by every loop in the process: a lock bound to the first loop it waited in
    would raise RuntimeError the moment a waiter in the second contended it."""
    limiter = RateLimit()
    for _ in range(4):
        limiter.request_times.append(0.0)  # long ago: nobody sleeps, but the lock is still contended

    async def contend():
        async def hold():
            async with limiter._turn():
                await asyncio.sleep(0.01)

        await asyncio.gather(hold(), limiter.wait(), limiter.wait())

    asyncio.run(contend())
    asyncio.run(contend())
    assert len(limiter.request_times) == 4
