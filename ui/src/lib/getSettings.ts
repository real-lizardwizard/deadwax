/**
 * You > Getting albums (2.0.0-player.15): what Get does, and what a source must at least be - pure,
 * pinned by ui/test/candidates.sim.cjs. Kept per user on the server (GET/PUT /deadwax/me/preferences,
 * src/routes/me.py); app/useGetSettings.ts is the store that asks for them and saves them.
 *
 *  - "When I tap Get": SHOW ME THE SOURCES - the default, James: "I don't think I can reliably trust
 *    automatically grabbing from the correct source" - or PICK THE BEST SOURCE FOR ME: Get takes the
 *    best match that scores AUTO_GRAB_MIN_SCORE or more and passes the quality floor, and shows the
 *    sources, saying why, when nothing does.
 *  - The quality floor: Any, 320 kbps, Lossless, 24-bit. It decides what "passes" means for a pick,
 *    and what the Sources sheet's chips start as - so a floor is never a filter silently on: it is a
 *    chip, drawn pressed, that a tap turns off.
 *  - FORMAT (2.0.0-player.41, the main page's Settings -> Downloads "Format", carried into the app):
 *    Any, Prefer lossless (the default, as the main page's was), Lossless only - sent with every Get as
 *    the find route's `format_preference`, so it changes the SCORE (src/matching.py score_format: a
 *    folder with no lossless file scores 0.45 on format under Prefer lossless, 1 under Any) and Lossless
 *    only leaves such folders out of the answer altogether. Separate from the floor, which filters
 *    the folders found and never changes a score.
 *
 * The keys and their values are one list with src/routes/me.py (tests/test_me_prefs.py reads this
 * file to hold the two together).
 */

import type { FormatPreference } from '../api/types'
import type { CandidateFilters, CandidateSort } from './candidates'
import { AUTO_GRAB_MIN_SCORE, NO_QUALITY_FILTERS, noSignalMinimums } from './candidates'

export const GET_MODE_VALUES = ['sources', 'pick'] as const
export const QUALITY_FLOOR_VALUES = ['any', '320', 'lossless', '24bit'] as const
//? the server's order, the default first (src/routes/me.py); You lists them as FORMATS does, below
export const FORMAT_PREFERENCE_VALUES = ['prefer_lossless', 'any', 'lossless_only'] as const

export type GetMode = (typeof GET_MODE_VALUES)[number]
export type QualityFloor = (typeof QUALITY_FLOOR_VALUES)[number]

export interface GetSettings {
  get_mode: GetMode
  quality_floor: QualityFloor
  format_preference: FormatPreference
}

/** The keys of the settings, as the server lists them - what `unseeded` names. */
export const GET_SETTING_KEYS: readonly (keyof GetSettings)[] = ['get_mode', 'quality_floor', 'format_preference']

/**
 * What the server answers: the settings, which of them the user set, whether anything was ever saved
 * for them (`seeded` - the app carries the main page's settings over once, when it is false), which
 * it has never carried over (`unseeded`, 2.0.0-player.41: every key until the first save; since, a
 * key added in a later version - Format, for a user seeded before it), and whether it can keep them.
 */
export interface GetSettingsAnswer extends GetSettings {
  stored: string[]
  seeded: boolean
  unseeded: (keyof GetSettings)[]
  can_save: boolean
}

export const GET_SETTINGS_DEFAULT: GetSettings = { get_mode: 'sources', quality_floor: 'any', format_preference: 'prefer_lossless' }

/** The two answers to "When I tap Get", in You's words. */
export const GET_MODES: readonly { value: GetMode; label: string }[] = [
  { value: 'sources', label: 'Show me the sources' },
  { value: 'pick', label: 'Pick the best source for me' },
]

/** The quality floors, in You's words. */
export const QUALITY_FLOORS: readonly { value: QualityFloor; label: string }[] = [
  { value: 'any', label: 'Any' },
  { value: '320', label: '320 kbps' },
  { value: 'lossless', label: 'Lossless' },
  { value: '24bit', label: '24-bit' },
]

/** Format, in You's words - the main page's Settings -> Downloads, in its order (2.0.0-player.41). */
export const FORMATS: readonly { value: FormatPreference; label: string }[] = [
  { value: 'any', label: 'Any' },
  { value: 'prefer_lossless', label: 'Prefer lossless' },
  { value: 'lossless_only', label: 'Lossless only' },
]

