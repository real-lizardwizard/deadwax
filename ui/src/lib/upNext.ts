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
 * hands back the SAME object when it changes nothing, so the engine can skip it. (jumpedTo alone puts the
 * row jumped to first, ahead of the added songs, for the moment until the engine moves onto it.) A queue
 * with no `upNext` - EMPTY_QUEUE - is a plain queue: each edit hands it back as it is, and onward,
 * backward and pastCopies answer as nextIndex and previousAction would.
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
  /** one per entry of the queue's tracks, in step with them: always the same length */
  marks: Mark[]
  /** the list as playTracks was given it, in its own order */
  source: QueueTrack[]
  shuffle: boolean
  nextKey: number
  /** the index playTracks started at: the first time round's songs before it were never heard */
  startedAt: number
  /** the list's songs taken out of a time round - removed, or jumped over - so a shuffle doesn't bring them back */
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

type Random = () => number

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

/** Where Repeat One's copies after the song playing end, and where the songs added after them end. */
function layout(queue: UpNextQueue, state: UpNextState): { copiesEnd: number; addedEnd: number } {
  let copiesEnd = queue.index + 1
  while (state.marks[copiesEnd]?.from === 'one') copiesEnd++
  let addedEnd = copiesEnd
  while (state.marks[addedEnd]?.from === 'added') addedEnd++
  return { copiesEnd, addedEnd }
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
 * when shuffled). `paged` (Part B): the first page of a whole library's shuffle - its order is the shuffle.
 */
