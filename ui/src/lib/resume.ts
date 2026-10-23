/**
 * Resume what was playing (2.0.0-player.64) - James, 2026-10-22: "every time I open the app, whatever was playing is
 * gone." He chose "follows you everywhere": kept as the signed-in person's play queue in Navidrome, so the desktop
 * picks up where the phone stopped. On opening the app the queue, the song and the second come back PAUSED - iOS
 * starts sound only from a tap - and the next play carries on from there.
 *
 * Two places, written together and read together (src/play_queue.py, src/routes/navidrome.py /queue):
 *
 *  - NAVIDROME'S PLAY QUEUE, as the asker: the ids, the current index, the position. What any Subsonic app sees,
 *    and the authority on what was played last - so Navidrome's answer always decides WHAT is newest.
 *  - DEADWAX'S RECORD beside it (`kept`): the same ids and index, the position in seconds, and the snapshot below -
 *    the page's account of Up Next, which Navidrome can't hold. Believed only when Navidrome says deadwax saved last
 *    and its ids are deadwax's (equal, or deadwax's less songs Navidrome dropped as gone); anything else comes back
 *    as a PLAIN LIST - Navidrome's songs in its order, from its index, as playTracks(tracks, index) queues them.
 *
 * What is saved is a WINDOW: at most RESUME_BEFORE entries before the song playing and RESUME_MAX in all (toSave).
 * The snapshot (v1, made only by toSave, read only by fromSnapshot) lists the source by id, with the whole song
 * (`extra`) only for source songs outside the window, one character a level per entry ('a' album, 't' track,
 * '-' none). On reading, the songs are rebuilt one object per (id, level), shared by the entries and the source as
 * startUpNext shares them, every level re-fitted to this device's Normalization (relevel). A snapshot that doesn't
 * read back - another version, or a state failing its checks - gives the plain list of the same songs.
 *
 * And the rules of saving (saveDue) and of the notice and the device's name - all of it pure: nothing here fetches,
 * touches the page, keeps anything or imports Preact (ui/test/app-rules.sim.cjs holds that), so
 * ui/test/resume.sim.cjs holds every rule without a browser or a timer. app/useResume.ts is what acts on them.
 */

import type { Level, LevelledTrack, Normalization } from './loudness'
import { current, type QueueTrack } from './playQueue'
import { startUpNext, type Mark, type Paged, type UpNextQueue, type UpNextState } from './upNext'

/** The most entries saved, and of them the most before the song playing - the history Previous walks. */
export const RESUME_MAX = 2000
export const RESUME_BEFORE = 50
/** The snapshot's most characters; a bigger one is left out, and that queue comes back a plain list. */
export const RESUME_SNAPSHOT_MAX = 262_144
/** Seconds of playing between two saves of where it is. */
export const RESUME_EVERY_S = 30
/** A change of the songs or of Up Next is saved this long after the last of a burst; a song change this long after. */
export const RESUME_FULL_WAIT_MS = 2000
export const RESUME_AT_WAIT_MS = 1000
/** Coming back to the front asks again at most this often. */
export const RESUME_RECHECK_MS = 15_000
/** A window's focus asks only this long after it: on a desktop the click that focuses the window is often a press of
 *  Play itself, and an answer landing between its mousedown and its click would swap the queue under it - so the click
 *  lands first, and once it plays nothing is asked. (Coming back visible, as a phone's app does, asks at once: there the
 *  page shows before anything can be touched.) */
export const RESUME_FOCUS_GRACE_MS = 500
/** A full save goes `keepalive` as the page goes away only while its body's BYTES, with those of the page's other
 *  keepalive saves still out, are at most this - inside the 64 KiB of bodies the browser lets keepalive requests have
 *  in flight at once (over it the fetch is refused outright, so the save is sent as an ordinary one instead). */
export const BEACON_MAX = 60_000
/** What Navidrome records deadwax's saves as (src/api/navidrome_endpoint.py CLIENT_NAME). */
export const DEADWAX_CLIENT = 'deadwax'

/**
 * The bytes `text` is as UTF-8 - what a request's body is sent as, and what keepalive's 64 KiB counts. A string's
 * length counts UTF-16 units, so a title in Japanese, three bytes a character, would read as a third of itself.
 * Counted here rather than by TextEncoder, so it holds without a browser (JSON.stringify's text has no lone
 * surrogate: it writes one as an escape).
 */
