/**
 * Up Next, shuffle and repeat (2.0.0-player.57) - James, 2026-10-20: "i need shuffle, loop, and queue options
 * across the board. in the player, browse, etc." What plays after the song playing, and how Play Next, Play
 * Last, a move, a removal, Shuffle and Repeat change it.
 *
 * The engine's queue stays lib/playQueue's `{ tracks, index }`, and "the song after this one" stays
 * `index + 1` for everything that reads it - lib/gapless's standby and handover, the gapless stream. Up
 * Next's account rides beside it as an extra field (`upNext`, UpNextQueue below), which every
 * `{ ...queue, index }` in the engine already carries: one Mark per entry - where it came from (the list
 * playTracks was given, a song added, a copy Repeat One put there), its place in that list, and which time
 * round of the list it belongs to.
 *
 * REPEAT IS THE QUEUE, UNROLLED. The stream (player/streamSource.ts) places songs at `last + 1` and can't go
 * back to index 0, so Repeat is not a mode anything consults at the end of the queue: Repeat All puts the
 * next time round of the list into the queue ahead of where anything looks (toppedUp, once a song has been
 * heard), and Repeat One puts copies of the song after it. The stream reads them as it reads an album's
 * songs and joins them the same way, sample to sample; a standby gets them ready as any next song. Up Next
 * shows neither the copies nor the later times round.
 *
 * THE INVARIANT, held by every function here (ui/test/upnext.sim.cjs checks it after every step of 2,000
 * random runs): after `index` the entries run Repeat One's copies, then the songs added, then the list's
 * songs time round by time round (`pass` never going down) - and every edit keeps `tracks[0..index]`,
 * `marks[0..index]` and `index` exactly: only what comes after the song playing ever changes. Every edit
 * hands back the SAME object when it changes nothing, so the engine can skip it. (jumpedTo's list edit puts
 * the list's songs down to the row ahead of Playing Next, for the moment until the engine moves to its
 * index.) Previous can leave the order after the song playing as it played (a list's rounds never going
 * down, songs added among them); Up Next draws it as it will play. A queue with no `upNext` - EMPTY_QUEUE -
 * is a plain queue: each edit hands it back as it is, and onward, backward and pastCopies answer as
 * nextIndex and previousAction would.
 *
 * HISTORY (2.1.3) is the queue's entries before the song playing - exactly what Previous walks back through,
 * so the two never disagree: from where listening began (`startedAt`; Previous back before it moves it down,
 * wentBack) and at most HISTORY_BACK entries back (what a reload keeps, so History after one is the same). A
 * UNIT - an entry and the Repeat One copies straight after it - is one row there as in Up Next, keyed by its
 * first entry, and every row either draws is reached by its tap (jumpedTo): Up Next's moves the place onto it,
 * History's plays its song again. A unit is ONE song: whatever takes a song out of the queue takes its copies with
 * it (withShuffle, withRepeat - 2.1.3 review), or they'd join the row before them. upnext.sim.cjs holds all of it by
 * property.
 *
 * Pure: nothing here fetches, touches the page or imports Preact (app-rules.sim.cjs holds that).
 */

import type { Level, QueuedAs } from './loudness'
import { EMPTY_QUEUE, current, nextIndex, previousAction, type PlayQueue, type PreviousAction, type QueueTrack } from './playQueue'

export type Repeat = 'off' | 'all' | 'one'

/** The Repeat button's cycle: off -> all -> one -> off. */
export const REPEATS: readonly Repeat[] = ['off', 'all', 'one']

/** Where one entry of the queue came from. */
export type From =
  /** the list playTracks was given - an album, an artist's albums, a library's shuffle */
  | 'source'
  /** Play Next or Play Last */
  | 'added'
  /** a copy Repeat One put after the song */
  | 'one'

export interface Mark {
  /** unique in this queue: what a row of Up Next, a move, a removal and a jump name it by */
  key: number
  from: From
  /** a 'source' entry's place in `source` (a copy: its original's); -1 for a song added */
  at: number
  /** which time round of the list (0 the first; Repeat All's later ones 1, 2, ...); -1 for a song added */
  pass: number
}

/** (Part B) A whole library's shuffle, played a page at a time: the order deadwax holds under `token`, how
 *  many songs it has, how many of them are in the queue, and whose library it is. */
export interface Paged {
  token: string
  total: number
  fetched: number
  scope: 'yours' | 'store'
  /** (2.0.0-player.62) the level the shuffle was queued at (lib/loudness.ts) - its later pages are queued at it
   *  too (app/useShuffleFeed.ts), so a change of setting never levels a shuffle two ways. None under Off. */
  level?: Level
}

