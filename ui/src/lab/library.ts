/**
 * A song from your library on the test bench (2.0.0-player.37). James, on seeing the bench: "hm. how about
 * adding a test song from my library, like eye in the sky" - music he knows, scrubbed on the bench and
 * set beside the ideal turntables. The point is the REAL path: a library song on the bench is exactly what
 * the app's turntable does with that song, so what he hears there is what he hears in the app.
 *
 *  - FOUND by Navidrome's search (search3, through deadwax's /navidrome/search - searchLibrary in
 *    player/api.ts), songs only, asked LIBRARY_SETTLE_MS after typing stops as the app's Search asks its
 *    library half, through latestOnly() so an older answer never lands over a newer one (librarySearch).
 *  - PLAYED at the song's own stream address, asked for exactly as the app asks for it (libraryAddress:
 *    streamUrl with the browser's canPlayType, wrapsFlac and the device's Maximum quality) - by the bench's
 *    own <audio>, never the app's player.
 *  - TURNED with no window source: the deck asks deadwax's scrub route for its windows as it does in the
 *    app, at the cap Turntable's host works out (deckCap).
 *  - COMPARED by reading the song itself along the path: the windows covering it fetched again from the
 *    scrub route (readWindows - never the whole song: an iPhone's memory), decoded at the song's own rate
 *    and read through the long windowed sinc (sampledReader in lab/signals.ts) placed by their first sample.
 *  - REMEMBERED on this device (readPick, writePick): the last song picked, offered again as the page opens
 *    once Navidrome says it still has it (checkPick) - and forgotten when it hasn't.
 *
 * Pure but for what is handed in (the search, the storage, the fetch), so ui/test/lab.sim.cjs holds it to
 * the rules.
 */

import { ApiError } from '../api/http'
import { formatRow } from '../lib/debugRows'
import { isAbort, latestOnly } from '../lib/latest'
import type { QueueTrack } from '../lib/playQueue'
import { LIBRARY_SETTLE_MS } from '../lib/searchQuery'
import { resamples, wrapsFlac, type Browser, type MaxRate } from '../lib/streamWrap'
import { WINDOW_GRID_S, WINDOW_S } from '../player/deck'
import { streamUrl, toQueueTrack, type AlbumWithSongs, type LibraryResults, type ScrubWindow, type Song } from '../player/api'
import { SINC_ZEROS } from './signals'

const message = (error: unknown) => (error instanceof Error ? error.message : String(error))

/* ===== a song of the library as the app plays it ===== */

/** A song from Navidrome's answer as the app's queue holds it - the app's own conversion (toQueueTrack). */
export function libraryTrack(song: Song): QueueTrack {
  const album: AlbumWithSongs = {
    id: song.albumId ?? '', name: song.album ?? '',
    ...(song.artist !== undefined ? { artist: song.artist } : {}), ...(song.coverArt !== undefined ? { coverArt: song.coverArt } : {}),
  }
  return toQueueTrack(song, album)
}

/**
 * Where the bench's player plays a library song from: the address the app's player asks for it at - the
 * file as it is where this browser plays it (or Navidrome's MP3 where it doesn't), inside an MP4 for Safari
 * and every iPhone browser, resampled under "Up to 48 kHz" for a hi-res FLAC. The very helpers usePlayer
 * asks (streamUrl, streamFormat through canPlayType, wrapsFlac, resamples).
 */
export function libraryAddress(track: QueueTrack, browser: Browser, maxRate: MaxRate): string {
  return streamUrl(track, (type) => browser.canPlayType(type) !== '', wrapsFlac(browser), maxRate)
}

/**
 * The cap the deck asks for the song's windows at - Turntable's host's own rule: 48000 where the song is
 * played resampled (a hi-res FLAC under "Up to 48 kHz"), so its windows are cut from that very copy - its
 * rate, its level - and none for the song as it is.
 */