export function utf8Length(text: string): number {
  let bytes = 0
  for (let i = 0; i < text.length; i++) {
    const unit = text.charCodeAt(i)
    if (unit < 0x80) bytes += 1
    else if (unit < 0x800) bytes += 2
    else if (unit >= 0xd800 && unit <= 0xdbff && i + 1 < text.length && (text.charCodeAt(i + 1) & 0xfc00) === 0xdc00) {
      bytes += 4
      i++
    } else bytes += 3
  }
  return bytes
}

/* ===== the server's answer ===== */

/** deadwax's record, as GET /queue hands it back when deadwax saved last. */
export interface KeptQueue {
  rev: number
  ids_rev: number
  ids: string[]
  index: number
  position: number
  snapshot: string | null
  device: string
  label: string
}

/** GET /deadwax/navidrome/queue (src/play_queue.py answer): Navidrome's queue, and the record when deadwax saved it. */
export interface QueueAnswer<Song = unknown> {
  tracks: Song[]
  /** Navidrome's currentIndex as it said it - stale after songs were dropped; null for none */
  index: number | null
  /** seconds */
  position: number
  changed_by: string
  /** logins off: one queue for everyone */
  shared: boolean
  kept: KeptQueue | null
}

/* ===== the window, and the snapshot ===== */

type LevelChar = 'a' | 't' | '-'
type FromChar = 's' | 'a' | 'o'

/** Snapshot v1, as toSave writes it. */
interface SnapshotV1 {
  v: 1
  levels: string
  marks: [number, FromChar, number, number][]
  source: string[]
  sourceLevels: string
  extra: Record<string, QueueTrack>
  shuffle: boolean
  nextKey: number
  startedAt: number
  left: [number, number][]
  paged?: Paged
  pagedRounds?: { pass: number; paged: Paged }[]
}

const levelChar = (level: Level | undefined): LevelChar => (level === 'album' ? 'a' : level === 'track' ? 't' : '-')
const charLevel = (char: string | undefined): Level | undefined => (char === 'a' ? 'album' : char === 't' ? 'track' : undefined)
const fromChar = (from: Mark['from']): FromChar => (from === 'source' ? 's' : from === 'added' ? 'a' : 'o')

/** A song as the queue needs it, without its level - what `extra` keeps. */
function bare(track: QueueTrack): QueueTrack {
  return {
    id: track.id, title: track.title, artist: track.artist, album: track.album, albumId: track.albumId, coverArt: track.coverArt,
    duration: track.duration, contentType: track.contentType, suffix: track.suffix, sampleRate: track.sampleRate,
    bitDepth: track.bitDepth, channels: track.channels,
  }
}

/** The window of a queue of `count` entries playing `index`: [start, end). */
export function windowOf(count: number, index: number): { start: number; end: number } {
  if (count <= 0) return { start: 0, end: 0 }
  const at = Math.min(Math.max(index, 0), count - 1)
  const start = Math.max(0, at - RESUME_BEFORE)
  return { start, end: Math.min(count, start + RESUME_MAX) }
}

export interface Saving {
  ids: string[]
  /** the song playing, in `ids` */
  index: number
  position: number
  /** the account of Up Next - null for a queue without one, or one over RESUME_SNAPSHOT_MAX */
  snapshot: string | null
  /** where `ids` begin in the queue */
  start: number
}

/**
 * What a full save sends of a queue: its window - entries [start, end), the index and `startedAt` moved down by
 * `start` (startedAt floored at 0), the marks sliced with them - and the snapshot of its Up Next, `left`, `source`,
 * `paged` as they are.
 */