export interface UpNextState {
  /** (2.1.15) the queue's identity, made as it starts (queueId) and carried by every edit of it - by the snapshot too, so
   *  a queue put back on another device is the same queue: what a start of a song says it was begun in
   *  (lib/playHistory.ts), so each start is drawn once - by this queue's own rows while they show its entry, else among
   *  the older plays above them */
  id: string
  /** one per entry of the queue's tracks, in step with them: always the same length */
  marks: Mark[]
  /** the list as playTracks was given it, in its own order */
  source: QueueTrack[]
  shuffle: boolean
  nextKey: number
  /** where listening began: the first time round's songs before it were never heard; Previous back before it moves
   *  it down (wentBack) */
  startedAt: number
  /** the list's songs taken out of a time round - removed only - so a shuffle doesn't bring them back (2.1.3: a song
   *  jumped over stays behind the song jumped to, among those heard) */
  left: { pass: number; at: number }[]
  /** (Part B) the library's shuffle this queue is, when it is one - the order of its last time round */
  paged?: Paged
  /** (Part B) the orders of the earlier times round still in the queue, by round, so a Repeat turned off that lets go
   *  of the later rounds goes back to the order of the round playing (withRepeat) */
  pagedRounds?: { pass: number; paged: Paged }[]
}

/** The engine's queue with Up Next's account of it. Every `{ ...queue, index }` in usePlayer carries it. */
export type UpNextQueue = PlayQueue & { upNext?: UpNextState }

/** What the song menu (app/QueueMenu.tsx) is opened with: one song or an album's songs, always in hand -
 *  and the album answers they came from, for Info (player/api.ts rememberAdded). */
export interface QueuePick<Album = { id: string }> {
  label: string
  tracks: QueueTrack[]
  albums: Album[]
  /** (2.0.0-player.62) how its songs are queued for the player's Normalization: 'album' for an album's own •••
   *  (the whole album), songs otherwise - lib/loudness.ts levelFor() */
  as?: QueuedAs
}

/** Songs a Repeat keeps queued past the song playing - well ahead of the stream's look for the next one. */
export const REPEAT_AHEAD = 2
/** The list's own rows Up Next draws; "And N more songs." past that. */
export const UP_NEXT_DRAWN = 100
/** Seconds of a song heard (or half of a shorter one) before Repeat tops the queue up. */
export const TOP_UP_HEARD_S = 2
/** How far back History reaches: entries before the song playing - resume.ts's RESUME_BEFORE, what a reload keeps, so
 *  History after one is History before it (resume.sim holds the two equal). */
export const HISTORY_BACK = 50

type Random = () => number

/** (2.1.15) A queue's id: the time in base 36 and eight random characters - no crypto.randomUUID (a plain http page
 *  has none), and never a call of startUpNext's `random`, so a shuffle's order is the same as before ids were. The
 *  random part from crypto.getRandomValues where there is one (a plain http page has it), Math.random otherwise.
 *  Always [A-Za-z0-9_-], 1 to 64 characters - what deadwax keeps (src/play_history.py QUEUE_ID). */
export function queueId(now: number = Date.now()): string {
  const digits = '0123456789abcdefghijklmnopqrstuvwxyz'
  const bytes = new Uint8Array(8)
  const crypto = (globalThis as { crypto?: { getRandomValues?: (array: Uint8Array) => Uint8Array } }).crypto
  if (typeof crypto?.getRandomValues === 'function') crypto.getRandomValues(bytes)
  else for (let i = 0; i < bytes.length; i++) bytes[i] = Math.floor(Math.random() * 256)
  return `${Math.max(0, Math.floor(now)).toString(36)}-${[...bytes].map((byte) => digits[byte % 36]).join('')}`
}

/** Fisher-Yates over a copy, exactly as startQueue() shuffles: the same calls of `random`, in the same order. */
function shuffled<T>(list: readonly T[], random: Random): T[] {
  const out = [...list]
  for (let i = out.length - 1; i > 0; i--) {
    const j = Math.floor(random() * (i + 1))
    ;[out[i], out[j]] = [out[j]!, out[i]!]
  }
  return out
}

/** The queue with new entries after the song playing - `tracks` and `marks` in step - and what else changed. */
function rebuilt(queue: UpNextQueue, state: UpNextState, tracks: QueueTrack[], marks: Mark[], more: Partial<UpNextState> = {}): UpNextQueue {
  return { ...queue, tracks, upNext: { ...state, marks, ...more } }
}

/** The end (exclusive) of the UNIT at `place`: the entry and the Repeat One copies straight after it - one row of Up
 *  Next or History, what Next and Previous step over as one song. */
function unitEnd(state: UpNextState, place: number): number {
  let end = place + 1
  while (state.marks[end]?.from === 'one') end++
  return end
}

/** Where the song playing's unit begins: back over the copies before it - backward()'s run. */
function unitStart(state: UpNextState, index: number): number {
  let place = index
  while (place > 0 && state.marks[place]?.from === 'one') place--
  return place
}

/** Where Repeat One's copies after the song playing end, where the songs added after them (Playing Next) end, and
 *  where the list Up Next draws after those ends - the shown round's songs, and any song added among them (Previous
 *  walked back across it: it plays where it played). */
