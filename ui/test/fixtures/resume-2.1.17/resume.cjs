/**
 * lib/resume.ts AS IT SHIPPED before 2.1.18 (5e3460c, deadwax 2.1.17), transpiled to CommonJS by TypeScript, comments
 * removed, the requires between the three named .cjs - frozen, for ui/test/resume.sim.cjs to read a 2.1.18 snapshot with
 * the reader James's open tabs and the iPhone app (0.9, DeadwaxCore's port of these files) still run ("an old reader").
 * Nothing in the app loads this file; don't edit it - it is a record of what shipped.
 */
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.DEADWAX_CLIENT = exports.BEACON_MAX = exports.RESUME_FOCUS_GRACE_MS = exports.RESUME_RECHECK_MS = exports.RESUME_AT_WAIT_MS = exports.RESUME_FULL_WAIT_MS = exports.RESUME_EVERY_S = exports.RESUME_SNAPSHOT_MAX = exports.RESUME_BEFORE = exports.RESUME_MAX = void 0;
exports.utf8Length = utf8Length;
exports.bare = bare;
exports.windowOf = windowOf;
exports.toSave = toSave;
exports.relevel = relevel;
exports.savedLevels = savedLevels;
exports.fromSnapshot = fromSnapshot;
exports.sameQueue = sameQueue;
exports.resumed = resumed;
exports.deviceLabel = deviceLabel;
exports.pickedUpWords = pickedUpWords;
exports.changedSince = changedSince;
exports.saveDue = saveDue;
const playQueue_1 = require("./playQueue.cjs");
const upNext_1 = require("./upNext.cjs");
exports.RESUME_MAX = 2000;
exports.RESUME_BEFORE = 50;
exports.RESUME_SNAPSHOT_MAX = 262_144;
exports.RESUME_EVERY_S = 30;
exports.RESUME_FULL_WAIT_MS = 2000;
exports.RESUME_AT_WAIT_MS = 1000;
exports.RESUME_RECHECK_MS = 15_000;
exports.RESUME_FOCUS_GRACE_MS = 500;
exports.BEACON_MAX = 60_000;
exports.DEADWAX_CLIENT = 'deadwax';
function utf8Length(text) {
    let bytes = 0;
    for (let i = 0; i < text.length; i++) {
        const unit = text.charCodeAt(i);
        if (unit < 0x80)
            bytes += 1;
        else if (unit < 0x800)
            bytes += 2;
        else if (unit >= 0xd800 && unit <= 0xdbff && i + 1 < text.length && (text.charCodeAt(i + 1) & 0xfc00) === 0xdc00) {
            bytes += 4;
            i++;
        }
        else
            bytes += 3;
    }
    return bytes;
}
const levelChar = (level) => (level === 'album' ? 'a' : level === 'track' ? 't' : '-');
const charLevel = (char) => (char === 'a' ? 'album' : char === 't' ? 'track' : undefined);
const fromChar = (from) => (from === 'source' ? 's' : from === 'added' ? 'a' : 'o');
function bare(track) {
    return {
        id: track.id, title: track.title, artist: track.artist, album: track.album, albumId: track.albumId, coverArt: track.coverArt,
        duration: track.duration, contentType: track.contentType, suffix: track.suffix, sampleRate: track.sampleRate,
        bitDepth: track.bitDepth, channels: track.channels,
    };
}
function windowOf(count, index) {
    if (count <= 0)
        return { start: 0, end: 0 };
    const at = Math.min(Math.max(index, 0), count - 1);
    const start = Math.max(0, at - exports.RESUME_BEFORE);
    return { start, end: Math.min(count, start + exports.RESUME_MAX) };
}
function toSave(queue, position) {
    const { start, end } = windowOf(queue.tracks.length, queue.index);
    const entries = queue.tracks.slice(start, end);
    const ids = entries.map((track) => track.id);
    const index = queue.index - start;
    const state = queue.upNext;
    if (!state)
        return { ids, index, position, snapshot: null, start };
    const inWindow = new Set(ids);
    const extra = {};
    for (const track of state.source)
        if (!inWindow.has(track.id) && !(track.id in extra))
            extra[track.id] = bare(track);
    const made = {
        v: 1,
        id: state.id,
        levels: entries.map((track) => levelChar(track.level)).join(''),
        marks: state.marks.slice(start, end).map((mark) => [mark.key, fromChar(mark.from), mark.at, mark.pass]),
        source: state.source.map((track) => track.id),
        sourceLevels: state.source.map((track) => levelChar(track.level)).join(''),
        extra,
        shuffle: state.shuffle,
        nextKey: state.nextKey,
        startedAt: Math.max(0, state.startedAt - start),
        left: state.left.map((gone) => [gone.pass, gone.at]),
        ...(state.paged ? { paged: state.paged } : {}),
        ...(state.pagedRounds ? { pagedRounds: state.pagedRounds } : {}),
    };
    const snapshot = JSON.stringify(made);
    return { ids, index, position, snapshot: snapshot.length <= exports.RESUME_SNAPSHOT_MAX ? snapshot : null, start };
}
function relevel(level, setting) {
    if (setting === 'off')
        return undefined;
    if (setting === 'song')
        return 'track';
    if (setting === 'album')
        return 'album';
    return level ?? 'track';
}
const QUEUE_ID = /^[A-Za-z0-9_-]{1,64}$/;
const isInt = (value) => typeof value === 'number' && Number.isInteger(value);
const isObject = (value) => typeof value === 'object' && value !== null && !Array.isArray(value);
const nullableString = (value) => value === null || typeof value === 'string';
function readSong(value, id) {
    if (!isObject(value) || value.id !== id)
        return null;
    const numbers = ['duration', 'sampleRate', 'bitDepth', 'channels'];
    if (typeof value.title !== 'string' || typeof value.artist !== 'string' || typeof value.album !== 'string')
        return null;
    if (!nullableString(value.albumId) || !nullableString(value.coverArt) || !nullableString(value.contentType) || !nullableString(value.suffix))
        return null;
    if (numbers.some((name) => typeof value[name] !== 'number' || !Number.isFinite(value[name])))
        return null;
    return bare(value);
}
function readPaged(value, setting) {
    if (!isObject(value) || typeof value.token !== 'string' || !isInt(value.total) || !isInt(value.fetched))
        return null;
    if (value.scope !== 'yours' && value.scope !== 'store')
        return null;
    if (value.level !== undefined && value.level !== 'album' && value.level !== 'track')
        return null;
    const level = relevel(value.level, setting);
    return { token: value.token, total: value.total, fetched: value.fetched, scope: value.scope, ...(level ? { level } : {}) };
}
function savedLevels(snapshot, count) {
    try {
        const made = snapshot === null ? null : JSON.parse(snapshot);
        if (isObject(made) && made.v === 1 && typeof made.levels === 'string' && made.levels.length === count) {
            return [...made.levels].map(charLevel);
        }
    }
    catch {
    }
    return Array.from({ length: count }, () => undefined);
}
function fromSnapshot(snapshot, tracks, index, setting, holding = null) {
    if (snapshot === null)
        return null;
    let made;
    try {
        made = JSON.parse(snapshot);
    }
    catch {
        return null;
    }
    if (!isObject(made) || made.v !== 1)
        return null;
    const n = tracks.length;
    const { levels, marks, source, sourceLevels, extra, shuffle, nextKey, startedAt, left } = made;
    if (typeof levels !== 'string' || levels.length !== n || !Array.isArray(marks) || marks.length !== n)
        return null;
    if (!Array.isArray(source) || !source.every((id) => typeof id === 'string'))
        return null;
    if (typeof sourceLevels !== 'string' || sourceLevels.length !== source.length || !isObject(extra))
        return null;
    if (typeof shuffle !== 'boolean' || !isInt(nextKey) || !isInt(startedAt) || !Array.isArray(left))
        return null;
    if (!isInt(index) || index < 0 || index >= n || startedAt < 0)
        return null;
    const navidrome = new Map(tracks.map((track) => [track.id, bare(track)]));
    const songs = new Map();
    const song = (id, char) => {
        const level = relevel(charLevel(char), setting);
        const key = `${level ?? ''}:${id}`;
        if (!songs.has(key)) {
            const base = navidrome.get(id) ?? readSong(extra[id], id);
            songs.set(key, base && level ? { ...base, level } : base);
        }
        return songs.get(key);
    };
    const entries = tracks.map((track, i) => song(track.id, levels[i]));
    const list = source.map((id, j) => song(id, sourceLevels[j]));
    if (entries.some((track) => !track) || list.some((track) => !track))
        return null;
    const keys = new Set();
    const rebuilt = [];
    for (const [i, raw] of marks.entries()) {
        if (!Array.isArray(raw) || raw.length !== 4)
            return null;
        const [key, char, at, pass] = raw;
        if (!isInt(key) || !isInt(at) || !isInt(pass) || key < 0 || key >= nextKey || keys.has(key))
            return null;
        keys.add(key);
        const from = char === 's' ? 'source' : char === 'a' ? 'added' : char === 'o' ? 'one' : null;
        if (from === null)
            return null;
        if (from === 'source' && (at < 0 || at >= list.length || list[at].id !== entries[i].id || pass < 0))
            return null;
        if (from === 'added' && (at !== -1 || pass !== -1))
            return null;
        if (from === 'one' && (at < -1 || at >= list.length))
            return null;
        rebuilt.push({ key, from, at, pass });
    }
    let run = index;
    while (run > 0 && rebuilt[run].from === 'one')
        run--;
    const gone = [];
    for (const raw of left) {
        if (!Array.isArray(raw) || raw.length !== 2 || !isInt(raw[0]) || !isInt(raw[1]))
            return null;
        gone.push({ pass: raw[0], at: raw[1] });
    }
    let paged;
    if (made.paged !== undefined) {
        const read = readPaged(made.paged, setting);
        if (!read)
            return null;
        paged = read;
    }
    let pagedRounds;
    if (made.pagedRounds !== undefined) {
        if (!Array.isArray(made.pagedRounds))
            return null;
        pagedRounds = [];
        for (const held of made.pagedRounds) {
            const read = isObject(held) && isInt(held.pass) ? readPaged(held.paged, setting) : null;
            if (!read || !isObject(held))
                return null;
            pagedRounds.push({ pass: held.pass, paged: read });
        }
    }
    const saved = typeof made.id === 'string' && QUEUE_ID.test(made.id) ? made.id : null;
    const upNext = {
        id: saved ?? (0, upNext_1.queueId)(),
        marks: rebuilt, source: list, shuffle, nextKey, startedAt: Math.min(startedAt, run), left: gone,
        ...(paged ? { paged } : {}), ...(pagedRounds ? { pagedRounds } : {}),
    };
    const queue = { tracks: entries, index, upNext };
    const kept = holding?.upNext?.id;
    return saved === null && kept && sameQueue(holding, queue) ? { ...queue, upNext: { ...upNext, id: kept } } : queue;
}
function sameQueue(held, put) {
    const a = held.upNext;
    const b = put.upNext;
    if (!a || !b || a.source.length !== b.source.length || a.source.some((track, i) => track.id !== b.source[i].id))
        return false;
    const songs = new Map(a.marks.map((mark, i) => [mark.key, held.tracks[i]?.id]));
    let common = 0;
    for (const [i, mark] of b.marks.entries()) {
        const song = songs.get(mark.key);
        if (song === undefined)
            continue;
        if (song !== put.tracks[i]?.id)
            return false;
        common++;
    }
    return common > 0;
}
function plain(tracks, index, levels, setting) {
    const levelled = tracks.map((track, i) => {
        const level = relevel(levels[i], setting);
        return level ? { ...bare(track), level } : track;
    });
    return (0, upNext_1.startUpNext)(levelled, index);
}
const same = (a, b) => a.length === b.length && a.every((id, i) => id === b[i]);
function resumed(answer, tracks, setting, deviceId, holding = null) {
    const n = tracks.length;
    if (!n)
        return null;
    const ids = tracks.map((track) => track.id);
    const kept = answer.kept;
    const keptFrom = kept && kept.device !== deviceId ? { device: kept.label } : null;
    let queue;
    let position;
    let from;
    let exact = false;
    const present = new Set(ids);
    const survivors = kept ? kept.ids.filter((id) => present.has(id)) : [];
    if (kept && same(ids, kept.ids) && kept.index === answer.index) {
        exact = true;
        queue = fromSnapshot(kept.snapshot, tracks, kept.index, setting, holding) ?? plain(tracks, kept.index, savedLevels(kept.snapshot, n), setting);
        position = kept.position;
        from = keptFrom;
    }
    else if (kept && survivors.length < kept.ids.length && same(survivors, ids)) {
        const levels = savedLevels(kept.snapshot, kept.ids.length).filter((_, i) => present.has(kept.ids[i]));
        const at = Math.min(Math.max(kept.index, 0), kept.ids.length - 1);
        const before = kept.ids.slice(0, at).filter((id) => present.has(id)).length;
        let index;
        if (present.has(kept.ids[at])) {
            index = before;
            position = kept.position;
        }
        else {
            index = before < n ? before : n - 1;
            position = 0;
        }
        queue = plain(tracks, index, levels, setting);
        from = keptFrom;
    }
    else {
        const said = answer.index;
        const index = said === null ? 0 : Math.min(Math.max(said, 0), n - 1);
        position = said === index ? answer.position : 0;
        queue = plain(tracks, index, [], setting);
        from = kept && same(ids, kept.ids) ? keptFrom : answer.changed_by && answer.changed_by !== exports.DEADWAX_CLIENT ? { app: answer.changed_by } : null;
    }
    const track = (0, playQueue_1.current)(queue);
    if (track.duration > 0 && position >= track.duration - 1) {
        if (queue.index + 1 < queue.tracks.length)
            queue = { ...queue, index: queue.index + 1 };
        position = 0;
    }
    return { queue, position: Math.max(0, position), from, exact };
}
function deviceLabel(userAgent, maxTouchPoints) {
    if (/iPhone|iPod/.test(userAgent))
        return 'iPhone';
    if (/iPad/.test(userAgent) || (/Macintosh/.test(userAgent) && maxTouchPoints > 1))
        return 'iPad';
    if (/Macintosh|Mac OS X/.test(userAgent))
        return 'Mac';
    if (/Windows/.test(userAgent))
        return 'Windows PC';
    if (/Android/.test(userAgent))
        return 'Android phone';
    if (/CrOS/.test(userAgent))
        return 'Chromebook';
    if (/Linux/.test(userAgent))
        return 'Linux PC';
    return 'browser';
}
function pickedUpWords(from, shared) {
    if (!from)
        return null;
    if ('app' in from)
        return `Picked up from ${from.app}`;
    const whose = shared ? (/^[aeiou]/i.test(from.device) ? 'an' : 'a') : 'your';
    return `Picked up from ${whose} ${from.device}`;
}
function changedSince(saved, queue, position) {
    if (!saved || queue.tracks !== saved.tracks || queue.upNext !== saved.upNext)
        return 'songs';
    if (queue.index !== saved.index)
        return 'song';
    if (Math.abs(position - saved.position) > 1)
        return 'position';
    return null;
}
function saveDue(clock, queue, position, playing, now, trigger) {
    if (!(0, playQueue_1.current)(queue))
        return null;
    if (clock.failedAt !== null && now - clock.failedAt < exports.RESUME_EVERY_S * 1000)
        return null;
    const change = changedSince(clock.saved, queue, position);
    if (change === null)
        return null;
    const saved = clock.saved;
    const at = change !== 'songs' && clock.idsRev !== null && saved !== null && queue.index >= saved.start && queue.index < saved.start + saved.count;
    const kind = at ? 'at' : 'full';
    if (trigger === 'pause' || trigger === 'hidden')
        return kind;
    const since = clock.changedAt === null ? Infinity : now - clock.changedAt;
    if (change === 'songs')
        return since >= exports.RESUME_FULL_WAIT_MS ? 'full' : null;
    if (change === 'song')
        return since >= exports.RESUME_AT_WAIT_MS ? kind : null;
    if (!playing)
        return trigger === 'wait' ? kind : null;
    return trigger === 'position' && (clock.countFrom === null || now - clock.countFrom >= exports.RESUME_EVERY_S * 1000) ? kind : null;
}
