/**
 * The record's voice AS IT WAS in 2.0.0-player.24 (lib/deckVoice.ts at bef9424, compiled to CommonJS by
 * tsc, its comments kept) - frozen, for ui/test/decksound.sim.cjs to show the warble James heard in the
 * same harness the voice of today passes ("THE WARBLE"): the adaptive fit that fell back to a 0.1 s
 * parabola read at its newest end whenever the hand's speed changed, played 50 ms behind, steered over
 * 40 ms. Nothing in the app loads this file; don't edit it - it is a record of what shipped.
 */
"use strict";
/**
 * The record's own sound (2.0.0-player.14): what the turntable plays while a hand turns the record,
 * while a flick coasts, and while a pause winds it down - pure, so ui/test/deck.sim.cjs and
 * ui/test/decksound.sim.cjs run it as it runs in the browser.
 *
 * A SEPARATE sound path. The player's own audio element is never connected to Web Audio - a
 * createMediaElementSource is what breaks locked playback on an iPhone - so normal playback is
 * exactly what it was, bit for bit. This sound is a stretch of the song round the playhead, decoded
 * from a FLAC window deadwax cuts (src/flac_window.py), and read here at a SIGNED, fractional rate: 1
 * is the song, 0 is silence - a record held still makes no sound - and negative runs it backwards.
 * Outside the window it is silent. What runs these functions is an AudioWorklet, on an audio thread of
 * its own, wherever the page can have one - or, where it can't (a page that isn't on HTTPS: the browser
 * gives AudioWorklet to secure pages only), a ScriptProcessorNode on the page's main thread
 * (player/deck.ts, 2.0.0-player.16). One DSP, two hosts: nothing about the sound differs but where it
 * runs - and, on the main thread, a constant 43 ms later (SCRIPT_LAG_BLOCKS, deck.ts's startScript).
 *
 *  - THE PATH (2.0.0-player.24). What the voice follows is a path through time: where the record is in
 *    the song at each moment of the audio context's clock - the hand's own samples, each with the time
 *    the pointer event gives it (`hand`, as they come, never one a frame); a coast's, a wind-down's, the
 *    motor's and the handover's positions and speeds as the page works them out (`drive`); and where the
 *    sound was taken up (`take`). Every time on it is mapped onto the context's clock by ONE smooth
 *    mapping (lib/deckClock.ts) - never a `currentTime` read per message, whose steps were what made the
 *    sound warble. The voice keeps them as knots in a small ring and plays the path a FIXED delay behind
 *    (HAND_DELAY_S, 50 ms: `delay`), so the next knot has always arrived - it interpolates between real
 *    ones rather than guessing ahead. Between two knots the path's place is a cubic Hermite through their
 *    places and speeds - continuous in speed. A hand sample's place and speed are fitted to its
 *    neighbours (voiceCommand's `place`): the longest straight line back over SPANS that still agrees
 *    with every shorter one and with a parabola over CURVE_S, to within AGREE of the spread the jitter
 *    measured in the samples gives - so a finger's jitter (a millisecond or so of the song, which straight
 *    through would be a few per cent of pitch) averages out while the hand is steady, however heavy the
 *    finger or near the spindle, and a hand that changes is followed closely; a coast's are exact. The
 *    speed it reads at is the path's: its two knots' speeds between them, and what the chord between
 *    their places asks beyond that as much as the hand wasn't steady there (`knotSteady`) - where it was,
 *    that ask is only jitter. Past the last knot: a drive runs on along its own curve until it runs out
 *    (`until`); a hand runs on EXTRAPOLATE_S, slowing to still, then holds - a hand that stops sends
 *    nothing, and a record held still is silent. A hand that stayed still past REST_S and moves again
 *    starts from where the path stopped - unless it is where its speed would have had it, samples having
 *    gone missing (MISSED_S, KEPT_ON); a plan after a rest sets off from there too. A hand sample older
 *    than the record's own motion the path has after it (a coast's frames) takes the path from its moment.
 *  - The rate it reads at is steered to the path: the path's speed and how far the read head is from
 *    the path's place (FOLLOW_S), smoothed by a one-pole filter of SMOOTH_S (10 ms) a sample -
 *    critically damped together - so a change of speed never steps; and the read head is a running sum
 *    of it, so nothing ever jumps.
 *  - Its loudness fades in and out (`take`, `fade`, `stop`) rather than switching, and fades at the
 *    window's two edges (EDGE_S).
 *  - A DC blocker (10 Hz) on the way out: a record held still reads one sample over and over, a
 *    constant, which this takes down to silence - and anything a slow turn pitches down below
 *    hearing goes with it.
 *  - Read with four-point (Catmull-Rom) interpolation, so the song at speed 1 - the handover after a
 *    coast, the start of a wind-down - sounds as the song does, not dulled.
 *
 * The four functions the worklet runs - newVoiceState, voiceCommand, renderVoice and voiceReport - are
 * written SELF-CONTAINED (no imports, no module constants, no helpers outside themselves, nor one
 * another), because the worklet's module is made from their own source text (voiceWorkletSource): an
 * AudioWorklet runs in a scope of its own, and the page's bundle can't be imported into it. The
 * main-thread voice calls the very same four.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.HAND_DELAY_S = exports.REPORTS_PER_SECOND = exports.VOICE_PROCESSOR = void 0;
exports.newVoiceState = newVoiceState;
exports.voiceCommand = voiceCommand;
exports.renderVoice = renderVoice;
exports.voiceReport = voiceReport;
/** The worklet's name, as registerProcessor() and new AudioWorkletNode() say it. */
exports.VOICE_PROCESSOR = 'deadwax-deck-voice';
/** How many times a second the voice says where it is - either host (voiceReport). */
exports.REPORTS_PER_SECOND = 30;
/**
 * How far behind the record's path the voice plays, in seconds (2.0.0-player.24): long enough that at
 * 60 pointer samples a second, with their delivery and the sample after them for the fit, the knot after
 * any moment it plays has always arrived - so it interpolates between real samples, never guesses ahead
 * of them - and short enough to be a latency, not an echo. A constant: the record's sound is this much
 * later than the hand, the coast and the wind-down alike, and nothing else moves. The literal is in
 * newVoiceState (the voice's functions name nothing outside themselves); deck.sim holds the two equal.
 */