function layout(queue: UpNextQueue, state: UpNextState): { copiesEnd: number; addedEnd: number; listEnd: number } {
  let copiesEnd = queue.index + 1
  while (state.marks[copiesEnd]?.from === 'one') copiesEnd++
  let addedEnd = copiesEnd
  while (state.marks[addedEnd]?.from === 'added') addedEnd = unitEnd(state, addedEnd)
  const shown = shownPass(queue)
  let listEnd = addedEnd
  while (listEnd < state.marks.length) {
    const mark = state.marks[listEnd]!
    if (mark.from === 'source' ? mark.pass !== shown : mark.from !== 'added') break
    listEnd = unitEnd(state, listEnd)
  }
  return { copiesEnd, addedEnd, listEnd }
}

/** The unit starts in [start, end). */
function unitsIn(state: UpNextState, start: number, end: number): number[] {
  const units: number[] = []
  for (let place = start; place < end; place = unitEnd(state, place)) units.push(place)
  return units
}

/** The position of the last of the list's songs at or before `index`; -1 for none. */
function lastSourceAt(state: UpNextState, index: number): number {
  for (let i = Math.min(index, state.marks.length - 1); i >= 0; i--) if (state.marks[i]!.from === 'source') return i
  return -1
}

/** The time round the song playing is in: the last of the list's songs at or before it (a song added, or a
 *  copy, is in the round of the list's song before it); -1 for none. */
function passPlaying(state: UpNextState, index: number): number {
  const at = lastSourceAt(state, index)
  return at < 0 ? -1 : state.marks[at]!.pass
}

/** The one album every song of the list is from, by name - or null for a list of several. */
function oneAlbum(source: readonly QueueTrack[]): string | null {
  const first = source[0]
  if (!first?.albumId) return null
  return source.every((track) => track.albumId === first.albumId) ? first.album : null
}

/**
 * The queue playTracks plays: exactly startQueue()'s tracks and index for the same `random` - the shuffle
 * done again over the list's places, with the same Fisher-Yates and the same calls, so every entry knows its
 * place in the list. Every entry the list's, in its first time round; `startedAt` the index it starts at (0
 * when shuffled). `paged` (Part B): the first page of a whole library's shuffle - its order is the shuffle. `id`
 * (2.1.15): a new queue's own, made after the shuffle.
 */
export function startUpNext(
  tracks: QueueTrack[], start: number | null, shuffle = false, random: Random = Math.random, paged?: Paged, id?: string,
): UpNextQueue {
  if (!tracks.length) return EMPTY_QUEUE
  const index = Math.min(Math.max(start ?? 0, 0), tracks.length - 1)
  const places = tracks.map((_, at) => at)
  const order = !shuffle ? places : start === null ? shuffled(places, random) : [index, ...shuffled(places.filter((at) => at !== index), random)]
  return {
    tracks: order.map((at) => tracks[at]!),
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
  }
}

/**
 * Repeat's songs, queued ahead of where anything looks. 'all': while fewer than REPEAT_AHEAD entries follow
 * the song playing, one more time round of the list - in its own order, or freshly shuffled with Shuffle on,
 * never starting with the song that ends the round before it (with more than one song in the list). Songs
 * added are never copied: they play once. 'one': the song playing's copies after it, made up to REPEAT_AHEAD
 * at the end of the copies there are (before any song added). 'off', or topped up already: the same queue.
 * (Part B) A library's shuffle is topped up by its feed (app/useShuffleFeed.ts), not here.
 */
export function toppedUp(queue: UpNextQueue, repeat: Repeat, random: Random = Math.random): UpNextQueue {
  const state = queue.upNext
  const playing = current(queue)
  if (!state || repeat === 'off' || !playing) return queue
  if (repeat === 'one') {
    //? the copies of THIS song straight after it (Previous back across a run of another song's leaves those)
    let end = queue.index + 1
    while (state.marks[end]?.from === 'one' && queue.tracks[end]?.id === playing.id) end++
    const have = end - queue.index - 1
    if (have >= REPEAT_AHEAD) return queue
    const count = REPEAT_AHEAD - have
    const original = state.marks[queue.index]!
    const copies: Mark[] = Array.from({ length: count }, (_, i) => ({ key: state.nextKey + i, from: 'one', at: original.at, pass: original.pass }))
    return rebuilt(
      queue, state,
      [...queue.tracks.slice(0, end), ...copies.map(() => playing), ...queue.tracks.slice(end)],
      [...state.marks.slice(0, end), ...copies, ...state.marks.slice(end)],
      { nextKey: state.nextKey + count },
    )
  }
  if (state.paged || !state.source.length || queue.tracks.length - queue.index - 1 >= REPEAT_AHEAD) return queue
  const tracks = [...queue.tracks]
  const marks = [...state.marks]
  let nextKey = state.nextKey
  while (tracks.length - queue.index - 1 < REPEAT_AHEAD) {
    const last = lastSourceAt({ ...state, marks }, marks.length - 1)
    const pass = (last < 0 ? -1 : marks[last]!.pass) + 1
    const order = state.source.map((_, at) => at)
    let round = state.shuffle ? shuffled(order, random) : order
    //? a new order never starts with the song that ended the round before - with any other song to start with
    const ending = last < 0 ? undefined : tracks[last]?.id
    if (state.shuffle && round.length > 1 && ending !== undefined && state.source[round[0]!]!.id === ending) {
      const later = round.map((at, place) => ({ at, place })).filter(({ at, place }) => place > 0 && state.source[at]!.id !== ending)
      const pick = later[Math.floor(random() * later.length)]
      if (pick) {
        round = [...round]
        ;[round[0], round[pick.place]] = [round[pick.place]!, round[0]!]
      }
    }
    for (const at of round) {
      tracks.push(state.source[at]!)
      marks.push({ key: nextKey++, from: 'source', at, pass })
    }
  }
  return rebuilt(queue, state, tracks, marks, { nextKey })
}