export function startUpNext(
  tracks: QueueTrack[], start: number | null, shuffle = false, random: Random = Math.random, paged?: Paged,
): UpNextQueue {
  if (!tracks.length) return EMPTY_QUEUE
  const index = Math.min(Math.max(start ?? 0, 0), tracks.length - 1)
  const places = tracks.map((_, at) => at)
  const order = !shuffle ? places : start === null ? shuffled(places, random) : [index, ...shuffled(places.filter((at) => at !== index), random)]
  return {
    tracks: order.map((at) => tracks[at]!),
    index: shuffle ? 0 : index,
    upNext: {
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
  const goes = (mark: Mark, place: number) => place > queue.index &&
    ((repeat !== 'one' && mark.from === 'one') || (repeat !== 'all' && mark.from === 'source' && mark.pass > round))
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
 * (and Repeat One's copies their place). The later times round go - the engine's toppedUp grows them again
 * in the new order. Let the round be the song playing's (the list's song at or before it).
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
  const stays = (mark: Mark, place: number) => place <= index || mark.from !== 'source'
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
function groupOf(queue: UpNextQueue, state: UpNextState, key: number): { place: number; start: number; end: number } | null {
  const place = state.marks.findIndex((mark) => mark.key === key)
  if (place <= queue.index) return null
  const mark = state.marks[place]!
  const { copiesEnd, addedEnd } = layout(queue, state)
  if (mark.from === 'added') return place < addedEnd ? { place, start: copiesEnd, end: addedEnd } : null
  if (mark.from !== 'source') return null
  const shown = state.marks[addedEnd]?.pass
  if (mark.pass !== shown) return null
  let end = addedEnd
  while (state.marks[end]?.from === 'source' && state.marks[end]!.pass === shown) end++
  return place < end ? { place, start: addedEnd, end } : null
}

/** A row of Up Next out. One of the list's is noted as taken out of its round (`left`). */
export function withoutKey(queue: UpNextQueue, key: number): UpNextQueue {
  const state = queue.upNext
  if (!state) return queue
  const group = groupOf(queue, state, key)
  if (!group) return queue
  const mark = state.marks[group.place]!
  return rebuilt(
    queue, state,
    queue.tracks.filter((_, place) => place !== group.place),
    state.marks.filter((_, place) => place !== group.place),
    mark.from === 'source' ? { left: [...state.left, { pass: mark.pass, at: mark.at }] } : {},
  )
}

/** A row of Up Next to place `to` (0-based) of its own group - Playing Next, or the list. */
export function movedKey(queue: UpNextQueue, key: number, to: number): UpNextQueue {
  const state = queue.upNext
  if (!state) return queue
  const group = groupOf(queue, state, key)
  if (!group) return queue
  const from = group.place - group.start
  const dest = Math.max(0, Math.min(group.end - group.start - 1, Math.round(to)))
  if (dest === from) return queue
  const move = <T>(list: readonly T[]): T[] => {
    const inside = list.slice(group.start, group.end)
    const [taken] = inside.splice(from, 1)
    inside.splice(dest, 0, taken!)
    return [...list.slice(0, group.start), ...inside, ...list.slice(group.end)]
  }
  return rebuilt(queue, state, move(queue.tracks), move(state.marks))
}

/** Clear: every song added, after the song playing, out. */
export function withoutAdded(queue: UpNextQueue): UpNextQueue {
  const state = queue.upNext
  if (!state) return queue
  const goes = (mark: Mark, place: number) => place > queue.index && mark.from === 'added'
  if (!state.marks.some(goes)) return queue
  return rebuilt(queue, state, queue.tracks.filter((_, place) => !goes(state.marks[place]!, place)), state.marks.filter((mark, place) => !goes(mark, place)))
}

/**
 * A row's tap: the row `key` moved straight after the copies (where Play Next goes), and the rows ABOVE it in
 * its own group dropped - jumping into the list keeps Playing Next (it plays after the song jumped to), and
 * jumping into Playing Next drops only the songs added above it. The list's songs jumped over are noted as
 * taken out of their round. Null for a key it can't jump to. The engine then moves onto it as Next does.
 */
export function jumpedTo(queue: UpNextQueue, key: number): UpNextQueue | null {
  const state = queue.upNext
  if (!state) return null
  const group = groupOf(queue, state, key)
  if (!group) return null
  const { copiesEnd } = layout(queue, state)
  const mark = state.marks[group.place]!
  const over = state.marks.slice(group.start, group.place)
  //? the new order, by old place: up to the copies, the row, then everything else but the rows above it
  const places: number[] = []
  for (let place = 0; place < copiesEnd; place++) places.push(place)
  places.push(group.place)
  for (let place = copiesEnd; place < state.marks.length; place++) {
    if (place >= group.start && place <= group.place) continue
    places.push(place)
  }
  return rebuilt(
    queue, state,
    places.map((place) => queue.tracks[place]!),
    places.map((place) => state.marks[place]!),
    mark.from === 'source' ? { left: [...state.left, ...over.map((gone) => ({ pass: gone.pass, at: gone.at }))] } : {},
  )
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
  playing: QueueTrack | null
  /** Playing Next: the songs added, after the copies - all of them */
  added: UpNextRow[]
  /** the list's songs still to play this time round - the first `limit`, and how many more */
  list: { title: string; rows: UpNextRow[]; more: number } | null
  /** what comes after: "Then … again from the top." or "Nothing after this song." */
  then: string | null
  repeatOne: boolean
}

/** What Up Next (app/UpNext.tsx) draws: neither Repeat One's copies nor the later times round. */
export function upNextView(queue: UpNextQueue, repeat: Repeat, limit: number = UP_NEXT_DRAWN): UpNextView {
  const playing = current(queue)
  const state = queue.upNext
  if (!playing || !state) return { playing, added: [], list: null, then: null, repeatOne: false }
  const { copiesEnd, addedEnd } = layout(queue, state)
  const row = (place: number): UpNextRow => ({ key: state.marks[place]!.key, track: queue.tracks[place]! })
  const addedRows: UpNextRow[] = []
  for (let place = copiesEnd; place < addedEnd; place++) addedRows.push(row(place))
  const shown = shownPass(queue)
  const listed: number[] = []
  for (let place = addedEnd; place < state.marks.length; place++) {
    const mark = state.marks[place]!
    if (mark.from !== 'source' || mark.pass !== shown) break
    listed.push(place)
  }
  const paged = state.paged
  const pending = paged ? Math.max(0, paged.total - paged.fetched) : 0
  const again = shown > passPlaying(state, queue.index)
  const title = paged ? `${paged.scope === 'yours' ? 'Your library' : 'Everything'}, shuffled${again ? ', again' : ''}` : listTitle(state.source, again)
  const list = listed.length || pending
    ? { title, rows: listed.slice(0, limit).map(row), more: Math.max(0, listed.length - limit) + pending }
    : null
  const name = paged ? (paged.scope === 'yours' ? 'your library' : 'everything') : oneAlbum(state.source) ?? 'the list'
  const then = repeat === 'all'
    ? state.shuffle ? `Then ${name} again, in a new order.` : `Then ${name} again from the top.`
    : repeat === 'off' && queue.index >= queue.tracks.length - 1 ? 'Nothing after this song.' : null
  return { playing, added: addedRows, list, then, repeatOne: repeat === 'one' }
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

/** What the Repeat chip and the player bar's button say. */
export function repeatLabel(repeat: Repeat): string {
  return repeat === 'all' ? 'Repeat all' : repeat === 'one' ? 'Repeat one' : 'Repeat'
}

/** The Repeat button's next setting: off -> all -> one -> off. */
export function nextRepeat(repeat: Repeat): Repeat {
  return REPEATS[(REPEATS.indexOf(repeat) + 1) % REPEATS.length]!
}

/** Now Playing's Up next button, named with what is on: "Up next - Shuffle and Repeat all". */
export function upNextLabel(shuffle: boolean, repeat: Repeat): string {
  if (shuffle && repeat !== 'off') return `Up next - Shuffle and ${repeatLabel(repeat)}`
  if (shuffle) return 'Up next - Shuffle on'
  if (repeat !== 'off') return `Up next - ${repeatLabel(repeat)}`
  return 'Up next'
}