export function deckCap(track: QueueTrack, maxRate: MaxRate): number | null {
  return resamples(track, maxRate, 'raw') ? 48000 : null
}

/** The file as Navidrome read it, in Info > Debug's own words: "FLAC, 16-bit, 44.1 kHz, stereo". */
export function formatLine(track: QueueTrack): string {
  return formatRow(track).value
}

/* ===== the search ===== */

/** What the search says: nothing asked, asking, the songs found, or why it couldn't. */
export type SearchAnswer =
  | { state: 'idle'; query: string }
  | { state: 'asking'; query: string }
  | { state: 'found'; query: string; songs: Song[] }
  | { state: 'failed'; query: string; problem: string }

export interface SearchOptions {
  /** Navidrome's search3 (searchLibrary) */
  search: (query: string, signal: AbortSignal | undefined) => Promise<LibraryResults>
  /** told every change of what the search says */
  onAnswer: (answer: SearchAnswer) => void
  /** how long typing has to stop before it asks, ms - the app's Search's LIBRARY_SETTLE_MS */
  settleMs?: number
  setTimer?: (run: () => void, ms: number) => unknown
  clearTimer?: (id: unknown) => void
}

export interface LibrarySearch {
  /** the box's text: asked once typing has stopped for settleMs - nothing asked for an empty box */
  type(text: string): void
  /** asked at once (Enter) */
  now(text: string): void
  /** nothing more asked, and nothing still out lands */
  stop(): void
}

/**
 * The bench's library search: songs only, LIBRARY_SETTLE_MS after typing stops - and through latestOnly(),
 * so only the newest question's answer is said: a slow answer to an older question is dropped, whatever
 * order the answers come in.
 */
export function librarySearch(options: SearchOptions): LibrarySearch {
  const settle = options.settleMs ?? LIBRARY_SETTLE_MS
  const setTimer = options.setTimer ?? ((run: () => void, ms: number) => setTimeout(run, ms))
  const clearTimer = options.clearTimer ?? ((id: unknown) => clearTimeout(id as ReturnType<typeof setTimeout>))
  const requests = latestOnly()
  let timer: unknown = null
  const cancelTimer = () => {
    if (timer !== null) clearTimer(timer)
    timer = null
  }
  const ask = (query: string) => {
    cancelTimer()
    const ticket = requests.begin()
    options.onAnswer({ state: 'asking', query })
    options.search(query, ticket.signal).then(
      (results) => {
        if (ticket.current()) options.onAnswer({ state: 'found', query, songs: results.songs ?? [] })
      },
      (error: unknown) => {
        if (!ticket.current() || isAbort(error)) return
        options.onAnswer({ state: 'failed', query, problem: message(error) })
      },
    )
  }
  const quiet = (query: string) => {
    cancelTimer()
    requests.supersede()
    options.onAnswer({ state: 'idle', query })
  }
  return {
    type(text) {
      const query = text.trim()
      if (!query) return quiet(query)
      cancelTimer()
      timer = setTimer(() => {
        timer = null
        ask(query)
      }, settle)
    },
    now(text) {
      const query = text.trim()
      if (!query) return quiet(query)
      ask(query)
    },
    stop() {
      cancelTimer()
      requests.supersede()
    },
  }
}

/* ===== the song remembered ===== */

/** Where the last song picked is kept, on this device. */
export const PICK_KEY = 'deadwax-lab-library-song'

/** What is kept of it: enough to say what it is, and its id to ask Navidrome by. */
export interface LibraryPick {
  id: string
  title: string
  artist: string
}

/** The storage it is kept in - localStorage, or the sim's. */
export interface PickStorage {
  getItem(key: string): string | null
  setItem(key: string, value: string): void
  removeItem(key: string): void
}

const pageStorage = (): PickStorage | null => {
  try {
    return typeof localStorage === 'undefined' ? null : localStorage
  } catch {
    return null
  }
}