/** A server answer, read safely: anything it doesn't recognise is the default. */
export function readGetSettings(answer: Partial<GetSettingsAnswer> | null | undefined): GetSettingsAnswer {
  const mode = GET_MODE_VALUES.find((value) => value === answer?.get_mode) ?? GET_SETTINGS_DEFAULT.get_mode
  const floor = QUALITY_FLOOR_VALUES.find((value) => value === answer?.quality_floor) ?? GET_SETTINGS_DEFAULT.quality_floor
  const format = FORMAT_PREFERENCE_VALUES.find((value) => value === answer?.format_preference) ?? GET_SETTINGS_DEFAULT.format_preference
  const stored = Array.isArray(answer?.stored) ? answer!.stored.filter((key): key is string => typeof key === 'string') : []
  //? something stored is something saved, whatever the answer forgot to say
  const seeded = answer?.seeded === true || stored.length > 0
  //? only keys there are; an answer that doesn't say means every key before a first save, none after
  const unseeded = Array.isArray(answer?.unseeded)
    ? GET_SETTING_KEYS.filter((key) => (answer!.unseeded as unknown[]).includes(key))
    : seeded ? [] : [...GET_SETTING_KEYS]
  return {
    get_mode: mode,
    quality_floor: floor,
    format_preference: format,
    stored,
    seeded,
    unseeded,
    can_save: answer?.can_save !== false,
  }
}

/**
 * What a user's first read carries over from what the main page's Settings -> Downloads left on
 * this browser (`deadwax-preferences`), where it was used before it retired in 2.0.0-player.66: a 24-bit bit-depth floor is 24-bit; a 16-bit one -
 * reported only by lossless files - is Lossless; a 320 kbps bitrate floor is 320. Anything lower is
 * Any - the default, so NOTHING is carried over: the defaults are never saved as if chosen (an
 * absent setting is its default, so a default changed later still reaches this user). And Format
 * (2.0.0-player.41), from `deadwax-download-defaults`' formatPreference - again only when it isn't
 * Prefer lossless, the default. "When I tap Get" is never carried over: the main page's auto-grab
 * didn't make Get pick (James wants Get to show the sources unless he says otherwise). Saved even
 * when empty: the save is what marks the user seeded (routes/me.py SEEDED), so this happens once.
 *
 * `keys`, when given, is what is left to carry over (the server's `unseeded`): a user seeded before
 * Format existed gets Format alone, never the floor again over what they chose in the app since.
 */
export function seedFromPreferences(
  preferences: { candidateMinBitrate: number; candidateMinBitDepth: number; formatPreference?: FormatPreference },
  keys: readonly (keyof GetSettings)[] = GET_SETTING_KEYS,
): Partial<GetSettings> {
  const floor: QualityFloor = preferences.candidateMinBitDepth >= 24 ? '24bit'
    : preferences.candidateMinBitDepth >= 16 ? 'lossless'
    : preferences.candidateMinBitrate >= 320 ? '320'
    : 'any'
  const format = FORMAT_PREFERENCE_VALUES.find((value) => value === preferences.formatPreference) ?? GET_SETTINGS_DEFAULT.format_preference
  const seed: Partial<GetSettings> = {}
  if (keys.includes('quality_floor') && floor !== GET_SETTINGS_DEFAULT.quality_floor) seed.quality_floor = floor
  if (keys.includes('format_preference') && format !== GET_SETTINGS_DEFAULT.format_preference) seed.format_preference = format
  return seed
}

/**
 * The Sources sheet's chips: Lossless, 24-bit and Free slot, as Sources.dc.html draws them - and
 * 320 kbps, which the board has no chip for, drawn only while the floor is 320 so that floor is
 * never a filter on out of sight - and Complete albums only (2.0.0-player.50, the main page's, on
 * both frames): every track of the pressing present, as the card counts its Tracks
 * (lib/candidates.ts everyTrackPresent). No setting presses it: every Get starts with it off.
 */
export interface SourceFilters {
  lossless: boolean
  bit24: boolean
  freeSlot: boolean
  kbps320: boolean
  complete: boolean
}

export const NO_SOURCE_FILTERS: SourceFilters = { lossless: false, bit24: false, freeSlot: false, kbps320: false, complete: false }

/**
 * The desktop panel's sample-rate floor (2.0.0-player.50), beside Signals: the least the folder's WORST
 * file's sample rate may be, in Hz, 0 for any - and a folder whose client reported no sample rate never
 * passes one (lib/candidates.ts passesQuality, the main page's own rule: many clients report none, and a
 * folder that might be 44.1 must not pass "96 kHz+"). A desktop's alone, as Signals is: a phone's sheet
 * draws no such chip, so none applies there.
 */