exports.HAND_DELAY_S = 0.05;
/** A voice at rest: silent, nowhere in particular, nothing to play, no path. */
function newVoiceState() {
    //? the path's knots: 64 is more than half a second of a hand sampled at 120 Hz - more than the fit (0.4
    //? s at most) and the delay ever look back over; at 240 Hz a fit takes what the ring still holds
    const KNOTS = 64;
    return {
        pos: 0, rate: 0, gain: 0, gainTarget: 0, gainAlpha: 0.01, driving: false, delay: 0.05,
        knotTime: new Float64Array(KNOTS), knotAt: new Float64Array(KNOTS), knotPos: new Float64Array(KNOTS),
        knotRate: new Float64Array(KNOTS), knotAccel: new Float64Array(KNOTS), knotUntil: new Float64Array(KNOTS),
        knotHand: new Uint8Array(KNOTS), knotSteady: new Float64Array(KNOTS), first: 0, end: 0, cursor: 0,
        window: null, lastIn: [0, 0], lastOut: [0, 0], counted: 0,
    };
}
/** A message from the page, applied as of context time `now`. */
function voiceCommand(state, message, now, sampleRate) {
    //? a one-pole filter's step for a time constant, per sample
    const alpha = (seconds) => 1 - Math.exp(-1 / (Math.max(seconds, 1e-4) * sampleRate));
    //? a fade in or a stop: a few milliseconds, so it never clicks
    const QUICK_S = 0.003;
    //? a hand sample is fitted to the samples up to this far after it (which must have come before the
    //? voice plays it: delay - a sample's spacing - its delivery); to a curve over the last CURVE_S, and to
    //? straight lines back over each of SPANS, shortest first, each kept while it agrees with every
    //? shorter one (and the curve) to within AGREE of that one's own spread - the spread worked out from
    //? the jitter measured in the samples themselves, never below JITTER_FLOOR_S (`place`)
    const SMOOTH_AFTER_S = 0.02;
    const CURVE_S = 0.1;
    const SPANS = [0.1, 0.15, 0.2, 0.3, 0.4];
    const AGREE = 3.5;
    const JITTER_FLOOR_S = 0.0001;
    //? a hand sample further than this after the one before it: the hand rested between them - unless, no
    //? more than MISSED_S after it, it is where the hand's speed would have it by then, to within KEPT_ON of
    //? how far that is (or KEPT_S): then samples went missing, and the hand kept moving through them
    const REST_S = 0.04;
    const MISSED_S = 0.1;
    const KEPT_ON = 0.25;
    const KEPT_S = 0.003;
    //? how far the path runs on past a hand's last sample, slowing to still (renderVoice's own)
    const EXTRAPOLATE_S = 0.02;
    //? a hand moving again after a rest started off within this of its first sample: a sample's spacing
    const RESUME_S = 0.017;
    const size = state.knotTime.length;
    const t = state.knotTime, at = state.knotAt, pos = state.knotPos, rate = state.knotRate;
    const accel = state.knotAccel, until = state.knotUntil, hand = state.knotHand, steady = state.knotSteady;
    //? a knot added at the end - the oldest let go of when the ring is full
    const add = (time, where, speed, change, end, isHand) => {
        if (state.end - state.first >= size)
            state.first += 1;
        const k = state.end % size;
        t[k] = time;
        at[k] = where;
        pos[k] = where;
        rate[k] = speed;
        accel[k] = change;
        until[k] = end;
        hand[k] = isHand;
        steady[k] = 0;
        state.end += 1;
        if (state.cursor < state.first)
            state.cursor = state.first;
    };
    //? a hand sample's place and speed, from it and its neighbours (`place`) - and where a resting hand set
    //? off from, when it is the first sample after the rest (`settle`)
    const fit = (i) => {
        place(i);
        settle(i);
    };
    //? where a resting hand set off from (a knot of kind 2, just before the first sample after the rest):
    //? still until as late as that sample's place and speed allow without the path ever stepping back to
    //? reach it - a sample's spacing before it at most (RESUME_S), at once if it hasn't moved on yet
    const settle = (i) => {
        const j = i - 1;
        if (j - 1 < state.first || hand[j % size] !== 2)
            return;
        const k = i % size;
        const ahead = pos[k] - pos[j % size];
        const lead = rate[k] * ahead > 0 ? Math.min(RESUME_S, (3 * ahead) / rate[k]) : 0;
        t[j % size] = Math.max(t[(j - 1) % size], t[k] - lead);
    };
    //? A hand sample's place and speed, from it and its neighbours - and how steady the hand was there
    //? (`knotSteady`). A least-squares line over a long stretch averages a finger's jitter out of the
    //? pitch, but reads a hand that speeds up, slows or turns back late; a short one, or a curve, follows
    //? that and carries the jitter. So it takes the LONGEST that is still true to the hand (review of
    //? 2.0.0-player.24: the line was kept or dropped on a fixed 3 ms, so jitter a little past it - a
    //? heavier finger, a grip nearer the spindle - fell to a 0.1 s parabola and the pitch wavered): the
    //? curve over the last CURVE_S, then lines back over each of SPANS, shortest first, each kept while its
    //? place and speed lie within AGREE spreads of every shorter one's - a spread worked out from the
    //? jitter measured in these very samples (each one's distance from the line between its neighbours),
    //? so it scales with the finger and the radius rather than switching on a number. A hand that is
    //? steady keeps the longest; one that is changing stops at the stretch that still agrees, or the curve.
    //? The hand's own samples only: back no further than the knot its run began from (a take, a coast's
    //? last frame - the record's motion before the hand). Steadiness is which of SPANS the line chosen is,
    //? 0 for the shortest to 1 for the longest - 0 for the curve, and for a run's first sample
    const place = (i) => {
        const k = i % size;
        const ti = t[k];
        let from = i;
        for (let j = i - 1; j >= state.first && hand[j % size] === 1 && ti - t[j % size] <= SPANS[SPANS.length - 1]; j--)
            from = j;
        let to = i;
        for (let j = i + 1; j < state.end && hand[j % size] === 1 && t[j % size] - ti <= SMOOTH_AFTER_S; j++)
            to = j;
        steady[k] = 0;
        if (to === from) {
            //? its run's only sample (the hand's first, as it takes the record): still, until more come
            pos[k] = at[k];
            rate[k] = 0;
            return;
        }
        //? the jitter: for jitter alone, a sample's distance from the line between its neighbours has
        //? 1 + w^2 + (1 - w)^2 times its variance
        let e2 = 0, ne = 0;
        for (let j = from + 1; j < to; j++) {
            const t0 = t[(j - 1) % size], t2 = t[(j + 1) % size];
            const w = (t2 - t[j % size]) / (t2 - t0);
            const e = at[j % size] - (w * at[(j - 1) % size] + (1 - w) * at[(j + 1) % size]);
            e2 += (e * e) / (1 + w * w + (1 - w) * (1 - w));
            ne += 1;
        }
        const jitter = Math.max(JITTER_FLOOR_S * JITTER_FLOOR_S, ne > 0 ? e2 / ne : 0);
        //? what a longer stretch must agree with: every shorter estimate's place and speed, give or take AGREE
        //? of its spread - the intersection of those, as it narrows
        let lowP = -Infinity, highP = Infinity, lowV = -Infinity, highV = Infinity;
        let found = false;
        //? the curve: x = a + b u + c u^2 by least squares, u the time from this sample in CURVE_S - with four
        //? samples or more to mean anything
        let s0 = 0, s1 = 0, s2 = 0, s3 = 0, s4 = 0, x0 = 0, x1 = 0, x2 = 0;
        for (let j = from; j <= to; j++) {
            const u = (t[j % size] - ti) / CURVE_S;
            if (u < -1)
                continue;
            const x = at[j % size];
            const u2 = u * u;
            s0 += 1;
            s1 += u;
            s2 += u2;
            s3 += u2 * u;
            s4 += u2 * u2;
            x0 += x;
            x1 += u * x;
            x2 += u2 * x;
        }
        if (s0 >= 4) {
            const m0 = s2 * s4 - s3 * s3, m1 = s1 * s4 - s2 * s3, m2 = s1 * s3 - s2 * s2;
            const det = s0 * m0 - s1 * m1 + s2 * m2;
            if (Math.abs(det) > 1e-9) {
                const p = (x0 * m0 - s1 * (x1 * s4 - s3 * x2) + s2 * (x1 * s3 - s2 * x2)) / det;
                const v = (s0 * (x1 * s4 - s3 * x2) - x0 * m1 + s2 * (s1 * x2 - x1 * s2)) / det / CURVE_S;
                const spreadP = Math.sqrt((jitter * m0) / det), spreadV = Math.sqrt((jitter * (s0 * s4 - s2 * s2)) / det) / CURVE_S;
                pos[k] = p;
                rate[k] = v;
                found = true;
                lowP = p - AGREE * spreadP;
                highP = p + AGREE * spreadP;
                lowV = v - AGREE * spreadV;
                highV = v + AGREE * spreadV;
            }
        }
        //? the lines, their sums gathered newest sample first, so each longer stretch adds to the last
        let sw = 0, ss = 0, sss = 0, sx = 0, ssx = 0;
        let j = to;
        for (let n = 0; n < SPANS.length; n++) {
            for (; j >= from && ti - t[j % size] <= SPANS[n]; j--) {
                const sj = t[j % size] - ti;
                const x = at[j % size];
                sw += 1;
                ss += sj;
                sss += sj * sj;
                sx += x;
                ssx += sj * x;
            }
            const det = sw * sss - ss * ss;
            if (!(det > 1e-12))
                continue;
            const p = (sss * sx - ss * ssx) / det;
            const v = (sw * ssx - ss * sx) / det;
            if (p < lowP || p > highP || v < lowV || v > highV)
                break;
            pos[k] = p;
            rate[k] = v;
            found = true;
            steady[k] = n / (SPANS.length - 1);
            const spreadP = Math.sqrt((jitter * sss) / det), spreadV = Math.sqrt((jitter * sw) / det);
            lowP = Math.max(lowP, p - AGREE * spreadP);
            highP = Math.min(highP, p + AGREE * spreadP);
            lowV = Math.max(lowV, v - AGREE * spreadV);
            highV = Math.min(highV, v + AGREE * spreadV);
        }
        if (!found)
            steady[k] = 0;
    };
    //? a knot coming after a hand's last sample, further on than REST_S: the hand rested since. The path ran
    //? on from that sample and stopped (renderVoice's run-on, exactly) - a knot there says so, so what comes
    //? next starts from where it stopped, not from a curve swung across the gap; and what set off again did
    //? so from there, still until then - a hand moving again just before its first sample (a knot of kind 2,
    //? its time settled by `settle`), a plan (the release after a rest) at its own moment. That plan starts
    //? where the hand let go, which the run-on went past: the path steps back to it as it sets off, and the
    //? steering takes that up as it goes on (FOLLOW_S) - the record slower for a moment, never back (review
    //? of 2.0.0-player.24: a curve from the run-on's end back to the plan's start, across the rest, ran the
    //? sound backwards at -0.7x on a release 45 ms after the last move). Not a rest at all: a hand sample
    //? where the hand's speed at the last would have it by then - samples went missing (a busy page, no
    //? coalesced events) and the hand kept moving, so the path runs on through the gap (review: two missed
    //? samples at 1x read as a stop - 0.14x, then 2.2x)
    const rested = (time, where, moving) => {
        const last = state.end - 1;
        if (last < state.first || hand[last % size] !== 1)
            return;
        const k = last % size;
        const gap = time - t[k];
        if (gap <= REST_S)
            return;
        const p = pos[k], v = rate[k];
        if (moving && gap <= MISSED_S && Math.abs(where - p - v * gap) <= Math.max(KEPT_S, KEPT_ON * Math.abs(v * gap)))
            return;
        const stopped = t[k] + EXTRAPOLATE_S, there = p + (v * EXTRAPOLATE_S) / 2;
        add(stopped, there, 0, 0, Infinity, 0);
        if (moving)
            add(Math.max(stopped, time - RESUME_S), there, 0, 0, Infinity, 2);
        else
            add(Math.max(stopped, time), there, 0, 0, Infinity, 0);
    };
    if (message.type === 'window') {
        const channels = message.channels.filter((channel) => channel && channel.length);
        state.window = channels.length ? { channels, start: message.start, rate: message.rate, length: channels[0].length } : null;
    }
    else if (message.type === 'take') {
        //? where the record is on its path by `now`, the delay behind: it was at `at` as of context time
        //? `time`, moving at `rate` - and a host may apply it later than that (the main-thread voice holds it
        //? to its next block, which plays a block or two on). Started there, it has nothing to catch up;
        //? started at `at`, the steering would race it to where the record had got to - a chirp, half an
        //? octave up (review of 2.0.0-player.16)
        state.pos = message.at + message.rate * (now - state.delay - message.time);
        state.rate = message.rate;
        state.gain = 0;
        state.gainTarget = 1;
        state.gainAlpha = alpha(QUICK_S);
        state.driving = true;
        //? the path starts again from here
        state.first = state.end;
        state.cursor = state.end;
        add(message.time, message.at, message.rate, 0, message.until, 0);
    }
    else if (message.type === 'drive') {
        //? newer word on a moment the path already has, or an earlier one: what came after it goes
        while (state.end > state.first && t[(state.end - 1) % size] >= message.time)
            state.end -= 1;
        rested(message.time, message.at, false);
        add(message.time, message.at, message.rate, message.accel ?? 0, message.until, 0);
        state.driving = true;
    }
    else if (message.type === 'hand') {
        //? the hand caught the record before the record's own motion the path has after it - a coast's frames,
        //? posted at their frames' times, while the event that crossed a tap's few pixels was on its way: from
        //? the hand's sample on the path is the hand's, as a drive's is the drive's (review of 2.0.0-player.24:
        //? dropped as out of order, the coast ran on under a still finger and then rushed back)
        while (state.end > state.first && hand[(state.end - 1) % size] !== 1 && t[(state.end - 1) % size] > message.time)
            state.end -= 1;
        const last = state.end - 1;
        if (last >= state.first) {
            const lastTime = t[last % size];
            //? out of order: an older sample than the hand's newest is no use to the path
            if (message.time < lastTime)
                return;
            if (message.time === lastTime && hand[last % size] === 1)
                state.end -= 1;
            else
                rested(message.time, message.at, true);
        }
        add(message.time, message.at, 0, 0, Infinity, 1);
        //? this sample and the ones it is now among the after of
        for (let j = state.end - 1; j >= state.first && hand[j % size] === 1 && message.time - t[j % size] <= SMOOTH_AFTER_S; j--)
            fit(j);
    }
    else if (message.type === 'fade') {
        //? an exponential fade: four time constants in `seconds`, about 35 dB down by then
        state.gainTarget = 0;
        state.gainAlpha = alpha(message.seconds / 4);
    }
    else if (message.type === 'stop') {
        state.driving = false;
        state.gainTarget = 0;
        state.gainAlpha = alpha(QUICK_S);
    }
    if (state.cursor > state.end - 1)
        state.cursor = Math.max(state.first, state.end - 1);
}
/**
 * `frames` samples of the record's sound into `outputs` (one Float32Array a channel), from context
 * time `now`. Each sample: where the path has the record `delay` before it, and how fast; the rate
 * steered towards that and smoothed, the read head moved by it, the window read there with four-point
 * interpolation (silence outside it, faded at its edges), the gain smoothed, and the DC blocker.
 */