/** The song remembered, or null - for nothing kept, something unreadable kept, or storage that can't be read. */
export function readPick(storage: PickStorage | null = pageStorage()): LibraryPick | null {
  try {
    const raw = storage?.getItem(PICK_KEY)
    if (!raw) return null
    const parsed = JSON.parse(raw) as Partial<LibraryPick> | null
    if (!parsed || typeof parsed.id !== 'string' || !parsed.id) return null
    return { id: parsed.id, title: typeof parsed.title === 'string' ? parsed.title : '', artist: typeof parsed.artist === 'string' ? parsed.artist : '' }
  } catch {
    return null
  }
}

/** The song picked, kept - a storage that won't take it is no reason for the pick not to work. */
export function writePick(song: Pick<Song, 'id' | 'title' | 'artist'>, storage: PickStorage | null = pageStorage()): void {
  try {
    storage?.setItem(PICK_KEY, JSON.stringify({ id: song.id, title: song.title, artist: song.artist ?? '' }))
  } catch {
    //? storage full, or refused (a private window): the pick works, it just isn't remembered
  }
}

/** Forgotten. */
export function forgetPick(storage: PickStorage | null = pageStorage()): void {
  try {
    storage?.removeItem(PICK_KEY)
  } catch {
    //? nothing to do about a storage that refuses
  }
}

/** What became of the song remembered, asked of Navidrome as the page opens. */
export type PickChecked =
  | { state: 'none' }
  | { state: 'found'; song: Song }
  | { state: 'forgotten'; pick: LibraryPick }
  | { state: 'failed'; pick: LibraryPick; problem: string }

/**
 * The song remembered, asked of Navidrome by its id (getSong, `ask`): offered again as it answers; FORGOTTEN
 * when Navidrome hasn't it any more (a 404 - the song deleted, or its id changed with a re-tag); kept, and
 * said, when Navidrome can't be asked just now.
 */
export async function checkPick(ask: (id: string) => Promise<Song>, storage: PickStorage | null = pageStorage()): Promise<PickChecked> {
  const pick = readPick(storage)
  if (!pick) return { state: 'none' }
  try {
    const song = await ask(pick.id)
    if (!song || song.id !== pick.id) throw new ApiError(404, null, 'Navidrome has no song by that id')
    return { state: 'found', song }
  } catch (error) {
    if (error instanceof ApiError && error.status === 404) {
      forgetPick(storage)
      return { state: 'forgotten', pick }
    }
    return { state: 'failed', pick, problem: message(error) }
  }
}

/* ===== the windows the comparison reads ===== */

/** How many of deadwax's windows B and C may read at most: 160 s of a CD-quality song, about 52 s of a
 *  hi-res one played as it is - far more than ten seconds of a hand covers - and only that much decoded. */
export const COMPARE_WINDOWS_MAX = 4

/** Room kept either side of the path beyond the reader's reach, seconds. */
export const READ_MARGIN_S = 0.5

/**
 * The window the deck asked for that begins at `start` (song seconds, its first sample): the deck asks on a
 * grid of WINDOW_GRID_S, and deadwax starts a window on the frame or fragment at or before what was asked -
 * so the grid point the window began within, asked again, gives it again, byte for byte (and from the
 * browser's own cache, where it is still kept).
 */
export function voiceWindowFrom(start: number): number {
  return Math.max(0, Math.ceil(start / WINDOW_GRID_S - 1e-6) * WINDOW_GRID_S)
}

/**
 * How far either side of a place the long windowed sinc reads, seconds, for samples at `songRate` read at
 * `fastest` times the speed into `outputRate`: SINC_ZEROS of the samples' own, or as many more as the
 * cutoff is lowered below their Nyquist frequency (sampledReader's own reach).
 */
export function readReach(fastest: number, outputRate: number, songRate: number): number {
  return SINC_ZEROS * Math.max(1 / songRate, Math.abs(fastest) / outputRate)
}

