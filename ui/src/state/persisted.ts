import type { FormatPreference } from '../api/types'
import { DEFAULT_NORMALIZATION, type Normalization } from '../lib/loudness'
import { isSpeed, roundSpeed, SPEED_NORMAL } from '../lib/playSpeed'
import type { MaxRate } from '../lib/streamWrap'
import type { Look } from '../lib/turntable'
import type { Repeat } from '../lib/upNext'
import type { AmbientChoice, Colours, Effect } from '../lib/visualizer'

/**
 * localStorage-backed state.
 *
 * These keys are already set in users' browsers - the two oldest by the main page, which retired in
 * 2.0.0-player.66 and whose values the app still carries over once. Changing a key name or a value
 * shape silently resets everyone's preferences, so treat them as a compatibility surface: read
 * defensively, keep the serialization identical, and reconcile unknown values rather than
 * discarding the whole blob.
 */
export const STORAGE_KEYS = {
  downloadDefaults: 'deadwax-download-defaults',
  /**
   * The main page's settings tab's preferences that weren't download defaults (its own key since
   * v0.5.1). Nothing writes it since that page retired (2.0.0-player.66): the app reads it only to
   * carry Confirm before cancelling over, once. (The main page's library and settings-tab keys -
   * deadwax-library-fields, -pane-width, -sort, deadwax-settings-tab - went with it, and are left as
   * they are in a browser that has them: nothing reads them.)
   */
  preferences: 'deadwax-preferences',
  /** Which order the Library's albums are in (lib/shelves.ts ALBUM_SORTS): the four old Subsonic list types mean
   *  what they did; since 2.0.0-player.59 three more, and anything else read as Artist, the default. */
  playerOrder: 'deadwax-player-order',
  /** (2.0.0-player.59) Which order the Library's artists are in: 'albums' (Most albums), anything else Name. Per
   *  device, like the albums' order. */
  playerArtistOrder: 'deadwax-player-artist-order',
  /** What the app's Library tab shows (2.0.0-player.17): 'artists' or 'songs', anything else the
   *  albums (the default). Per device, like the order. */
  playerLibraryView: 'deadwax-player-library-view',
  /** Whether the player's gapless switch is on: 'on', or anything else for off (the default). */
  playerGapless: 'deadwax-player-gapless',
  /** The player's "Maximum quality": '48000' (the default, and anything unknown) or 'original'.
   *  The player's own, like its gapless switch. */
  playerMaxRate: 'deadwax-player-max-rate',
  /** The player's Normalization (2.0.0-player.62): 'song', 'album' or 'off'; anything else - nothing stored, a
   *  mistyped value, storage that can't be read - is 'auto', what James asked for as the default. Per device,
   *  like Maximum quality: a desktop on speakers and a phone on AirPods can want different things. */
  playerNormalization: 'deadwax-player-normalization',
  /** "Now Playing opens as" (2.0.0-player.11): 'turntable', or anything else for the cover (the
   *  default). Per device, like the two above. */
  playerOpensAs: 'deadwax-player-opens-as',
  /** "Pause winds the record down" (2.0.0-player.14): 'off', or anything else for on (the default).
   *  Per device, like the three above. */
  playerWindDown: 'deadwax-player-wind-down',
  /** The desktop visualizer's choices (2.0.0-player.20), per device like the four above: its effect
   *  ('bars', 'scope', 'halo' or 'ambient', the default), its colours ('cover', the default, or
   *  'purple') and its Ambient style ('rotate' or one of lib/visualizer.ts's AMBIENT_STYLES -
   *  'mandala' by default). Anything else stored reads as the default. */
  playerVizEffect: 'deadwax-player-viz-effect',
  playerVizColours: 'deadwax-player-viz-colours',
  playerVizStyle: 'deadwax-player-viz-style',
  /** The player's speed (2.0.0-player.39): a number from 0.25 to 2, as text ('1.25'); anything else
   *  stored - nothing, a word, a number out of range - is 1, the song's own speed. Per device, like
   *  the others: a deck's pitch fader stays where you left it. */
  playerSpeed: 'deadwax-player-speed',
  /** Repeat (2.0.0-player.57): 'all' or 'one'; anything else - nothing stored, a mistyped value, storage that
   *  can't be read - is off. Per device, like Gapless: the queue (and with it Shuffle) is the page's alone. */
  playerRepeat: 'deadwax-player-repeat',
  /** "Confirm before cancelling" in You > Getting albums (2.0.0-player.41), per device: 'off', 'on',
   *  or 'default' - carried over from the main page's own setting in this browser, which said to ask
   *  (or said nothing), so it reads as the default, on. Nothing stored: not yet carried over. */
  playerConfirmCancel: 'deadwax-player-confirm-cancel',
  /** (2.0.0-player.64) This device's own name for its saves of the play queue (app/useResume.ts): 16 characters of
   *  A-Z a-z 0-9 _ -, made once. What tells "picked up from your Mac" from this device's own queue coming back. */
  playerDevice: 'deadwax-player-device',
} as const