export const SAMPLE_RATE_FLOORS: readonly { value: number; label: string; chip: string }[] = [
  { value: 0, label: 'Any sample rate', chip: 'Sample rate' },
  { value: 44100, label: '44.1 kHz or more', chip: '44.1 kHz+' },
  { value: 48000, label: '48 kHz or more', chip: '48 kHz+' },
  { value: 88200, label: '88.2 kHz or more', chip: '88.2 kHz+' },
  { value: 96000, label: '96 kHz or more', chip: '96 kHz+' },
]

/** What the sample-rate chip says: "Sample rate" for any, else its floor - "48 kHz+". */
export function sampleRateChip(rate: number): string {
  return (SAMPLE_RATE_FLOORS.find((floor) => floor.value === rate) ?? SAMPLE_RATE_FLOORS[0]!).chip
}

/** What the chips start as, for a Get: the quality floor, pressed. */
export function floorFilters(floor: QualityFloor): SourceFilters {
  return { ...NO_SOURCE_FILTERS, lossless: floor === 'lossless', bit24: floor === '24bit', kbps320: floor === '320' }
}

/** The chips the sheet draws, in order, for a floor and what is pressed now - the desktop panel drawing
 *  Complete albums only after its Signals chip (Sources.tsx, review). */
export function sourceChips(floor: QualityFloor, filters: SourceFilters): { key: keyof SourceFilters; label: string; on: boolean }[] {
  const chips: { key: keyof SourceFilters; label: string; on: boolean }[] = [
    { key: 'lossless', label: 'Lossless', on: filters.lossless },
    { key: 'bit24', label: '24-bit', on: filters.bit24 },
    { key: 'freeSlot', label: 'Free slot', on: filters.freeSlot },
  ]
  if (floor === '320' || filters.kbps320) chips.splice(2, 0, { key: 'kbps320', label: '320 kbps', on: filters.kbps320 })
  chips.push({ key: 'complete', label: 'Complete albums only', on: filters.complete })
  return chips
}

/**
 * The chips as lib/candidates.ts's filters - what passesFilters, the cards and a pick all go by. And
 * on a desktop (2.0.0-player.19) the Signals chip's per-signal minimums, as the main page's panel had
 * them (DesktopRequest.dc.html draws the chip; the phone's sheet has none, so none apply there) - and
 * its sample-rate floor (2.0.0-player.50, Hz, 0 for any), likewise a desktop's alone. Complete albums
 * only is the app's every-track rule (`everyTrack`), never the main page's `completeOnly`.
 */
export function candidateFilters(filters: SourceFilters, minSignals?: Readonly<Record<string, number>>, minSampleRate = 0): CandidateFilters {
  return {
    freeSlotOnly: filters.freeSlot,
    completeOnly: false,
    minScore: 0,
    formats: new Set(),
    minSignals: minSignals ? { ...noSignalMinimums(), ...minSignals } : noSignalMinimums(),
    quality: { ...NO_QUALITY_FILTERS, minBitDepth: filters.bit24 ? 24 : 0, minBitrate: filters.kbps320 ? 320 : 0, minSampleRate },
    lossless: filters.lossless,
    everyTrack: filters.complete,
  }
}

/** How many chips are pressed - "Clear filters" shows only when some are - and how many of the
 *  Signals chip's minimums are set (a desktop's), each one as a chip pressed, and the sample-rate
 *  floor (2.0.0-player.50, a desktop's) as one more when it is set. */
export function pressedCount(filters: SourceFilters, minSignals?: Readonly<Record<string, number>>, minSampleRate = 0): number {
  return Object.values(filters).filter(Boolean).length + signalsSet(minSignals) + (minSampleRate > 0 ? 1 : 0)
}

/** How many per-signal minimums are set (0 is off): what the Signals chip counts. */
export function signalsSet(minSignals?: Readonly<Record<string, number>>): number {
  return minSignals ? Object.values(minSignals).filter((value) => value > 0).length : 0
}

/** A pick is always by best match: "the best match that passes your quality floor". */
export const PICK_SORT: CandidateSort = 'score'

/**
 * Why Get showed the sources when it was set to pick one: the pressing is held or on its way, or
 * there was no tracklist (or no release id) to judge the folders by (lib/candidates.ts
 * autoPickBlocked), or nothing scored well enough under the filters.
 */
export function notPickedLine(blocked: string | null): string {
  return blocked
    ? `Didn't pick a source for you: ${blocked}.`
    : `Didn't pick a source for you: none scores ${AUTO_GRAB_MIN_SCORE} or more and passes your filters.`
}