/**
 * Repeat changed to `repeat`: anything else than One lets go of the copies after the song playing; anything
 * else than All lets go of the later times round (the list's songs after the song playing of a round later
 * than its own). The engine then tops the queue up for the new mode (toppedUp).
 */
export function withRepeat(queue: UpNextQueue, repeat: Repeat): UpNextQueue {
  const state = queue.upNext
  if (!state) return queue
  const round = passPlaying(state, queue.index)
  //? (2.1.3 review) a later round's song goes with its own copies (Previous walked back across it): left, they'd join
  //? the row before them - History naming one song where Previous plays another
  const goes = (mark: Mark, place: number): boolean => {
    if (place <= queue.index) return false
    if (mark.from === 'one') {
      if (repeat !== 'one') return true
      const song = unitStart(state, place)
      return song > queue.index && goes(state.marks[song]!, song)
    }
    return repeat !== 'all' && mark.from === 'source' && mark.pass > round
  }
  if (!state.marks.some(goes)) return queue
  const marks = state.marks.filter((mark, place) => !goes(mark, place))
  //? (Part B) a library's shuffle whose later rounds went: back to the order of the last round left, so its feed
  //? judges that round's order - whole, with Repeat off, and the shuffle ends - not the next round's
  const last = lastSourceAt({ ...state, marks }, marks.length - 1)
  const pass = last < 0 ? -1 : marks[last]!.pass
  const back = state.paged && state.pagedRounds?.find((held) => held.pass === pass)
  const more: Partial<UpNextState> = back
    ? { paged: back.paged, pagedRounds: state.pagedRounds!.filter((held) => held.pass < pass) }
    : {}
  return rebuilt(queue, state, queue.tracks.filter((_, place) => !goes(state.marks[place]!, place)), marks, more)
}

/**
 * Shuffle on or off for the queue playing; the song playing goes on, and the songs added keep their order
 * (and Repeat One's copies of the song playing their place; a list's song's copies go with it). The later times
 * round go - the engine's toppedUp grows them again in the new order. Let the round be the song playing's (the
 * list's song at or before it).
 *
 *  - ON: the list's songs not yet heard this time round, in a new order (Apple's way) - every place of the
 *    list but the song playing's, the places heard this round (from where the round began - `startedAt` for
 *    the first - up to the song playing) and the places taken out of it (`left`). An album started at song 5
 *    and shuffled at song 7 shuffles 1-4 and 8-12. Entries already queued for those places keep their keys.
 *    With nothing left unheard (the round's last song playing), the next time round is the shuffled one, as
 *    toppedUp makes it.
 *  - OFF: the list's own order from the song playing's place in it - the places after the last of the list's
 *    songs at or before it, less those taken out this round - as new entries. A song heard in the shuffle can
 *    come round again (Apple Music does the same).
 *
 * (Part B) A library's shuffle is the same queue: its order IS the shuffle.
 */
export function withShuffle(queue: UpNextQueue, on: boolean, random: Random = Math.random): UpNextQueue {
  const state = queue.upNext
  if (!state || state.paged || state.shuffle === on || !current(queue)) return queue
  const { index } = queue
  const round = passPlaying(state, index)
  const left = new Set(state.left.filter((gone) => gone.pass === round).map((gone) => gone.at))
  const places = state.source.map((_, at) => at)
  let wanted: number[]
  if (on) {
    let roundStart = round === 0 ? state.startedAt : state.marks.findIndex((mark) => mark.from === 'source' && mark.pass === round)
    if (roundStart < 0) roundStart = index
    const heard = new Set<number>()
    for (let place = roundStart; place <= index; place++) {
      const mark = state.marks[place]!
      if (mark.from === 'source' && mark.pass === round) heard.add(mark.at)
    }
    const playingAt = state.marks[index]!.at
    if (playingAt >= 0) heard.add(playingAt)
    wanted = shuffled(places.filter((at) => !heard.has(at) && !left.has(at)), random)
  } else {
    const last = lastSourceAt(state, index)
    const lastAt = last < 0 ? -1 : state.marks[last]!.at
    wanted = places.filter((at) => at > lastAt && !left.has(at))
  }
  //? shuffled ON, the entries already queued this round for those places keep their keys
  const queued = new Map<number, Mark>()
  if (on) {
    for (let place = index + 1; place < state.marks.length; place++) {
      const mark = state.marks[place]!
      if (mark.from === 'source' && mark.pass === round) queued.set(mark.at, mark)
    }
  }
  let nextKey = state.nextKey
  const fresh: Mark[] = wanted.map((at) => queued.get(at) ?? { key: nextKey++, from: 'source', at, pass: Math.max(round, 0) })
  //? the list's songs after the song playing go - each with its Repeat One copies (Previous walked back across it), which
  //? left would join the row before them (2.1.3 review); the song playing's own copies and the songs added, theirs
  //? with them, stay
  const stays = (mark: Mark, place: number) => {
    if (place <= index) return true
    const song = mark.from === 'one' ? unitStart(state, place) : place
    return song <= index || state.marks[song]!.from !== 'source'
  }
  return rebuilt(
    queue, state,
    [...queue.tracks.filter((_, place) => stays(state.marks[place]!, place)), ...fresh.map((mark) => state.source[mark.at]!)],
    [...state.marks.filter(stays), ...fresh],
    { shuffle: on, nextKey },
  )
}

