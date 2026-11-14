/**
 * lib/playQueue.ts AS IT SHIPPED before 2.1.18 (5e3460c, deadwax 2.1.17), transpiled to CommonJS by TypeScript, comments
 * removed, the requires between the three named .cjs - frozen, for ui/test/resume.sim.cjs to read a 2.1.18 snapshot with
 * the reader James's open tabs and the iPhone app (0.9, DeadwaxCore's port of these files) still run ("an old reader").
 * Nothing in the app loads this file; don't edit it - it is a record of what shipped.
 */
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.LOAD_RETRY_DELAY_MS = exports.MEDIA_ERR_SRC_NOT_SUPPORTED = exports.MEDIA_ERR_DECODE = exports.MEDIA_ERR_NETWORK = exports.MEDIA_ERR_ABORTED = exports.NEW_LISTEN = exports.LISTEN_SLACK_SECONDS = exports.RESTART_AFTER_SECONDS = exports.EMPTY_QUEUE = void 0;
exports.current = current;
exports.startQueue = startQueue;
exports.nextIndex = nextIndex;
exports.previousAction = previousAction;
exports.countsAsPlayed = countsAsPlayed;
exports.listenedStep = listenedStep;
exports.listenStarted = listenStarted;
exports.listenHeard = listenHeard;
exports.afterFailure = afterFailure;
exports.EMPTY_QUEUE = { tracks: [], index: -1 };
exports.RESTART_AFTER_SECONDS = 3;
function current(queue) {
    return queue.tracks[queue.index] ?? null;
}
function startQueue(tracks, start, shuffle = false, random = Math.random) {
    if (!tracks.length)
        return exports.EMPTY_QUEUE;
    const index = Math.min(Math.max(start ?? 0, 0), tracks.length - 1);
    if (!shuffle)
        return { tracks: [...tracks], index };
    const rest = start === null ? [...tracks] : tracks.filter((_, i) => i !== index);
    for (let i = rest.length - 1; i > 0; i--) {
        const j = Math.floor(random() * (i + 1));
        [rest[i], rest[j]] = [rest[j], rest[i]];
    }
    return { tracks: start === null ? rest : [tracks[index], ...rest], index: 0 };
}
function nextIndex(queue) {
    const next = queue.index + 1;
    return next < queue.tracks.length ? next : null;
}
function previousAction(queue, position) {
    if (position > exports.RESTART_AFTER_SECONDS || queue.index <= 0)
        return { kind: 'restart' };
    return { kind: 'go', index: queue.index - 1 };
}
function countsAsPlayed(listened, duration) {
    if (!(duration > 30))
        return false;
    return listened >= Math.min(duration / 2, 240);
}
exports.LISTEN_SLACK_SECONDS = 0.5;
function listenedStep({ previous, now, elapsed, rate, seeked }) {
    const step = now - previous;
    if (seeked || !(step > 0))
        return 0;
    const pace = rate > 0 ? rate : 1;
    const allowed = Math.max(0, elapsed) * pace + exports.LISTEN_SLACK_SECONDS;
    return Math.min(step, allowed);
}
exports.NEW_LISTEN = { heard: 0, startedAt: 0, submitted: false };
function listenStarted(listen, now) {
    if (listen.startedAt)
        return { listen, nowPlaying: false };
    return { listen: { ...listen, startedAt: now }, nowPlaying: true };
}
function listenHeard(listen, seconds, duration) {
    const heard = listen.heard + seconds;
    const submit = !listen.submitted && countsAsPlayed(heard, duration);
    return { listen: { ...listen, heard, submitted: listen.submitted || submit }, submit };
}
exports.MEDIA_ERR_ABORTED = 1;
exports.MEDIA_ERR_NETWORK = 2;
exports.MEDIA_ERR_DECODE = 3;
exports.MEDIA_ERR_SRC_NOT_SUPPORTED = 4;
exports.LOAD_RETRY_DELAY_MS = 1500;
function afterFailure({ queue, code, intendsToPlay, retried }) {
    if (!intendsToPlay || code === exports.MEDIA_ERR_ABORTED)
        return { kind: 'stop' };
    const loadFailure = code === exports.MEDIA_ERR_NETWORK || code === exports.MEDIA_ERR_SRC_NOT_SUPPORTED;
    if (loadFailure && !retried)
        return { kind: 'retry' };
    const next = nextIndex(queue);
    return next === null ? { kind: 'stop' } : { kind: 'skip', index: next };
}