/*
 * Every access is guarded. localStorage throws rather than returning null in private
 * browsing and when the quota is exceeded, and losing a preference is not a reason to take
 * the panel down with it.
 */

function readRaw(key: string): string | null {
  try {
    return localStorage.getItem(key)
  } catch {
    return null
  }
}

function writeRaw(key: string, value: string): void {
  try {
    localStorage.setItem(key, value)
  } catch {
    // storage unavailable - skip persisting, don't fail the interaction
  }
}

function readJson<T>(key: string): T | null {
  const raw = readRaw(key)
  if (raw === null) return null

  try {
    const parsed: unknown = JSON.parse(raw)
    return parsed && typeof parsed === 'object' ? (parsed as T) : null
  } catch {
    return null
  }
}

/* ===== deadwax-download-defaults ===== */

interface DownloadDefaults {
  formatPreference: FormatPreference
  autoGrab: boolean
}

const DOWNLOAD_DEFAULTS_FALLBACK: DownloadDefaults = {
  formatPreference: 'prefer_lossless',
  autoGrab: false,
}

const FORMAT_PREFERENCES: readonly FormatPreference[] = ['any', 'prefer_lossless', 'lossless_only']

/**
 * The main page's download defaults, as that page left them in this browser (it retired in
 * 2.0.0-player.66) - read only to carry Format over once (app/useGetSettings.ts). An unknown format
 * falls back rather than being carried.
 */
export function readDownloadDefaults(): DownloadDefaults {
  const saved = readJson<Partial<DownloadDefaults>>(STORAGE_KEYS.downloadDefaults) ?? {}
  return {
    formatPreference: FORMAT_PREFERENCES.includes(saved.formatPreference as FormatPreference)
      ? saved.formatPreference as FormatPreference
      : DOWNLOAD_DEFAULTS_FALLBACK.formatPreference,
    autoGrab: saved.autoGrab === true,
  }
}

/* ===== deadwax-player-order ===== */

/** A plain string, validated by the player against the orders it offers today. */
export function readPlayerOrder(): string | null {
  return readRaw(STORAGE_KEYS.playerOrder)
}

export function writePlayerOrder(order: string): void {
  writeRaw(STORAGE_KEYS.playerOrder, order)
}

/* ===== deadwax-player-artist-order ===== */

/** A plain string, read by lib/shelves.ts artistOrderFrom. */
export function readPlayerArtistOrder(): string | null {
  return readRaw(STORAGE_KEYS.playerArtistOrder)
}

export function writePlayerArtistOrder(order: string): void {
  writeRaw(STORAGE_KEYS.playerArtistOrder, order)
}

/* ===== deadwax-player-library-view ===== */

export type LibraryView = 'albums' | 'artists' | 'songs' | 'store' | 'storeArtists'

//? (2.0.0-player.52) Browse's two - the store's albums and artists - kept like the rest; with logins off
//? the Library shows them as the albums and the artists (lib/appFrame.ts shownPick)
const LIBRARY_VIEWS: readonly string[] = ['artists', 'songs', 'store', 'storeArtists']

/** What the Library tab shows: anything but one of its other views is the albums. */
export function readPlayerLibraryView(): LibraryView {
  const saved = readRaw(STORAGE_KEYS.playerLibraryView)
  return saved !== null && LIBRARY_VIEWS.includes(saved) ? (saved as LibraryView) : 'albums'
}

export function writePlayerLibraryView(view: LibraryView): void {
  writeRaw(STORAGE_KEYS.playerLibraryView, view)
}

/* ===== deadwax-player-gapless ===== */

/**
 * The player's own, like its order: a home-screen app keeps its storage apart from Safari's, so a
 * switch in the main page's settings tab (as it was) would never have reached it. Off unless it says 'on' - an experiment is
 * never on by accident.
 */
export function readPlayerGapless(): boolean {
  return readRaw(STORAGE_KEYS.playerGapless) === 'on'
}

export function writePlayerGapless(on: boolean): void {
  writeRaw(STORAGE_KEYS.playerGapless, on ? 'on' : 'off')
}