/** New entries, the songs added, at `place`. */
function added(queue: UpNextQueue, state: UpNextState, tracks: readonly QueueTrack[], place: number): UpNextQueue {
  const marks: Mark[] = tracks.map((_, i) => ({ key: state.nextKey + i, from: 'added', at: -1, pass: -1 }))
  return rebuilt(
    queue, state,
    [...queue.tracks.slice(0, place), ...tracks, ...queue.tracks.slice(place)],
    [...state.marks.slice(0, place), ...marks, ...state.marks.slice(place)],
    { nextKey: state.nextKey + tracks.length },
  )
}

/** Play Next: `tracks`, in their order, straight after the song playing's copies - the head of Playing Next. */
export function withNext(queue: UpNextQueue, tracks: readonly QueueTrack[]): UpNextQueue {
  const state = queue.upNext
  if (!state || !tracks.length || !current(queue)) return queue
  return added(queue, state, tracks, layout(queue, state).copiesEnd)
}

/** Play Last: after the songs already added (after the copies, with none) - the end of Playing Next, still
 *  ahead of the rest of the list, as Apple Music has it. */
export function withLast(queue: UpNextQueue, tracks: readonly QueueTrack[]): UpNextQueue {
  const state = queue.upNext
  if (!state || !tracks.length || !current(queue)) return queue
  return added(queue, state, tracks, layout(queue, state).addedEnd)
}

/** Where the entry `key` is, and the group of Up Next's rows it is in: Playing Next (the songs added), or the
 *  list as Up Next shows it (the shown round). Null for a key at or before the song playing, a copy, a later
 *  round, or one the queue doesn't have. */
function groupOf(queue: UpNextQueue, state: UpNextState, key: number): { place: number; start: number; end: number; added: boolean } | null {
  const place = state.marks.findIndex((mark) => mark.key === key)
  const { copiesEnd, addedEnd, listEnd } = layout(queue, state)
  if (place < copiesEnd || state.marks[place]!.from === 'one') return null
  if (place < addedEnd) return { place, start: copiesEnd, end: addedEnd, added: true }
  return place < listEnd ? { place, start: addedEnd, end: listEnd, added: false } : null
}

/** A row of Up Next out. One of the list's is noted as taken out of its round (`left`). */
export function withoutKey(queue: UpNextQueue, key: number): UpNextQueue {
  const state = queue.upNext
  if (!state) return queue
  const group = groupOf(queue, state, key)
  if (!group) return queue
  const mark = state.marks[group.place]!
  const end = unitEnd(state, group.place)
  const stays = (_: unknown, place: number) => place < group.place || place >= end
  return rebuilt(
    queue, state,
    queue.tracks.filter(stays),
    state.marks.filter(stays),
    mark.from === 'source' ? { left: [...state.left, { pass: mark.pass, at: mark.at }] } : {},
  )
}

/** A row of Up Next to place `to` (0-based) of its own group - Playing Next, or the list. */
export function movedKey(queue: UpNextQueue, key: number, to: number): UpNextQueue {
  const state = queue.upNext
  if (!state) return queue
  const group = groupOf(queue, state, key)
  if (!group) return queue
  const units = unitsIn(state, group.start, group.end)
  const from = units.indexOf(group.place)
  const dest = Math.max(0, Math.min(units.length - 1, Math.round(to)))
  if (dest === from) return queue
  const order = units.map((start) => ({ start, end: unitEnd(state, start) }))
  const [taken] = order.splice(from, 1)
  order.splice(dest, 0, taken!)
  const move = <T>(list: readonly T[]): T[] =>
    [...list.slice(0, group.start), ...order.flatMap(({ start, end }) => list.slice(start, end)), ...list.slice(group.end)]
  return rebuilt(queue, state, move(queue.tracks), move(state.marks))
}

/** Clear: Playing Next out - the songs added straight after the song playing, the group Clear heads (a song added
 *  further on, that Previous walked back across, plays where it played and stays). */
