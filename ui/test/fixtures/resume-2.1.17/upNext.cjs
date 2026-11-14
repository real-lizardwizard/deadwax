/**
 * lib/upNext.ts AS IT SHIPPED before 2.1.18 (5e3460c, deadwax 2.1.17), transpiled to CommonJS by TypeScript, comments
 * removed, the requires between the three named .cjs - frozen, for ui/test/resume.sim.cjs to read a 2.1.18 snapshot with
 * the reader James's open tabs and the iPhone app (0.9, DeadwaxCore's port of these files) still run ("an old reader").
 * Nothing in the app loads this file; don't edit it - it is a record of what shipped.
 */
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.HISTORY_BACK = exports.TOP_UP_HEARD_S = exports.UP_NEXT_DRAWN = exports.REPEAT_AHEAD = exports.REPEATS = void 0;
exports.queueId = queueId;
exports.startUpNext = startUpNext;
exports.toppedUp = toppedUp;
exports.withRepeat = withRepeat;
exports.withShuffle = withShuffle;
exports.withNext = withNext;
exports.withLast = withLast;
exports.withoutKey = withoutKey;
exports.movedKey = movedKey;
exports.withoutAdded = withoutAdded;
exports.jumpedTo = jumpedTo;
exports.onward = onward;
exports.backward = backward;
exports.pastCopies = pastCopies;
exports.shownPass = shownPass;
exports.withMore = withMore;
exports.upNextView = upNextView;
exports.historyRows = historyRows;
exports.shownKeys = shownKeys;
exports.wentBack = wentBack;
exports.listTitle = listTitle;
exports.queuedWords = queuedWords;
exports.repeatLabel = repeatLabel;
exports.shuffleLabel = shuffleLabel;
exports.nextRepeat = nextRepeat;
exports.upNextLabel = upNextLabel;
const playQueue_1 = require("./playQueue.cjs");
exports.REPEATS = ['off', 'all', 'one'];
exports.REPEAT_AHEAD = 2;
exports.UP_NEXT_DRAWN = 100;
exports.TOP_UP_HEARD_S = 2;
exports.HISTORY_BACK = 50;
function queueId(now = Date.now()) {
    const digits = '0123456789abcdefghijklmnopqrstuvwxyz';
    const bytes = new Uint8Array(8);
    const crypto = globalThis.crypto;
    if (typeof crypto?.getRandomValues === 'function')
        crypto.getRandomValues(bytes);
    else
        for (let i = 0; i < bytes.length; i++)
            bytes[i] = Math.floor(Math.random() * 256);
    return `${Math.max(0, Math.floor(now)).toString(36)}-${[...bytes].map((byte) => digits[byte % 36]).join('')}`;
}
function shuffled(list, random) {
    const out = [...list];
    for (let i = out.length - 1; i > 0; i--) {
        const j = Math.floor(random() * (i + 1));
        [out[i], out[j]] = [out[j], out[i]];
    }
    return out;
}
function rebuilt(queue, state, tracks, marks, more = {}) {
    return { ...queue, tracks, upNext: { ...state, marks, ...more } };
}
function unitEnd(state, place) {
    let end = place + 1;
    while (state.marks[end]?.from === 'one')
        end++;
    return end;
}
function unitStart(state, index) {
    let place = index;
    while (place > 0 && state.marks[place]?.from === 'one')
        place--;
    return place;
}
function layout(queue, state) {
    let copiesEnd = queue.index + 1;
    while (state.marks[copiesEnd]?.from === 'one')
        copiesEnd++;
    let addedEnd = copiesEnd;
    while (state.marks[addedEnd]?.from === 'added')
        addedEnd = unitEnd(state, addedEnd);
    const shown = shownPass(queue);
    let listEnd = addedEnd;
    while (listEnd < state.marks.length) {
        const mark = state.marks[listEnd];
        if (mark.from === 'source' ? mark.pass !== shown : mark.from !== 'added')
            break;
        listEnd = unitEnd(state, listEnd);
    }
    return { copiesEnd, addedEnd, listEnd };
}
function unitsIn(state, start, end) {
    const units = [];
    for (let place = start; place < end; place = unitEnd(state, place))
        units.push(place);
    return units;
}
function lastSourceAt(state, index) {
    for (let i = Math.min(index, state.marks.length - 1); i >= 0; i--)
        if (state.marks[i].from === 'source')
            return i;
    return -1;
}
function passPlaying(state, index) {
    const at = lastSourceAt(state, index);
    return at < 0 ? -1 : state.marks[at].pass;
}
function oneAlbum(source) {
    const first = source[0];
    if (!first?.albumId)
        return null;
    return source.every((track) => track.albumId === first.albumId) ? first.album : null;
}
function startUpNext(tracks, start, shuffle = false, random = Math.random, paged, id) {
    if (!tracks.length)
        return playQueue_1.EMPTY_QUEUE;
    const index = Math.min(Math.max(start ?? 0, 0), tracks.length - 1);
    const places = tracks.map((_, at) => at);
    const order = !shuffle ? places : start === null ? shuffled(places, random) : [index, ...shuffled(places.filter((at) => at !== index), random)];
    return {
        tracks: order.map((at) => tracks[at]),
        index: shuffle ? 0 : index,
        upNext: {
            id: id ?? queueId(),
            marks: order.map((at, key) => ({ key, from: 'source', at, pass: 0 })),
            source: [...tracks],
            shuffle: shuffle || !!paged,
            nextKey: order.length,
            startedAt: shuffle ? 0 : index,
            left: [],
            ...(paged ? { paged } : {}),
        },
    };
}
function toppedUp(queue, repeat, random = Math.random) {
    const state = queue.upNext;
    const playing = (0, playQueue_1.current)(queue);
    if (!state || repeat === 'off' || !playing)
        return queue;
    if (repeat === 'one') {
        let end = queue.index + 1;
        while (state.marks[end]?.from === 'one' && queue.tracks[end]?.id === playing.id)
            end++;
        const have = end - queue.index - 1;
        if (have >= exports.REPEAT_AHEAD)
            return queue;
        const count = exports.REPEAT_AHEAD - have;
        const original = state.marks[queue.index];
        const copies = Array.from({ length: count }, (_, i) => ({ key: state.nextKey + i, from: 'one', at: original.at, pass: original.pass }));
        return rebuilt(queue, state, [...queue.tracks.slice(0, end), ...copies.map(() => playing), ...queue.tracks.slice(end)], [...state.marks.slice(0, end), ...copies, ...state.marks.slice(end)], { nextKey: state.nextKey + count });
    }
    if (state.paged || !state.source.length || queue.tracks.length - queue.index - 1 >= exports.REPEAT_AHEAD)
        return queue;
    const tracks = [...queue.tracks];
    const marks = [...state.marks];
    let nextKey = state.nextKey;
    while (tracks.length - queue.index - 1 < exports.REPEAT_AHEAD) {
        const last = lastSourceAt({ ...state, marks }, marks.length - 1);
        const pass = (last < 0 ? -1 : marks[last].pass) + 1;
        const order = state.source.map((_, at) => at);
        let round = state.shuffle ? shuffled(order, random) : order;
        const ending = last < 0 ? undefined : tracks[last]?.id;
        if (state.shuffle && round.length > 1 && ending !== undefined && state.source[round[0]].id === ending) {
            const later = round.map((at, place) => ({ at, place })).filter(({ at, place }) => place > 0 && state.source[at].id !== ending);
            const pick = later[Math.floor(random() * later.length)];
            if (pick) {
                round = [...round];
                [round[0], round[pick.place]] = [round[pick.place], round[0]];
            }
        }
        for (const at of round) {
            tracks.push(state.source[at]);
            marks.push({ key: nextKey++, from: 'source', at, pass });
        }
    }
    return rebuilt(queue, state, tracks, marks, { nextKey });
}
function withRepeat(queue, repeat) {
    const state = queue.upNext;
    if (!state)
        return queue;
    const round = passPlaying(state, queue.index);
    const goes = (mark, place) => {
        if (place <= queue.index)
            return false;
        if (mark.from === 'one') {
            if (repeat !== 'one')
                return true;
            const song = unitStart(state, place);
            return song > queue.index && goes(state.marks[song], song);
        }
        return repeat !== 'all' && mark.from === 'source' && mark.pass > round;
    };
    if (!state.marks.some(goes))
        return queue;
    const marks = state.marks.filter((mark, place) => !goes(mark, place));
    const last = lastSourceAt({ ...state, marks }, marks.length - 1);
    const pass = last < 0 ? -1 : marks[last].pass;
    const back = state.paged && state.pagedRounds?.find((held) => held.pass === pass);
    const more = back
        ? { paged: back.paged, pagedRounds: state.pagedRounds.filter((held) => held.pass < pass) }
        : {};
    return rebuilt(queue, state, queue.tracks.filter((_, place) => !goes(state.marks[place], place)), marks, more);
}
function withShuffle(queue, on, random = Math.random) {
    const state = queue.upNext;
    if (!state || state.paged || state.shuffle === on || !(0, playQueue_1.current)(queue))
        return queue;
    const { index } = queue;
    const round = passPlaying(state, index);
    const left = new Set(state.left.filter((gone) => gone.pass === round).map((gone) => gone.at));
    const places = state.source.map((_, at) => at);
    let wanted;
    if (on) {
        let roundStart = round === 0 ? state.startedAt : state.marks.findIndex((mark) => mark.from === 'source' && mark.pass === round);
        if (roundStart < 0)
            roundStart = index;
        const heard = new Set();
        for (let place = roundStart; place <= index; place++) {
            const mark = state.marks[place];
            if (mark.from === 'source' && mark.pass === round)
                heard.add(mark.at);
        }
        const playingAt = state.marks[index].at;
        if (playingAt >= 0)
            heard.add(playingAt);
        wanted = shuffled(places.filter((at) => !heard.has(at) && !left.has(at)), random);
    }
    else {
        const last = lastSourceAt(state, index);
        const lastAt = last < 0 ? -1 : state.marks[last].at;
        wanted = places.filter((at) => at > lastAt && !left.has(at));
    }
    const queued = new Map();
    if (on) {
        for (let place = index + 1; place < state.marks.length; place++) {
            const mark = state.marks[place];
            if (mark.from === 'source' && mark.pass === round)
                queued.set(mark.at, mark);
        }
    }
    let nextKey = state.nextKey;
    const fresh = wanted.map((at) => queued.get(at) ?? { key: nextKey++, from: 'source', at, pass: Math.max(round, 0) });
    const stays = (mark, place) => {
        if (place <= index)
            return true;
        const song = mark.from === 'one' ? unitStart(state, place) : place;
        return song <= index || state.marks[song].from !== 'source';
    };
    return rebuilt(queue, state, [...queue.tracks.filter((_, place) => stays(state.marks[place], place)), ...fresh.map((mark) => state.source[mark.at])], [...state.marks.filter(stays), ...fresh], { shuffle: on, nextKey });
}
function added(queue, state, tracks, place) {
    const marks = tracks.map((_, i) => ({ key: state.nextKey + i, from: 'added', at: -1, pass: -1 }));
    return rebuilt(queue, state, [...queue.tracks.slice(0, place), ...tracks, ...queue.tracks.slice(place)], [...state.marks.slice(0, place), ...marks, ...state.marks.slice(place)], { nextKey: state.nextKey + tracks.length });
}
function withNext(queue, tracks) {
    const state = queue.upNext;
    if (!state || !tracks.length || !(0, playQueue_1.current)(queue))
        return queue;
    return added(queue, state, tracks, layout(queue, state).copiesEnd);
}
function withLast(queue, tracks) {
    const state = queue.upNext;
    if (!state || !tracks.length || !(0, playQueue_1.current)(queue))
        return queue;
    return added(queue, state, tracks, layout(queue, state).addedEnd);
}
function groupOf(queue, state, key) {
    const place = state.marks.findIndex((mark) => mark.key === key);
    const { copiesEnd, addedEnd, listEnd } = layout(queue, state);
    if (place < copiesEnd || state.marks[place].from === 'one')
        return null;
    if (place < addedEnd)
        return { place, start: copiesEnd, end: addedEnd, added: true };
    return place < listEnd ? { place, start: addedEnd, end: listEnd, added: false } : null;
}
function withoutKey(queue, key) {
    const state = queue.upNext;
    if (!state)
        return queue;
    const group = groupOf(queue, state, key);
    if (!group)
        return queue;
    const mark = state.marks[group.place];
    const end = unitEnd(state, group.place);
    const stays = (_, place) => place < group.place || place >= end;
    return rebuilt(queue, state, queue.tracks.filter(stays), state.marks.filter(stays), mark.from === 'source' ? { left: [...state.left, { pass: mark.pass, at: mark.at }] } : {});
}
function movedKey(queue, key, to) {
    const state = queue.upNext;
    if (!state)
        return queue;
    const group = groupOf(queue, state, key);
    if (!group)
        return queue;
    const units = unitsIn(state, group.start, group.end);
    const from = units.indexOf(group.place);
    const dest = Math.max(0, Math.min(units.length - 1, Math.round(to)));
    if (dest === from)
        return queue;
    const order = units.map((start) => ({ start, end: unitEnd(state, start) }));
    const [taken] = order.splice(from, 1);
    order.splice(dest, 0, taken);
    const move = (list) => [...list.slice(0, group.start), ...order.flatMap(({ start, end }) => list.slice(start, end)), ...list.slice(group.end)];
    return rebuilt(queue, state, move(queue.tracks), move(state.marks));
}
function withoutAdded(queue) {
    const state = queue.upNext;
    if (!state)
        return queue;
    const { copiesEnd, addedEnd } = layout(queue, state);
    if (addedEnd === copiesEnd)
        return queue;
    const stays = (_, place) => place < copiesEnd || place >= addedEnd;
    return rebuilt(queue, state, queue.tracks.filter(stays), state.marks.filter(stays));
}
function jumpedTo(queue, key) {
    const state = queue.upNext;
    if (!state || !(0, playQueue_1.current)(queue))
        return null;
    const place = state.marks.findIndex((mark) => mark.key === key);
    if (place < 0)
        return null;
    const { copiesEnd, addedEnd } = layout(queue, state);
    if (place < unitStart(state, queue.index)) {
        if (!historyRows(queue).some((row) => row.key === key))
            return null;
        return { queue: added(queue, state, [queue.tracks[place]], copiesEnd), index: copiesEnd };
    }
    const group = groupOf(queue, state, key);
    if (!group)
        return null;
    if (group.added || addedEnd === copiesEnd)
        return { queue, index: group.place };
    const end = unitEnd(state, group.place);
    const places = [];
    for (let at = 0; at < copiesEnd; at++)
        places.push(at);
    for (let at = addedEnd; at < end; at++)
        places.push(at);
    for (let at = copiesEnd; at < addedEnd; at++)
        places.push(at);
    for (let at = end; at < state.marks.length; at++)
        places.push(at);
    return {
        queue: rebuilt(queue, state, places.map((at) => queue.tracks[at]), places.map((at) => state.marks[at])),
        index: group.place - (addedEnd - copiesEnd),
    };
}
function onward(queue) {
    const state = queue.upNext;
    if (!state)
        return (0, playQueue_1.nextIndex)(queue);
    for (let place = queue.index + 1; place < state.marks.length; place++)
        if (state.marks[place].from !== 'one')
            return place;
    return null;
}
function backward(queue, position) {
    const action = (0, playQueue_1.previousAction)(queue, position);
    const state = queue.upNext;
    if (action.kind === 'restart' || !state)
        return action;
    let place = queue.index;
    while (place > 0 && state.marks[place]?.from === 'one')
        place--;
    return place > 0 ? { kind: 'go', index: place - 1 } : { kind: 'restart' };
}
function pastCopies(queue, from) {
    const state = queue.upNext;
    if (!state)
        return from >= 0 && from < queue.tracks.length ? from : null;
    for (let place = Math.max(from, 0); place < state.marks.length; place++)
        if (state.marks[place].from !== 'one')
            return place;
    return null;
}
function shownPass(queue) {
    const state = queue.upNext;
    if (!state)
        return -1;
    for (let place = queue.index + 1; place < state.marks.length; place++) {
        const mark = state.marks[place];
        if (mark.from === 'source')
            return mark.pass;
    }
    return -1;
}
function withMore(queue, token, tracks, next) {
    const state = queue.upNext;
    const paged = state?.paged;
    if (!state || !paged || paged.token !== token || !tracks.length)
        return queue;
    const round = next && paged.fetched >= paged.total;
    const last = lastSourceAt(state, state.marks.length - 1);
    const before = last < 0 ? 0 : state.marks[last].pass;
    const pass = before + (round ? 1 : 0);
    const marks = tracks.map((_, i) => ({ key: state.nextKey + i, from: 'source', at: state.source.length + i, pass }));
    const playing = passPlaying(state, queue.index);
    const pagedRounds = round
        ? [...(state.pagedRounds ?? []).filter((held) => held.pass >= playing), { pass: before, paged }]
        : state.pagedRounds;
    return rebuilt(queue, state, [...queue.tracks, ...tracks], [...state.marks, ...marks], {
        source: [...state.source, ...tracks],
        nextKey: state.nextKey + tracks.length,
        paged: next ? { ...next, fetched: tracks.length } : { ...paged, fetched: paged.fetched + tracks.length },
        ...(pagedRounds ? { pagedRounds } : {}),
    });
}
function upNextView(queue, repeat, limit = exports.UP_NEXT_DRAWN) {
    const playing = (0, playQueue_1.current)(queue);
    const state = queue.upNext;
    if (!playing || !state)
        return { history: [], playing, added: [], list: null, then: null, repeatOne: false };
    const { copiesEnd, addedEnd, listEnd } = layout(queue, state);
    const row = (place) => ({ key: state.marks[place].key, track: queue.tracks[place] });
    const addedRows = unitsIn(state, copiesEnd, addedEnd).map(row);
    const shown = shownPass(queue);
    const listed = unitsIn(state, addedEnd, listEnd);
    const paged = state.paged;
    const pending = paged ? Math.max(0, paged.total - paged.fetched) : 0;
    const again = shown > passPlaying(state, queue.index);
    const title = paged ? `${paged.scope === 'yours' ? 'Your library' : 'All music'}, shuffled${again ? ', again' : ''}` : listTitle(state.source, again);
    const list = listed.length || pending
        ? { title, rows: listed.slice(0, limit).map(row), more: Math.max(0, listed.length - limit) + pending }
        : null;
    const name = paged ? (paged.scope === 'yours' ? 'your library' : 'all music') : oneAlbum(state.source) ?? 'the list';
    const then = repeat === 'all'
        ? state.shuffle ? `Then ${name} again, in a new order.` : `Then ${name} again from the top.`
        : repeat === 'off' && queue.index >= queue.tracks.length - 1 ? 'Nothing after this song.' : null;
    return { history: historyRows(queue), playing, added: addedRows, list, then, repeatOne: repeat === 'one' };
}
function historyRows(queue, back = exports.HISTORY_BACK) {
    const state = queue.upNext;
    if (!state || !(0, playQueue_1.current)(queue))
        return [];
    const from = historyFloor(queue, state, back);
    const rows = [];
    for (let place = from; place < unitStart(state, queue.index); place = unitEnd(state, place)) {
        if (state.marks[place].from !== 'one')
            rows.push({ key: state.marks[place].key, track: queue.tracks[place] });
    }
    return rows;
}
function historyFloor(queue, state, back = exports.HISTORY_BACK) {
    return Math.max(state.startedAt, queue.index - back, 0);
}
function shownFrom(queue, state) {
    if (!(0, playQueue_1.current)(queue))
        return queue.tracks.length;
    const playing = unitStart(state, queue.index);
    let place = historyFloor(queue, state);
    while (place < playing && state.marks[place]?.from === 'one')
        place++;
    return Math.min(place, playing);
}
function shownKeys(queue, limit = exports.UP_NEXT_DRAWN) {
    const state = queue.upNext;
    const keys = new Set();
    if (!state || !(0, playQueue_1.current)(queue))
        return keys;
    const { addedEnd, listEnd } = layout(queue, state);
    const listed = unitsIn(state, addedEnd, listEnd);
    const end = listed.length > limit ? listed[limit] : listEnd;
    for (let place = shownFrom(queue, state); place < end; place++)
        keys.add(state.marks[place].key);
    return keys;
}
function wentBack(queue, index) {
    const state = queue.upNext;
    if (!state)
        return { ...queue, index };
    const start = unitStart(state, index);
    if (start >= state.startedAt)
        return { ...queue, index };
    return { ...queue, index, upNext: { ...state, startedAt: start } };
}
function listTitle(source, again) {
    const album = oneAlbum(source);
    const title = album !== null ? `From ${album}` : 'Still to play';
    return again ? `${title}, again` : title;
}
function queuedWords(how, label) {
    return how === 'next' ? `Playing next: ${label}` : `Added to Up Next: ${label}`;
}
function repeatLabel(repeat) {
    return repeat === 'all' ? 'Repeat all' : repeat === 'one' ? 'Repeat one' : 'Repeat';
}
function shuffleLabel(scope) {
    if (!scope)
        return 'Shuffle';
    return `Shuffle - shuffling ${scope === 'store' ? 'all music' : 'your whole library'}`;
}
function nextRepeat(repeat) {
    return exports.REPEATS[(exports.REPEATS.indexOf(repeat) + 1) % exports.REPEATS.length];
}
function upNextLabel(shuffle, repeat) {
    if (shuffle && repeat !== 'off')
        return `Up Next - Shuffle and ${repeatLabel(repeat)}`;
    if (shuffle)
        return 'Up Next - Shuffle on';
    if (repeat !== 'off')
        return `Up Next - ${repeatLabel(repeat)}`;
    return 'Up Next';
}