export function toSave(queue: UpNextQueue, position: number): Saving {
  const { start, end } = windowOf(queue.tracks.length, queue.index)
  const entries = queue.tracks.slice(start, end) as LevelledTrack[]
  const ids = entries.map((track) => track.id)
  const index = queue.index - start
  const state = queue.upNext
  if (!state) return { ids, index, position, snapshot: null, start }
  const inWindow = new Set(ids)
  const extra: Record<string, QueueTrack> = {}
  for (const track of state.source) if (!inWindow.has(track.id) && !(track.id in extra)) extra[track.id] = bare(track)
  const made: SnapshotV1 = {
    v: 1,
    levels: entries.map((track) => levelChar(track.level)).join(''),
    marks: state.marks.slice(start, end).map((mark) => [mark.key, fromChar(mark.from), mark.at, mark.pass]),
    source: state.source.map((track) => track.id),
    sourceLevels: (state.source as LevelledTrack[]).map((track) => levelChar(track.level)).join(''),
    extra,
    shuffle: state.shuffle,
    nextKey: state.nextKey,
    startedAt: Math.max(0, state.startedAt - start),
    left: state.left.map((gone) => [gone.pass, gone.at]),
    ...(state.paged ? { paged: state.paged } : {}),
    ...(state.pagedRounds ? { pagedRounds: state.pagedRounds } : {}),
  }
  const snapshot = JSON.stringify(made)
  return { ids, index, position, snapshot: snapshot.length <= RESUME_SNAPSHOT_MAX ? snapshot : null, start }
}

/** A level re-fitted to this device's Normalization: Off none, By song track, By album album, Automatic the level
 *  saved - or track where none was (a list from another app is songs: levelFor(setting, 'songs')). */
export function relevel(level: Level | undefined, setting: Normalization): Level | undefined {
  if (setting === 'off') return undefined
  if (setting === 'song') return 'track'
  if (setting === 'album') return 'album'
  return level ?? 'track'
}

const isInt = (value: unknown): value is number => typeof value === 'number' && Number.isInteger(value)
const isObject = (value: unknown): value is Record<string, unknown> => typeof value === 'object' && value !== null && !Array.isArray(value)
const nullableString = (value: unknown) => value === null || typeof value === 'string'

function readSong(value: unknown, id: string): QueueTrack | null {
  if (!isObject(value) || value.id !== id) return null
  const numbers = ['duration', 'sampleRate', 'bitDepth', 'channels'] as const
  if (typeof value.title !== 'string' || typeof value.artist !== 'string' || typeof value.album !== 'string') return null
  if (!nullableString(value.albumId) || !nullableString(value.coverArt) || !nullableString(value.contentType) || !nullableString(value.suffix)) return null
  if (numbers.some((name) => typeof value[name] !== 'number' || !Number.isFinite(value[name]))) return null
  return bare(value as unknown as QueueTrack)
}

function readPaged(value: unknown, setting: Normalization): Paged | null {
  if (!isObject(value) || typeof value.token !== 'string' || !isInt(value.total) || !isInt(value.fetched)) return null
  if (value.scope !== 'yours' && value.scope !== 'store') return null
  if (value.level !== undefined && value.level !== 'album' && value.level !== 'track') return null
  const level = relevel(value.level as Level | undefined, setting)
  return { token: value.token, total: value.total, fetched: value.fetched, scope: value.scope, ...(level ? { level } : {}) }
}

/** The levels a snapshot saved for its `count` entries - none for each where it can't say. */
export function savedLevels(snapshot: string | null, count: number): (Level | undefined)[] {
  try {
    const made: unknown = snapshot === null ? null : JSON.parse(snapshot)
    if (isObject(made) && made.v === 1 && typeof made.levels === 'string' && made.levels.length === count) {
      return [...made.levels].map(charLevel)
    }
  } catch {
    // not one: no levels known
  }
  return Array.from({ length: count }, () => undefined)
}

/**
 * The queue a snapshot describes, over `tracks` - Navidrome's songs, the window's entries, in order - playing
 * `index`, every level re-fitted to `setting`. Null when it doesn't read back: not JSON, another version, a source
 * song in neither Navidrome's songs nor `extra`, or a rebuilt state failing its checks - marks as long as the entries,
 * each mark's `from` one of the three, a source mark's `at` inside the source and naming its song, an added mark's
 * at and pass -1, keys unique and below nextKey, startedAt not below 0.
 */