/* ===== deadwax-player-repeat ===== */

/**
 * Repeat (2.0.0-player.57), per device like the gapless switch and for the same reason. All or One only when it
 * says exactly that: anything else - nothing stored, an old or mistyped value, storage that can't be read - is
 * off, which is what the player always did at the end of the queue.
 */
export function readPlayerRepeat(): Repeat {
  const saved = readRaw(STORAGE_KEYS.playerRepeat)
  return saved === 'all' || saved === 'one' ? saved : 'off'
}

export function writePlayerRepeat(mode: Repeat): void {
  writeRaw(STORAGE_KEYS.playerRepeat, mode)
}

/* ===== deadwax-player-max-rate ===== */

/**
 * The player's "Maximum quality", per device like the gapless switch and for the same reason.
 * 'original' only when it says exactly that: anything else - nothing stored, an old or mistyped
 * value, storage that can't be read - is 48 kHz, the setting that keeps a hi-res album gapless.
 */
export function readPlayerMaxRate(): MaxRate {
  return readRaw(STORAGE_KEYS.playerMaxRate) === 'original' ? 'original' : '48000'
}

export function writePlayerMaxRate(rate: MaxRate): void {
  writeRaw(STORAGE_KEYS.playerMaxRate, rate)
}

/* ===== deadwax-player-normalization ===== */

/**
 * The player's Normalization (2.0.0-player.62), per device like Maximum quality. By song, By album or Off only
 * when it says exactly that: anything else - nothing stored, an old or mistyped value, storage that can't be
 * read - is Automatic, the default James asked for (an album levelled as an album, everything else song by
 * song). Read at each play (player/levelling.ts), never by the engine.
 */
export function readPlayerNormalization(): Normalization {
  const saved = readRaw(STORAGE_KEYS.playerNormalization)
  return saved === 'song' || saved === 'album' || saved === 'off' ? saved : DEFAULT_NORMALIZATION
}

export function writePlayerNormalization(setting: Normalization): void {
  writeRaw(STORAGE_KEYS.playerNormalization, setting)
}

/* ===== deadwax-player-opens-as ===== */

/**
 * "Now Playing opens as" (2.0.0-player.11): the look Now Playing opens in, per device like the two
 * above. The turntable only when it says exactly that: anything else - nothing stored, an unknown
 * value, storage that can't be read - is the cover, which is what Now Playing always was.
 */
export function readPlayerOpensAs(): Look {
  return readRaw(STORAGE_KEYS.playerOpensAs) === 'turntable' ? 'turntable' : 'cover'
}

export function writePlayerOpensAs(look: Look): void {
  writeRaw(STORAGE_KEYS.playerOpensAs, look)
}

/* ===== deadwax-player-wind-down ===== */

/**
 * "Pause winds the record down" (2.0.0-player.14): whether a pause on the turntable slows the
 * record's sound to a stop over about a second, per device like the three above. On unless it says
 * exactly 'off': nothing stored, an unknown value, storage that can't be read - all on, as it ships.
 */
export function readPlayerWindDown(): boolean {
  return readRaw(STORAGE_KEYS.playerWindDown) !== 'off'
}

export function writePlayerWindDown(on: boolean): void {
  writeRaw(STORAGE_KEYS.playerWindDown, on ? 'on' : 'off')
}

/* ===== deadwax-player-confirm-cancel ===== */

/**
 * "Confirm before cancelling" (2.0.0-player.41): whether the Requests tab's ✕ asks first, in the card,
 * per device. On by default. The first time it is read on a device it is carried over, ONCE, from
 * the main page's own setting in this browser (deadwax-preferences' confirmCancel, which the app read
 * at every tap until now): 'off' if that said off, else 'default' - which marks it carried over
 * without storing the default as if chosen, so it reads as whatever the default is. A choice made in
 * You is 'on' or 'off'. Storage that can't be read or written: on, nothing thrown.
 */
export function readConfirmCancel(): boolean {
  const stored = readRaw(STORAGE_KEYS.playerConfirmCancel)
  if (stored === 'off') return false
  if (stored !== null) return true
  const carried = readPreferences().confirmCancel
  writeRaw(STORAGE_KEYS.playerConfirmCancel, carried ? 'default' : 'off')
  return carried
}

export function writeConfirmCancel(on: boolean): void {
  writeRaw(STORAGE_KEYS.playerConfirmCancel, on ? 'on' : 'off')
}

/* ===== deadwax-player-speed ===== */