export function withoutAdded(queue: UpNextQueue): UpNextQueue {
  const state = queue.upNext
  if (!state) return queue
  const { copiesEnd, addedEnd } = layout(queue, state)
  if (addedEnd === copiesEnd) return queue
  const stays = (_: unknown, place: number) => place < copiesEnd || place >= addedEnd
  return rebuilt(queue, state, queue.tracks.filter(stays), state.marks.filter(stays))
}

/** A row's tap, as the engine makes it: the queue to put in place first (an edit of what comes after the song playing,
 *  or the same object), and the entry to move to then. */
export interface Jump {
  queue: UpNextQueue
  index: number
}

/**
 * A row's tap (James, 2026-11-11: "6 and 7 stay behind 8: Previous from 8 plays 7, then 6, as on the album"). Nothing
 * is dropped: the place moves to the row, and the rows it passes stay where they are, behind it.
 *
 *  - A row of the list: the place moves there; Playing Next goes straight after it (and its copies) - songs added
 *    still play next - and the list's rows above it stay behind it, in their order, where Previous finds them.
 *  - A row of Playing Next: the place moves there; the songs added above it stay behind it.
 *  - A row of History (an entry before the song playing's unit): the song AGAIN - a new entry of it, a song added,
 *    straight after the song playing's copies (where Play Next goes), moved to; the songs after are as they were, and
 *    History is never rewritten: it is what played, and the song played again joins it as played.
 *
 * `index` is the entry to move to, in `queue`; the edit keeps `tracks[0..index]` of the queue it was given (the
 * engine's replaceUpcoming takes it as any edit). Null for the song playing (or one of its copies), a key it doesn't
 * have, a row Up Next doesn't draw (a later time round, a copy), or one History doesn't (before where listening
 * began, past HISTORY_BACK) - every row drawn is one a tap reaches, and nothing else is.
 */
export function jumpedTo(queue: UpNextQueue, key: number): Jump | null {
  const state = queue.upNext
  if (!state || !current(queue)) return null
  const place = state.marks.findIndex((mark) => mark.key === key)
  if (place < 0) return null
  const { copiesEnd, addedEnd } = layout(queue, state)
  if (place < unitStart(state, queue.index)) {
    if (!historyRows(queue).some((row) => row.key === key)) return null
    return { queue: added(queue, state, [queue.tracks[place]!], copiesEnd), index: copiesEnd }
  }
  const group = groupOf(queue, state, key)
  if (!group) return null
  if (group.added || addedEnd === copiesEnd) return { queue, index: group.place }
  //? into the list with songs added: they go after the row's unit; by old place, up to the copies, the list up to and
  //? including the row, Playing Next, the rest
  const end = unitEnd(state, group.place)
  const places: number[] = []
  for (let at = 0; at < copiesEnd; at++) places.push(at)
  for (let at = addedEnd; at < end; at++) places.push(at)
  for (let at = copiesEnd; at < addedEnd; at++) places.push(at)
  for (let at = end; at < state.marks.length; at++) places.push(at)
  return {
    queue: rebuilt(queue, state, places.map((at) => queue.tracks[at]!), places.map((at) => state.marks[at]!)),
    index: group.place - (addedEnd - copiesEnd),
  }
}

/** Next: the first entry after the song playing that isn't one of Repeat One's copies; null if none. */
export function onward(queue: UpNextQueue): number | null {
  const state = queue.upNext
  if (!state) return nextIndex(queue)
  for (let place = queue.index + 1; place < state.marks.length; place++) if (state.marks[place]!.from !== 'one') return place
  return null
}

/**
 * Previous: previousAction()'s rule, kept in ONE place - the song again past RESTART_AFTER_SECONDS or at the
 * first song - but going back passes over the run of Repeat One's copies the song playing is part of (the
 * copies before it, and its original) to the entry before them; with none before them, the song again.
 */
export function backward(queue: UpNextQueue, position: number): PreviousAction {
  const action = previousAction(queue, position)
  const state = queue.upNext
  if (action.kind === 'restart' || !state) return action
  let place = queue.index
  while (place > 0 && state.marks[place]?.from === 'one') place--
  return place > 0 ? { kind: 'go', index: place - 1 } : { kind: 'restart' }
}

/** A failed song's skip: the first entry at or after `from` that isn't one of Repeat One's copies - a song
 *  that won't play isn't asked for again once per copy. Null if none: the queue stops there, as at its end. */
export function pastCopies(queue: UpNextQueue, from: number): number | null {
  const state = queue.upNext
  if (!state) return from >= 0 && from < queue.tracks.length ? from : null
  for (let place = Math.max(from, 0); place < state.marks.length; place++) if (state.marks[place]!.from !== 'one') return place
  return null
}

/** The time round of the list Up Next shows: the first of the list's songs after the song playing; -1 for none. */
export function shownPass(queue: UpNextQueue): number {
  const state = queue.upNext
  if (!state) return -1
  for (let place = queue.index + 1; place < state.marks.length; place++) {
    const mark = state.marks[place]!
    if (mark.from === 'source') return mark.pass
  }
  return -1
}