/** The stretch of the song B and C read: the path's lowest to highest place, and the reader's reach and
 *  READ_MARGIN_S either side - inside the song. */
export interface ReadSpan {
  from: number
  to: number
}

export function readSpan(
  path: { lowest: number; highest: number; fastest: number }, outputRate: number, songRate: number, length: number,
): ReadSpan {
  const reach = readReach(path.fastest, outputRate, songRate) + READ_MARGIN_S
  const from = Math.max(0, path.lowest - reach)
  const to = length > 0 ? Math.min(length, path.highest + reach) : path.highest + reach
  return { from, to: Math.max(from, to) }
}

/** Why B and C couldn't be read: the path ran over more of the song than the bench reads at once. */
export class TooWide extends Error {
  constructor(seconds: number) {
    super(`the record went over ${Math.round(seconds)} s of the song - more than ${COMPARE_WINDOWS_MAX} of deadwax's windows, which is as much of it as the bench reads at once`)
    this.name = 'TooWide'
  }
}

/**
 * The windows covering `span`, asked of `fetchWindow` (the scrub route, at the deck's cap) on the deck's grid,
 * as the deck asks - each from the grid point at or before where the last one ended, so nothing is left out
 * between them; as many as it takes, up to `max`. Past `max`: TooWide. Past the song's end (a 416, or a
 * window that adds nothing): as far as the song goes.
 */
export async function readWindows(
  span: ReadSpan, fetchWindow: (at: number) => Promise<ScrubWindow>, max = COMPARE_WINDOWS_MAX,
): Promise<ScrubWindow[]> {
  if (span.to - span.from > max * WINDOW_S) throw new TooWide(span.to - span.from)
  const windows: ScrubWindow[] = []
  let at = Math.max(0, Math.floor(span.from / WINDOW_GRID_S) * WINDOW_GRID_S)
  let reached = -Infinity
  for (;;) {
    if (windows.length >= max) throw new TooWide(span.to - span.from)
    let got: ScrubWindow
    try {
      got = await fetchWindow(at)
    } catch (error) {
      //? past the song's end: as far as it goes
      if (windows.length && error instanceof ApiError && error.status === 416) break
      throw error
    }
    const end = (got.first + got.samples) / got.rate
    if (end <= reached + 1e-9) break
    windows.push(got)
    reached = end
    if (end >= span.to - 1e-9) break
    //? the next from the grid point at or before this one's end - or from its end, where that is no further
    const next = Math.floor(end / WINDOW_GRID_S) * WINDOW_GRID_S
    at = next > at ? next : end
  }
  return windows
}

/** The song's samples over the windows read: one channel, its first sample `first`, at `rate`. */
export interface Stitched {
  samples: Float32Array
  first: number
  rate: number
}

/**
 * The windows decoded (`decode`: decodeAudioData at their own rate, so each sample is the FLAC's own) and
 * laid side by side by their first samples into one stretch - the first channel, as a picked file's is
 * read, which is the one the recording holds. Decoded one at a time, each let go of as it is laid in.
 */
export async function stitchWindows(windows: ScrubWindow[], decode: (bytes: ArrayBuffer, rate: number) => Promise<Float32Array[]>): Promise<Stitched> {
  if (!windows.length) throw new Error('no window to read')
  const rate = windows[0]!.rate
  if (windows.some((one) => one.rate !== rate)) throw new Error("deadwax's windows came at two rates")
  const first = Math.min(...windows.map((one) => one.first))
  const last = Math.max(...windows.map((one) => one.first + one.samples))
  const samples = new Float32Array(last - first)
  for (const one of windows) {
    const channels = await decode(one.bytes, rate)
    const channel = channels[0]
    if (!channel) throw new Error('a window of it decoded to nothing')
    samples.set(channel.subarray(0, Math.min(channel.length, one.samples, samples.length - (one.first - first))), one.first - first)
  }
  return { samples, first, rate }
}