/**
 * The player's speed (2.0.0-player.39), per device like the player's other settings. Only a number
 * from 0.25 to 2 is taken (lib/playSpeed's isSpeed, in hundredths as the fader sets it); anything else
 * - nothing stored, a word, 0, 3, storage that can't be read - is 1, the song's own speed, so a bad
 * value never leaves a song playing fast or slow.
 */
export function readPlayerSpeed(): number {
  const saved = readRaw(STORAGE_KEYS.playerSpeed)
  if (saved === null || saved.trim() === '') return SPEED_NORMAL
  const speed = Number(saved)
  return isSpeed(speed) ? roundSpeed(speed) : SPEED_NORMAL
}

export function writePlayerSpeed(speed: number): void {
  writeRaw(STORAGE_KEYS.playerSpeed, String(speed))
}

/* ===== deadwax-player-device ===== */

const DEVICE_LETTERS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-'
const DEVICE_ID = /^[A-Za-z0-9_-]{8,64}$/

/**
 * (2.0.0-player.64) This device's id for its saves of the play queue - what deadwax's record says saved it - made
 * once and kept. 16 characters from crypto.getRandomValues where the browser has it (over plain http too: it needs
 * no secure page, unlike randomUUID), Math.random where it hasn't; read with care like the others - a kept value
 * that isn't one is made again, and where storage is refused the page makes a new one each load (its own queue then
 * reads as another device's: "Picked up from your iPhone" once).
 */
export function readPlayerDevice(): string {
  const saved = readRaw(STORAGE_KEYS.playerDevice)
  if (saved !== null && DEVICE_ID.test(saved)) return saved
  const bytes = new Uint8Array(16)
  const random = typeof crypto !== 'undefined' && typeof crypto.getRandomValues === 'function' ? crypto : null
  if (random) random.getRandomValues(bytes)
  else for (let i = 0; i < bytes.length; i++) bytes[i] = Math.floor(Math.random() * 256)
  const made = Array.from(bytes, (byte) => DEVICE_LETTERS[byte & 63]).join('')
  writeRaw(STORAGE_KEYS.playerDevice, made)
  return made
}

/* ===== deadwax-player-viz-effect, -colours, -style ===== */

/**
 * The desktop visualizer's three choices (2.0.0-player.20), per device like the player's other
 * settings, each validated on read: only a value the visualizer offers today is taken, and anything
 * else - nothing stored, an old or mistyped value, storage that can't be read - is the board's own
 * opening: Ambient, from the cover, the Mandala.
 *
 * The lists are lib/visualizer.ts's, spelled out here rather than imported: this module was shared by
 * the main page's bundle until it retired (2.0.0-player.66), which had no visualizer to carry
 * (ui/test/visualizer.sim.cjs holds every effect and style offered to reading back as itself).
 */
const VIZ_EFFECTS: readonly Effect[] = ['bars', 'scope', 'halo', 'ambient']
const VIZ_COLOURS: readonly Colours[] = ['cover', 'purple']
const VIZ_STYLES: readonly AmbientChoice[] = ['rotate', 'mandala', 'waves', 'liquid', 'burst', 'ribbons', 'smoke', 'rings', 'embers']

export function readVizEffect(): Effect {
  const saved = readRaw(STORAGE_KEYS.playerVizEffect)
  return (VIZ_EFFECTS as readonly string[]).includes(saved ?? '') ? (saved as Effect) : 'ambient'
}

export function writeVizEffect(effect: Effect): void {
  writeRaw(STORAGE_KEYS.playerVizEffect, effect)
}

export function readVizColours(): Colours {
  const saved = readRaw(STORAGE_KEYS.playerVizColours)
  return (VIZ_COLOURS as readonly string[]).includes(saved ?? '') ? (saved as Colours) : 'cover'
}

export function writeVizColours(colours: Colours): void {
  writeRaw(STORAGE_KEYS.playerVizColours, colours)
}

export function readVizStyle(): AmbientChoice {
  const saved = readRaw(STORAGE_KEYS.playerVizStyle)
  return (VIZ_STYLES as readonly string[]).includes(saved ?? '') ? (saved as AmbientChoice) : 'mandala'
}

export function writeVizStyle(choice: AmbientChoice): void {
  writeRaw(STORAGE_KEYS.playerVizStyle, choice)
}

/* ===== deadwax-preferences ===== */

/**
 * Everything the main page's settings tab owned that the server doesn't, as it stored it - the shape
 * of the blob readPreferences reads to carry two of them over once. That page retired in
 * 2.0.0-player.66; the rest are read by nothing.
 */