/** (Part B) More of a library's shuffle, from its feed - unless the queue playing is no longer that shuffle
 *  (`token`), the same queue. Appended at the END as the list's songs: the rest of this time round, or -
 *  the whole order fetched already, `next` a fresh one (Repeat All) - the next time round, `next` the
 *  shuffle from then on. A fresh order for one that went (deadwax restarted) is the rest of this round. */
export function withMore(queue: UpNextQueue, token: string, tracks: readonly QueueTrack[], next?: Paged): UpNextQueue {
  const state = queue.upNext
  const paged = state?.paged
  //? nothing to append - a fresh order of an emptied library too: the same queue, so its feed asks no more
  if (!state || !paged || paged.token !== token || !tracks.length) return queue
  const round = next && paged.fetched >= paged.total
  const last = lastSourceAt(state, state.marks.length - 1)
  const before = last < 0 ? 0 : state.marks[last]!.pass
  const pass = before + (round ? 1 : 0)
  const marks: Mark[] = tracks.map((_, i) => ({ key: state.nextKey + i, from: 'source', at: state.source.length + i, pass }))
  //? a next round: the order of the round before kept by its round, for a Repeat turned off (withRepeat); rounds
  //? before the song playing's can no longer be gone back to
  const playing = passPlaying(state, queue.index)
  const pagedRounds = round
    ? [...(state.pagedRounds ?? []).filter((held) => held.pass >= playing), { pass: before, paged }]
    : state.pagedRounds
  return rebuilt(queue, state, [...queue.tracks, ...tracks], [...state.marks, ...marks], {
    source: [...state.source, ...tracks],
    nextKey: state.nextKey + tracks.length,
    paged: next ? { ...next, fetched: tracks.length } : { ...paged, fetched: paged.fetched + tracks.length },
    ...(pagedRounds ? { pagedRounds } : {}),
  })
}

/** One row of Up Next: the entry's key (so a song in twice is two rows), and its song. */
export interface UpNextRow {
  key: number
  track: QueueTrack
}

export interface UpNextView {
  /** History: the songs before the song playing, oldest first - one row a unit, from where the listening began
   *  (`startedAt`) and at most HISTORY_BACK entries back */
  history: UpNextRow[]
  playing: QueueTrack | null
  /** Playing Next: the songs added, after the copies - all of them */
  added: UpNextRow[]
  /** the list's songs still to play this time round - the first `limit`, and how many more (2.1.3: a song added that
   *  Previous walked back across is among them, where it plays) */
  list: { title: string; rows: UpNextRow[]; more: number } | null
  /** what comes after: "Then … again from the top." or "Nothing after this song." */
  then: string | null
  repeatOne: boolean
}

/** What Up Next (app/UpNext.tsx) draws: History above the song playing (2.1.3), then what plays after it - neither
 *  Repeat One's copies nor the later times round. */
export function upNextView(queue: UpNextQueue, repeat: Repeat, limit: number = UP_NEXT_DRAWN): UpNextView {
  const playing = current(queue)
  const state = queue.upNext
  if (!playing || !state) return { history: [], playing, added: [], list: null, then: null, repeatOne: false }
  const { copiesEnd, addedEnd, listEnd } = layout(queue, state)
  const row = (place: number): UpNextRow => ({ key: state.marks[place]!.key, track: queue.tracks[place]! })
  const addedRows = unitsIn(state, copiesEnd, addedEnd).map(row)
  const shown = shownPass(queue)
  const listed = unitsIn(state, addedEnd, listEnd)
  const paged = state.paged
  const pending = paged ? Math.max(0, paged.total - paged.fetched) : 0
  const again = shown > passPlaying(state, queue.index)
  const title = paged ? `${paged.scope === 'yours' ? 'Your library' : 'All music'}, shuffled${again ? ', again' : ''}` : listTitle(state.source, again)
  const list = listed.length || pending
    ? { title, rows: listed.slice(0, limit).map(row), more: Math.max(0, listed.length - limit) + pending }
    : null
  //? (2.0.5) the collection's shuffle is "all music" here too, as its heading says - never "everything"
  const name = paged ? (paged.scope === 'yours' ? 'your library' : 'all music') : oneAlbum(state.source) ?? 'the list'
  const then = repeat === 'all'
    ? state.shuffle ? `Then ${name} again, in a new order.` : `Then ${name} again from the top.`
    : repeat === 'off' && queue.index >= queue.tracks.length - 1 ? 'Nothing after this song.' : null
  return { history: historyRows(queue), playing, added: addedRows, list, then, repeatOne: repeat === 'one' }
}

/** History: the units before the song playing's, oldest first - from `startedAt` (the list's songs before where
 *  listening began were never heard) and no further back than HISTORY_BACK entries before the song playing - what a
 *  reload keeps (resume.ts toSave), so it draws the same after one. One row a unit, keyed by its first entry. A run of
 *  copies at that edge, its song further back, isn't a row. */