function renderVoice(state, outputs, frames, sampleRate, now) {
    //? the rate's smoothing, and the steering to the path - critically damped together (FOLLOW = 4 SMOOTH)
    const SMOOTH_S = 0.01;
    const FOLLOW_S = 0.04;
    //? the fastest it reads, either way, in the song's own speeds
    const MAX_RATE = 24;
    //? the fade at the window's edges, and the DC blocker's corner
    const EDGE_S = 0.004;
    const DC_HZ = 10;
    //? below this loudness nothing is read: silence
    const QUIET = 1e-5;
    //? how far the path runs on past a hand's last sample, slowing to still, before it holds
    const EXTRAPOLATE_S = 0.02;
    const rateAlpha = 1 - Math.exp(-1 / (SMOOTH_S * sampleRate));
    const pole = Math.exp((-2 * Math.PI * DC_HZ) / sampleRate);
    const dt = 1 / sampleRate;
    const win = state.window;
    const count = outputs.length;
    const size = state.knotTime.length;
    const kt = state.knotTime, kp = state.knotPos, kr = state.knotRate, ka = state.knotAccel, ku = state.knotUntil, kh = state.knotHand;
    const ks = state.knotSteady;
    for (let i = 0; i < frames; i++) {
        const t = now + i * dt;
        let desired = 0;
        if (state.driving && state.end > state.first) {
            //? the moment of the path it plays, and the knot that is on - by a moving index, never a search
            const tau = t - state.delay;
            let c = state.cursor;
            while (c > state.first && kt[c % size] > tau)
                c--;
            while (c + 1 < state.end && kt[(c + 1) % size] <= tau)
                c++;
            state.cursor = c;
            const a = c % size;
            const ta = kt[a];
            let x = 0, v = 0, follow = true;
            if (tau < ta) {
                //? before its first knot: where the take's motion had it
                x = kp[a] + kr[a] * (tau - ta);
                v = kr[a];
            }
            else if (c + 1 < state.end) {
                //? between two knots: the cubic through their places and speeds - its slope their two speeds,
                //? between them, and what the chord between their places asks beyond that (the last term). Where
                //? the hand was steady at both, that ask is a finger's jitter (a fraction of a ms of place a
                //? sample's spacing apart - a few per cent of pitch) and goes, as much as it was steady: the
                //? speeds are long lines' own, and the steering keeps the place (review of 2.0.0-player.24)
                const b = (c + 1) % size;
                const h = kt[b] - ta;
                const s = (tau - ta) / h;
                const s2 = s * s, s3 = s2 * s;
                x = (2 * s3 - 3 * s2 + 1) * kp[a] + (s3 - 2 * s2 + s) * h * kr[a] + (3 * s2 - 2 * s3) * kp[b] + (s3 - s2) * h * kr[b];
                const ask = 6 * (s - s2) * ((kp[b] - kp[a]) / h - (kr[a] + kr[b]) / 2);
                v = (1 - s) * kr[a] + s * kr[b] + (1 - Math.min(ks[a], ks[b])) * ask;
            }
            else if (kh[a] === 1) {
                //? past a hand's last sample: on along its speed, slowing to still over EXTRAPOLATE_S, then held
                const since = Math.min(tau - ta, EXTRAPOLATE_S);
                x = kp[a] + kr[a] * (since - (since * since) / (2 * EXTRAPOLATE_S));
                v = kr[a] * (1 - since / EXTRAPOLATE_S);
            }
            else if (tau <= ku[a]) {
                //? past a drive: along its own curve, until it runs out
                const since = tau - ta;
                x = kp[a] + kr[a] * since + 0.5 * ka[a] * since * since;
                v = kr[a] + ka[a] * since;
            }
            else {
                //? run out (a page stalled, a tab hidden): nothing to follow - it slows to still where it is
                follow = false;
            }
            if (follow) {
                desired = v + (x - state.pos) / FOLLOW_S;
                if (desired > MAX_RATE)
                    desired = MAX_RATE;
                else if (desired < -MAX_RATE)
                    desired = -MAX_RATE;
            }
        }
        state.rate += (desired - state.rate) * rateAlpha;
        state.pos += state.rate * dt;
        state.gain += (state.gainTarget - state.gain) * state.gainAlpha;
        let shape = 0;
        let index = 0;
        if (win && state.gain > QUIET) {
            index = (state.pos - win.start) * win.rate;
            const last = win.length - 1;
            const edge = Math.min(index, last - index) / (EDGE_S * win.rate);
            shape = edge <= 0 ? 0 : edge >= 1 ? 1 : edge;
        }
        for (let c = 0; c < count; c++) {
            let value = 0;
            if (shape > 0 && win) {
                const data = win.channels[c % win.channels.length];
                const last = win.length - 1;
                const at = Math.floor(index);
                const f = index - at;
                const y0 = data[at - 1 < 0 ? 0 : at - 1];
                const y1 = data[at < 0 ? 0 : at > last ? last : at];
                const y2 = data[at + 1 > last ? last : at + 1];
                const y3 = data[at + 2 > last ? last : at + 2];
                const c1 = 0.5 * (y2 - y0);
                const c2 = y0 - 2.5 * y1 + 2 * y2 - 0.5 * y3;
                const c3 = 0.5 * (y3 - y0) + 1.5 * (y1 - y2);
                value = (((c3 * f + c2) * f + c1) * f + y1) * shape * state.gain;
            }
            //? the DC blocker: y = x - x[-1] + pole y[-1]
            const out = value - (state.lastIn[c] ?? 0) + pole * (state.lastOut[c] ?? 0);
            state.lastIn[c] = value;
            state.lastOut[c] = out;
            outputs[c][i] = out;
        }
    }
}
/**
 * After `frames` samples played from context time `now`: what the voice says of where it is, when
 * `perSecond` times a second come round (exactly - the count carries its remainder), or null. Both
 * hosts call it after renderVoice, so the worklet and the main-thread voice say it alike.
 */
function voiceReport(state, frames, sampleRate, now, perSecond) {
    state.counted += frames;
    const every = sampleRate / perSecond;
    if (state.counted < every)
        return null;
    state.counted -= every;
    return { type: 'heard', pos: state.pos, rate: state.rate, gain: state.gain, time: now };
}