interface Preferences {
  /* --- search --- */
  /** Initial value of the limit stepper. MusicBrainz caps a page at 100. */
  searchLimit: number
  /** Start every search with the "studio only" release-type filter applied. */
  searchStudioOnly: boolean
  /**
   * How the results list was ordered: one of the ids the retired page's sort.mjs knew.
   *
   * Chronological by default: "sorted by year" is ambiguous, and the reading that matters is
   * reading an artist's output in the order they made it.
   */
  searchSort: string

  /* --- soulseek candidates --- */
  /** Starting position of the min-score slider in the candidates panel, 0-100. */
  candidateMinScore: number
  /** Start with "free slot only" ticked. */
  candidateFreeSlotOnly: boolean
  /** Start with "complete albums only" ticked. */
  candidateCompleteOnly: boolean
  /** Where the Quality dropdown's floors start (v0.9.16). 0 is any. kbps, and bits. */
  candidateMinBitrate: number
  candidateMinBitDepth: number
  /** How the candidates list starts ordered - one of SORT_LABELS in lib/candidates.ts. */
  candidateSort: string

  /* --- interface --- */
  /** Open the log panel on load. Mirrors the existing deadwax-log-open key's job. */
  logOpenOnStart: boolean
  /** Confirm before cancelling an in-flight download. */
  confirmCancel: boolean
}

export const PREFERENCE_FALLBACK: Preferences = {
  searchLimit: 50,
  searchStudioOnly: false,
  searchSort: 'year_asc',
  candidateMinScore: 0,
  candidateFreeSlotOnly: false,
  candidateCompleteOnly: false,
  candidateMinBitrate: 0,
  candidateMinBitDepth: 0,
  candidateSort: 'score',
  logOpenOnStart: false,
  confirmCancel: true,
}

/**
 * The main page's preferences, as that page left them in this browser (it retired in
 * 2.0.0-player.66) - read only to carry the quality floor and Confirm before cancelling over, once
 * (app/useGetSettings.ts, readConfirmCancel above). Nothing writes them now.
 *
 * Every field is validated rather than trusted: this is JSON from localStorage, which a user
 * can edit, an older version may have written, and a newer version may not recognise. A
 * string where searchLimit should be a number would otherwise reach the query builder.
 */
export function readPreferences(): Preferences {
  const stored = readJson<Partial<Preferences>>(STORAGE_KEYS.preferences) ?? {}

  const num = (value: unknown, fallback: number, min: number, max: number): number => {
    const n = typeof value === 'number' ? value : Number(value)
    if (!Number.isFinite(n)) return fallback
    return Math.min(max, Math.max(min, Math.round(n)))
  }

  const bool = (value: unknown, fallback: boolean): boolean =>
    typeof value === 'boolean' ? value : fallback

  return {
    searchLimit: num(stored.searchLimit, PREFERENCE_FALLBACK.searchLimit, 1, 100),
    searchStudioOnly: bool(stored.searchStudioOnly, PREFERENCE_FALLBACK.searchStudioOnly),
    searchSort:
      typeof stored.searchSort === 'string' && stored.searchSort
        ? stored.searchSort
        : PREFERENCE_FALLBACK.searchSort,
    candidateMinScore: num(stored.candidateMinScore, PREFERENCE_FALLBACK.candidateMinScore, 0, 100),
    candidateFreeSlotOnly: bool(
      stored.candidateFreeSlotOnly,
      PREFERENCE_FALLBACK.candidateFreeSlotOnly,
    ),
    candidateCompleteOnly: bool(
      stored.candidateCompleteOnly,
      PREFERENCE_FALLBACK.candidateCompleteOnly,
    ),
    //? only the values the Quality dropdown offers - anything else would show a floor no select
    //? can display
    candidateMinBitrate: [0, 128, 192, 256, 320].includes(Number(stored.candidateMinBitrate))
      ? Number(stored.candidateMinBitrate) : PREFERENCE_FALLBACK.candidateMinBitrate,
    candidateMinBitDepth: [0, 16, 24].includes(Number(stored.candidateMinBitDepth))
      ? Number(stored.candidateMinBitDepth) : PREFERENCE_FALLBACK.candidateMinBitDepth,
    candidateSort: ['score', 'quality', 'size_desc', 'size_asc'].includes(String(stored.candidateSort))
      ? String(stored.candidateSort) : PREFERENCE_FALLBACK.candidateSort,
    logOpenOnStart: bool(stored.logOpenOnStart, PREFERENCE_FALLBACK.logOpenOnStart),
    confirmCancel: bool(stored.confirmCancel, PREFERENCE_FALLBACK.confirmCancel),
  }
}