export function historyRows(queue: UpNextQueue, back: number = HISTORY_BACK): UpNextRow[] {
  const state = queue.upNext
  if (!state || !current(queue)) return []
  const from = historyFloor(queue, state, back)
  const rows: UpNextRow[] = []
  for (let place = from; place < unitStart(state, queue.index); place = unitEnd(state, place)) {
    if (state.marks[place]!.from !== 'one') rows.push({ key: state.marks[place]!.key, track: queue.tracks[place]! })
  }
  return rows
}

/** How far back History reaches: from where listening began, no further than `back` entries before the song playing. */
function historyFloor(queue: UpNextQueue, state: UpNextState, back: number = HISTORY_BACK): number {
  return Math.max(state.startedAt, queue.index - back, 0)
}

/** (2.1.15) Where the entries Up Next's rows stand for begin - History's first row (its floor, past a run of copies there
 *  whose song is further back, never a row), or the song playing's unit if that comes first. The queue's length with
 *  nothing playing. */
function shownFrom(queue: UpNextQueue, state: UpNextState): number {
  if (!current(queue)) return queue.tracks.length
  const playing = unitStart(state, queue.index)
  let place = historyFloor(queue, state)
  while (place < playing && state.marks[place]?.from === 'one') place++
  return Math.min(place, playing)
}

/** (2.1.15) The keys of the entries Up Next's rows stand for - exactly what upNextView(queue, _, limit) draws, each row's
 *  entry with its copies: History's units, the song playing's, the songs added, and the list's first `limit` rows. One
 *  run, from shownFrom to the end of the last list row drawn - NEVER a later time round (Repeat All's, which Up Next
 *  sums up in a line) or a list row past `limit` ("And N more songs"), though Previous can leave songs begun there.
 *  lib/playHistory.ts draws a start of any other entry among the older plays above History, so each is drawn once
 *  (history.sim judges it by the view's own rows). None with nothing playing. */
export function shownKeys(queue: UpNextQueue, limit: number = UP_NEXT_DRAWN): Set<number> {
  const state = queue.upNext
  const keys = new Set<number>()
  if (!state || !current(queue)) return keys
  const { addedEnd, listEnd } = layout(queue, state)
  const listed = unitsIn(state, addedEnd, listEnd)
  const end = listed.length > limit ? listed[limit]! : listEnd
  for (let place = shownFrom(queue, state); place < end; place++) keys.add(state.marks[place]!.key)
  return keys
}

/** Previous's move: `{ ...queue, index }` - and, back before where listening began, `startedAt` moved down to the
 *  unit landed in, so History shows the songs played from there. The same tracks: the stream's seek still applies. */
export function wentBack(queue: UpNextQueue, index: number): UpNextQueue {
  const state = queue.upNext
  if (!state) return { ...queue, index }
  const start = unitStart(state, index)
  if (start >= state.startedAt) return { ...queue, index }
  return { ...queue, index, upNext: { ...state, startedAt: start } }
}

/** The list's heading in Up Next: "From Mezzanine" for one album's songs, else "Still to play" - with
 *  `again` (a later time round than the song playing's), "From Mezzanine, again". */
export function listTitle(source: readonly QueueTrack[], again: boolean): string {
  const album = oneAlbum(source)
  const title = album !== null ? `From ${album}` : 'Still to play'
  return again ? `${title}, again` : title
}

/** The app's notice for what Play Next or Play Last did. */
export function queuedWords(how: 'next' | 'last', label: string): string {
  return how === 'next' ? `Playing next: ${label}` : `Added to Up Next: ${label}`
}

/** What the Repeat chip says - and (2.0.14) Now Playing's Repeat button on a phone, an icon whose name it is. */
export function repeatLabel(repeat: Repeat): string {
  return repeat === 'all' ? 'Repeat all' : repeat === 'one' ? 'Repeat one' : 'Repeat'
}

/** The Shuffle buttons that are an icon alone - the desktop's player bar's and (2.0.14) Now Playing's on a phone -
 *  named: "Shuffle", or during a whole library's shuffle (Part B; `scope`, the queue's `upNext.paged.scope`), whose
 *  order IS the shuffle so it can't be turned off, named for why in Up Next's words - all music (Browse's Songs) or
 *  your whole library (your albums). */
export function shuffleLabel(scope: Paged['scope'] | undefined): string {
  if (!scope) return 'Shuffle'
  return `Shuffle - shuffling ${scope === 'store' ? 'all music' : 'your whole library'}`
}

/** The Repeat button's next setting: off -> all -> one -> off. */
export function nextRepeat(repeat: Repeat): Repeat {
  return REPEATS[(REPEATS.indexOf(repeat) + 1) % REPEATS.length]!
}

/** Now Playing's Up Next button, named with what is on: "Up Next - Shuffle and Repeat all" (2.0.7: "Up Next", as
 *  the sheet, the player bar and every notice say it - it was "Up next" here). */
export function upNextLabel(shuffle: boolean, repeat: Repeat): string {
  if (shuffle && repeat !== 'off') return `Up Next - Shuffle and ${repeatLabel(repeat)}`
  if (shuffle) return 'Up Next - Shuffle on'
  if (repeat !== 'off') return `Up Next - ${repeatLabel(repeat)}`
  return 'Up Next'
}