export function fromSnapshot(snapshot: string | null, tracks: readonly QueueTrack[], index: number, setting: Normalization): UpNextQueue | null {
  if (snapshot === null) return null
  let made: unknown
  try {
    made = JSON.parse(snapshot)
  } catch {
    return null
  }
  if (!isObject(made) || made.v !== 1) return null
  const n = tracks.length
  const { levels, marks, source, sourceLevels, extra, shuffle, nextKey, startedAt, left } = made
  if (typeof levels !== 'string' || levels.length !== n || !Array.isArray(marks) || marks.length !== n) return null
  if (!Array.isArray(source) || !source.every((id) => typeof id === 'string')) return null
  if (typeof sourceLevels !== 'string' || sourceLevels.length !== source.length || !isObject(extra)) return null
  if (typeof shuffle !== 'boolean' || !isInt(nextKey) || !isInt(startedAt) || !Array.isArray(left)) return null
  //? startedAt is only where playTracks began, not a bound: Previous walks back before it (an album started at song 5,
  //? then Previous), and Repeat's copies dropped since can leave it anywhere - withShuffle reads it only as where the
  //? first round's heard songs begin, up to the song playing, so any place at or after 0 reads back as it was
  if (!isInt(index) || index < 0 || index >= n || startedAt < 0) return null
  //? the songs: Navidrome's where it has them, `extra` for the source's outside the window - one object per (id, level)
  const navidrome = new Map(tracks.map((track) => [track.id, bare(track)]))
  const songs = new Map<string, LevelledTrack | null>()
  const song = (id: string, char: string | undefined): LevelledTrack | null => {
    const level = relevel(charLevel(char), setting)
    const key = `${level ?? ''}:${id}`
    if (!songs.has(key)) {
      const base = navidrome.get(id) ?? readSong(extra[id], id)
      songs.set(key, base && level ? { ...base, level } : base)
    }
    return songs.get(key)!
  }
  const entries = tracks.map((track, i) => song(track.id, levels[i]))
  const list = (source as string[]).map((id, j) => song(id, sourceLevels[j]))
  if (entries.some((track) => !track) || list.some((track) => !track)) return null
  const keys = new Set<number>()
  const rebuilt: Mark[] = []
  for (const [i, raw] of marks.entries()) {
    if (!Array.isArray(raw) || raw.length !== 4) return null
    const [key, char, at, pass] = raw as unknown[]
    if (!isInt(key) || !isInt(at) || !isInt(pass) || key < 0 || key >= nextKey || keys.has(key)) return null
    keys.add(key)
    const from = char === 's' ? 'source' : char === 'a' ? 'added' : char === 'o' ? 'one' : null
    if (from === null) return null
    if (from === 'source' && (at < 0 || at >= list.length || list[at]!.id !== entries[i]!.id || pass < 0)) return null
    if (from === 'added' && (at !== -1 || pass !== -1)) return null
    if (from === 'one' && (at < -1 || at >= list.length)) return null
    rebuilt.push({ key, from, at, pass })
  }
  const gone: { pass: number; at: number }[] = []
  for (const raw of left) {
    if (!Array.isArray(raw) || raw.length !== 2 || !isInt(raw[0]) || !isInt(raw[1])) return null
    gone.push({ pass: raw[0], at: raw[1] })
  }
  let paged: Paged | undefined
  if (made.paged !== undefined) {
    const read = readPaged(made.paged, setting)
    if (!read) return null
    paged = read
  }
  let pagedRounds: { pass: number; paged: Paged }[] | undefined
  if (made.pagedRounds !== undefined) {
    if (!Array.isArray(made.pagedRounds)) return null
    pagedRounds = []
    for (const held of made.pagedRounds) {
      const read = isObject(held) && isInt(held.pass) ? readPaged(held.paged, setting) : null
      if (!read || !isObject(held)) return null
      pagedRounds.push({ pass: held.pass as number, paged: read })
    }
  }
  const upNext: UpNextState = {
    marks: rebuilt, source: list as LevelledTrack[], shuffle, nextKey, startedAt, left: gone,
    ...(paged ? { paged } : {}), ...(pagedRounds ? { pagedRounds } : {}),
  }
  return { tracks: entries as LevelledTrack[], index, upNext }
}

/** A plain list: the songs in order, from `index`, as playTracks(tracks, index) queues them - each at its level,
 *  re-fitted to this device (`levels` the ones saved, where known). */
function plain(tracks: readonly QueueTrack[], index: number, levels: readonly (Level | undefined)[], setting: Normalization): UpNextQueue {
  const levelled = tracks.map((track, i) => {
    const level = relevel(levels[i], setting)
    return level ? { ...bare(track), level } : track
  })
  return startUpNext(levelled, index)
}

