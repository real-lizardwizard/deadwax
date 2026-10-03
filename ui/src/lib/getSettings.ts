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
 *
 * The keys and their values are one list with src/routes/me.py (tests/test_me_prefs.py reads this
 * file to hold the two together).
 */

import type { CandidateFilters, CandidateSort } from './candidates'
import { AUTO_GRAB_MIN_SCORE, NO_QUALITY_FILTERS, noSignalMinimums } from './candidates'

export const GET_MODE_VALUES = ['sources', 'pick'] as const
export const QUALITY_FLOOR_VALUES = ['any', '320', 'lossless', '24bit'] as const

export type GetMode = (typeof GET_MODE_VALUES)[number]
export type QualityFloor = (typeof QUALITY_FLOOR_VALUES)[number]

export interface GetSettings {
  get_mode: GetMode
  quality_floor: QualityFloor
}

/**
 * What the server answers: the settings, which of them the user set, whether anything was ever saved
 * for them (`seeded` - the app carries the main page's floor over once, when it is false), and
 * whether it can keep them.
 */
export interface GetSettingsAnswer extends GetSettings {
  stored: string[]
  seeded: boolean
  can_save: boolean
}

export const GET_SETTINGS_DEFAULT: GetSettings = { get_mode: 'sources', quality_floor: 'any' }

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

/** A server answer, read safely: anything it doesn't recognise is the default. */
export function readGetSettings(answer: Partial<GetSettingsAnswer> | null | undefined): GetSettingsAnswer {
  const mode = GET_MODE_VALUES.find((value) => value === answer?.get_mode) ?? GET_SETTINGS_DEFAULT.get_mode
  const floor = QUALITY_FLOOR_VALUES.find((value) => value === answer?.quality_floor) ?? GET_SETTINGS_DEFAULT.quality_floor
  const stored = Array.isArray(answer?.stored) ? answer!.stored.filter((key): key is string => typeof key === 'string') : []
  return {
    get_mode: mode,
    quality_floor: floor,
    stored,
    //? something stored is something saved, whatever the answer forgot to say
    seeded: answer?.seeded === true || stored.length > 0,
    can_save: answer?.can_save !== false,
  }
}

/**
 * What a user's first read carries over from what the main page's Settings -> Downloads already
 * says on this browser (`deadwax-preferences`): a 24-bit bit-depth floor is 24-bit; a 16-bit one -
 * reported only by lossless files - is Lossless; a 320 kbps bitrate floor is 320. Anything lower is
 * Any - the default, so NOTHING is carried over: the defaults are never saved as if chosen (an
 * absent setting is its default, so a default changed later still reaches this user). "When I tap
 * Get" is never carried over: the main page's auto-grab doesn't make Get pick (James wants Get to
 * show the sources unless he says otherwise). Saved even when empty: the save is what marks the
 * user seeded (routes/me.py SEEDED), so this happens once.
 */
export function seedFromPreferences(preferences: { candidateMinBitrate: number; candidateMinBitDepth: number }): Partial<GetSettings> {
  const floor: QualityFloor = preferences.candidateMinBitDepth >= 24 ? '24bit'
    : preferences.candidateMinBitDepth >= 16 ? 'lossless'
    : preferences.candidateMinBitrate >= 320 ? '320'
    : 'any'
  return floor === GET_SETTINGS_DEFAULT.quality_floor ? {} : { quality_floor: floor }
}

/**
 * The Sources sheet's chips: Lossless, 24-bit and Free slot, as Sources.dc.html draws them - and
 * 320 kbps, which the board has no chip for, drawn only while the floor is 320 so that floor is
 * never a filter on out of sight.
 */
export interface SourceFilters {
  lossless: boolean
  bit24: boolean
  freeSlot: boolean
  kbps320: boolean
}

export const NO_SOURCE_FILTERS: SourceFilters = { lossless: false, bit24: false, freeSlot: false, kbps320: false }

/** What the chips start as, for a Get: the quality floor, pressed. */
export function floorFilters(floor: QualityFloor): SourceFilters {
  return { ...NO_SOURCE_FILTERS, lossless: floor === 'lossless', bit24: floor === '24bit', kbps320: floor === '320' }
}

/** The chips the sheet draws, in order, for a floor and what is pressed now. */
export function sourceChips(floor: QualityFloor, filters: SourceFilters): { key: keyof SourceFilters; label: string; on: boolean }[] {
  const chips: { key: keyof SourceFilters; label: string; on: boolean }[] = [
    { key: 'lossless', label: 'Lossless', on: filters.lossless },
    { key: 'bit24', label: '24-bit', on: filters.bit24 },
    { key: 'freeSlot', label: 'Free slot', on: filters.freeSlot },
  ]
  if (floor === '320' || filters.kbps320) chips.splice(2, 0, { key: 'kbps320', label: '320 kbps', on: filters.kbps320 })
  return chips
}

/** The chips as lib/candidates.ts's filters - what passesFilters, the cards and a pick all go by. */
export function candidateFilters(filters: SourceFilters): CandidateFilters {
  return {
    freeSlotOnly: filters.freeSlot,
    completeOnly: false,
    minScore: 0,
    formats: new Set(),
    minSignals: noSignalMinimums(),
    quality: { ...NO_QUALITY_FILTERS, minBitDepth: filters.bit24 ? 24 : 0, minBitrate: filters.kbps320 ? 320 : 0 },
    lossless: filters.lossless,
  }
}

/** How many chips are pressed - "Clear filters" shows only when some are. */
export function pressedCount(filters: SourceFilters): number {
  return Object.values(filters).filter(Boolean).length
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