const same = (a: readonly string[], b: readonly string[]) => a.length === b.length && a.every((id, i) => id === b[i])

/** Where a queue came from, for the notice: another device of deadwax's (by its label), or another app. */
export type PickedFrom = { device: string } | { app: string }

export interface Resumed {
  queue: UpNextQueue
  position: number
  /** null: this device, or no telling */
  from: PickedFrom | null
  /** the ids deadwax kept are Navidrome's - its record believed, a position save against its ids_rev possible */
  exact: boolean
}

/**
 * What is put back, from GET /queue's answer and its songs (`tracks`, shuffledTrack's of answer.tracks):
 *
 *  - Navidrome's list empty: nothing (another app may have cleared it - Navidrome is the authority).
 *  - deadwax's own, exact (kept, ids equal, index equal): the whole account from the snapshot at kept.position - or,
 *    a snapshot that doesn't read back, the plain list of the same songs at the same index and position.
 *  - deadwax's own less songs Navidrome dropped (its ids a subsequence of kept.ids, every copy of a survivor kept):
 *    a plain list of what is left, levels carried by entry; the song kept.index's if it survived (at kept.position),
 *    else the first survivor after it at 0, else the last survivor at 0.
 *  - anyone else's: a plain list at Navidrome's index held into the list - at 0 when it had to be held - at its
 *    position.
 *  - a song played to its end (within a second of its length): the next entry at 0, or - the queue's last - it at 0.
 */
export function resumed(answer: Pick<QueueAnswer, 'index' | 'position' | 'changed_by' | 'kept'>, tracks: readonly QueueTrack[],
  setting: Normalization, deviceId: string): Resumed | null {
  const n = tracks.length
  if (!n) return null
  const ids = tracks.map((track) => track.id)
  const kept = answer.kept
  const keptFrom: PickedFrom | null = kept && kept.device !== deviceId ? { device: kept.label } : null
  let queue: UpNextQueue
  let position: number
  let from: PickedFrom | null
  let exact = false
  const present = new Set(ids)
  const survivors = kept ? kept.ids.filter((id) => present.has(id)) : []
  if (kept && same(ids, kept.ids) && kept.index === answer.index) {
    exact = true
    queue = fromSnapshot(kept.snapshot, tracks, kept.index, setting) ?? plain(tracks, kept.index, savedLevels(kept.snapshot, n), setting)
    position = kept.position
    from = keptFrom
  } else if (kept && survivors.length < kept.ids.length && same(survivors, ids)) {
    const levels = savedLevels(kept.snapshot, kept.ids.length).filter((_, i) => present.has(kept.ids[i]!))
    const at = Math.min(Math.max(kept.index, 0), kept.ids.length - 1)
    const before = kept.ids.slice(0, at).filter((id) => present.has(id)).length
    let index: number
    if (present.has(kept.ids[at]!)) {
      index = before
      position = kept.position
    } else {
      index = before < n ? before : n - 1
      position = 0
    }
    queue = plain(tracks, index, levels, setting)
    from = keptFrom
  } else {
    const said = answer.index
    const index = said === null ? 0 : Math.min(Math.max(said, 0), n - 1)
    position = said === index ? answer.position : 0
    queue = plain(tracks, index, [], setting)
    from = kept && same(ids, kept.ids) ? keptFrom : answer.changed_by && answer.changed_by !== DEADWAX_CLIENT ? { app: answer.changed_by } : null
  }
  const track = current(queue)!
  if (track.duration > 0 && position >= track.duration - 1) {
    if (queue.index + 1 < queue.tracks.length) queue = { ...queue, index: queue.index + 1 }
    position = 0
  }
  return { queue, position: Math.max(0, position), from, exact }
}

/* ===== the notice, and the device ===== */

/** What the device saving is called: iPhone, iPad (iPadOS says it is a Mac, but with touch), Mac, Windows PC, Android
 *  phone, Chromebook, Linux PC - else "browser". */
export function deviceLabel(userAgent: string, maxTouchPoints: number): string {
  if (/iPhone|iPod/.test(userAgent)) return 'iPhone'
  if (/iPad/.test(userAgent) || (/Macintosh/.test(userAgent) && maxTouchPoints > 1)) return 'iPad'
  if (/Macintosh|Mac OS X/.test(userAgent)) return 'Mac'
  if (/Windows/.test(userAgent)) return 'Windows PC'
  if (/Android/.test(userAgent)) return 'Android phone'
  if (/CrOS/.test(userAgent)) return 'Chromebook'
  if (/Linux/.test(userAgent)) return 'Linux PC'
  return 'browser'
}

/** The app's one notice, as a queue is picked up from elsewhere: "Picked up from your Mac" - with logins off, when the
 *  queue is everyone's, "Picked up from a Mac" - or "Picked up from Symfonium". Null for this device's own. */
export function pickedUpWords(from: PickedFrom | null, shared: boolean): string | null {
  if (!from) return null
  if ('app' in from) return `Picked up from ${from.app}`
  const whose = shared ? (/^[aeiou]/i.test(from.device) ? 'an' : 'a') : 'your'
  return `Picked up from ${whose} ${from.device}`
}

/* ===== when it saves ===== */

/** What was last saved, or put back - the baseline a change is measured from. */
export interface SaveBaseline {
  /** the queue's own objects then: a change of either is a change of the songs or of Up Next */
  tracks: readonly QueueTrack[]
  upNext: UpNextState | undefined
  index: number
  position: number
  /** the window its full save sent: the queue's entries [start, start + count) */
  start: number
  count: number
}

export interface SaveClock {
  saved: SaveBaseline | null
  /** the last full save's ids_rev - null while there is none a position save could be made against */
  idsRev: number | null
  /** the 30 s are counted from here (ms): the last save, or playing starting since - null for neither */
  countFrom: number | null
  /** when the queue last changed - its songs, Up Next or the song (ms) */
  changedAt: number | null
  /** when a save last failed (ms) - null when the last one didn't */
  failedAt: number | null
}

/** What moved since the baseline: the songs or Up Next, the song, the second (by more than 1 s) - or nothing. */
export function changedSince(saved: SaveBaseline | null, queue: UpNextQueue, position: number): 'songs' | 'song' | 'position' | null {
  if (!saved || queue.tracks !== saved.tracks || queue.upNext !== saved.upNext) return 'songs'
  if (queue.index !== saved.index) return 'song'
  if (Math.abs(position - saved.position) > 1) return 'position'
  return null
}

/** What started the question: a wait running out, the player's own position update while playing, a pause (or
 *  anything else that wants it now), the page going away. */
export type SaveTrigger = 'wait' | 'position' | 'pause' | 'hidden'

/**
 * Whether a save is due, and which: a FULL one (the ids, the index, the position, the snapshot) or one of the
 * position only, against the last full save's ids (`at`) - null for none. Nothing for an empty queue, nothing while
 * nothing changed (a queue merely put back is the baseline), nothing for 30 s after a save failed. A change of the
 * songs or of Up Next: in full, RESUME_FULL_WAIT_MS after the last of them. A song change: RESUME_AT_WAIT_MS after.
 * The second alone: while paused, at the wait after it moved (a scrub); while playing, every RESUME_EVERY_S, counted
 * by the player's own position updates. A pause and the page going away: whatever is due, at once. A position save
 * needs an ids_rev and the song inside the window saved; else it is a full one.
 */
export function saveDue(clock: SaveClock, queue: UpNextQueue, position: number, playing: boolean, now: number, trigger: SaveTrigger): 'full' | 'at' | null {
  if (!current(queue)) return null
  if (clock.failedAt !== null && now - clock.failedAt < RESUME_EVERY_S * 1000) return null
  const change = changedSince(clock.saved, queue, position)
  if (change === null) return null
  const saved = clock.saved
  const at = change !== 'songs' && clock.idsRev !== null && saved !== null && queue.index >= saved.start && queue.index < saved.start + saved.count
  const kind = at ? 'at' : 'full'
  if (trigger === 'pause' || trigger === 'hidden') return kind
  const since = clock.changedAt === null ? Infinity : now - clock.changedAt
  if (change === 'songs') return since >= RESUME_FULL_WAIT_MS ? 'full' : null
  if (change === 'song') return since >= RESUME_AT_WAIT_MS ? kind : null
  if (!playing) return trigger === 'wait' ? kind : null
  return trigger === 'position' && (clock.countFrom === null || now - clock.countFrom >= RESUME_EVERY_S * 1000) ? kind : null
}
