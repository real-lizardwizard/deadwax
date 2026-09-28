import { useCallback, useState } from 'preact/hooks'

import type { FormatPreference } from '../api/types'

/**
 * localStorage-backed state.
 *
 * These keys are already set in users' browsers by the vanilla app. Changing a key name or a
 * value shape silently resets everyone's preferences, so treat them as a compatibility
 * surface: read defensively, keep the serialization identical, and reconcile unknown values
 * rather than discarding the whole blob.
 */
export const STORAGE_KEYS = {
  downloadDefaults: 'deadwax-download-defaults',
  /**
   * Preferences owned by the settings tab that aren't download defaults.
   *
   * A NEW key rather than more fields on deadwax-download-defaults, because that blob is
   * read and rewritten wholesale by the vanilla app too - anything it doesn't know about
   * would survive only until the next time main.js saved. New key, one writer.
   */
  preferences: 'deadwax-preferences',
  /**
   * Which fields the library's track viewer shows. Its own key, written only by the viewer's
   * field menu - the same one-writer rule as `preferences` above, which the settings tab
   * rewrites wholesale from its own copy.
   */
  libraryFields: 'deadwax-library-fields',
  /** Where the library's splitter sits: the tree pane's width in px. */
  libraryPaneWidth: 'deadwax-library-pane-width',
  /** How the library tree is arranged, and which way round. */
  librarySort: 'deadwax-library-sort',
  /** Which settings tab was open last (v0.9.15). The literal tab id, not JSON. */
  settingsTab: 'deadwax-settings-tab',
  /** Which order the player's album grid is in - a Subsonic album list type. */
  playerOrder: 'deadwax-player-order',
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

export interface DownloadDefaults {
  formatPreference: FormatPreference
  autoGrab: boolean
}

const DOWNLOAD_DEFAULTS_FALLBACK: DownloadDefaults = {
  formatPreference: 'prefer_lossless',
  autoGrab: false,
}

const FORMAT_PREFERENCES: readonly FormatPreference[] = ['any', 'prefer_lossless', 'lossless_only']

/**
 * A one-off read for code that isn't a component - the candidates panel reads it per search,
 * so a preference changed in the settings tab applies to the very next one (as main.js's
 * getSettings() did). An unknown format falls back rather than being sent.
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

/**
 * Merged over the fallback rather than replacing it: the vanilla app persists whatever
 * partial object it happens to hold, so a stored blob may be missing either field.
 */
export function useDownloadDefaults(): [
  DownloadDefaults,
  (partial: Partial<DownloadDefaults>) => void,
] {
  const [value, setValue] = useState<DownloadDefaults>(() => ({
    ...DOWNLOAD_DEFAULTS_FALLBACK,
    ...(readJson<Partial<DownloadDefaults>>(STORAGE_KEYS.downloadDefaults) ?? {}),
  }))

  const update = useCallback((partial: Partial<DownloadDefaults>) => {
    setValue((current) => {
      const next = { ...current, ...partial }
      writeRaw(STORAGE_KEYS.downloadDefaults, JSON.stringify(next))
      return next
    })
  }, [])

  return [value, update]
}

/* ===== deadwax-library-fields ===== */

/**
 * The viewer's field choices. `seen` is every field id that existed when this was written, so
 * a field added by a LATER version can tell "you turned me off" (in seen, not in visible) from
 * "you have never been asked about me" (not in seen) - and take its own default in the second
 * case rather than silently staying hidden forever.
 */
export interface LibraryFieldState {
  visible: string[]
  seen: string[]
  /**
   * Every column in the order you arranged them, the title and hidden fields included, so a
   * field hidden and shown again comes back where you put it. Absent until you move one, so a
   * later version's default order still reaches everyone who never did.
   */
  order?: string[]
  /** Columns you have dragged to a width, in px. A column not in here keeps its own size. */
  widths?: Record<string, number>
}

export function readLibraryFields(): LibraryFieldState | null {
  const saved = readJson<Partial<LibraryFieldState>>(STORAGE_KEYS.libraryFields)
  if (!saved || !Array.isArray(saved.visible) || !Array.isArray(saved.seen)) return null

  const strings = (list: unknown[]) => list.filter((v): v is string => typeof v === 'string')

  //? JSON a user can edit: a width that isn't a positive number is dropped rather than trusted
  const widths: Record<string, number> = {}
  if (saved.widths && typeof saved.widths === 'object') {
    for (const [id, width] of Object.entries(saved.widths as Record<string, unknown>)) {
      if (typeof width === 'number' && Number.isFinite(width) && width > 0) widths[id] = width
    }
  }

  return {
    visible: strings(saved.visible),
    seen: strings(saved.seen),
    order: Array.isArray(saved.order) ? strings(saved.order) : [],
    widths,
  }
}

export function writeLibraryFields(state: LibraryFieldState): void {
  writeRaw(STORAGE_KEYS.libraryFields, JSON.stringify(state))
}

/* ===== deadwax-library-pane-width ===== */

export function readLibraryPaneWidth(): number | null {
  const n = Number(readRaw(STORAGE_KEYS.libraryPaneWidth))
  return Number.isFinite(n) && n > 0 ? n : null
}

export function writeLibraryPaneWidth(width: number): void {
  writeRaw(STORAGE_KEYS.libraryPaneWidth, String(Math.round(width)))
}

/* ===== deadwax-library-sort ===== */

/**
 * Returned as plain strings on purpose: this is JSON a user can edit and an older version may
 * have written, so the library view validates both against the sorts that exist today.
 */
export function readLibrarySort(): { sort: string; direction: string } | null {
  const saved = readJson<{ sort?: unknown; direction?: unknown }>(STORAGE_KEYS.librarySort)
  if (!saved || typeof saved.sort !== 'string' || typeof saved.direction !== 'string') return null
  return { sort: saved.sort, direction: saved.direction }
}

export function writeLibrarySort(value: { sort: string; direction: string }): void {
  writeRaw(STORAGE_KEYS.librarySort, JSON.stringify(value))
}

export function readSettingsTab(): string | null {
  return readRaw(STORAGE_KEYS.settingsTab)
}

export function writeSettingsTab(tab: string): void {
  writeRaw(STORAGE_KEYS.settingsTab, tab)
}

/* ===== deadwax-player-order ===== */

/** A plain string, validated by the player against the orders it offers today. */
export function readPlayerOrder(): string | null {
  return readRaw(STORAGE_KEYS.playerOrder)
}

export function writePlayerOrder(order: string): void {
  writeRaw(STORAGE_KEYS.playerOrder, order)
}

/* ===== deadwax-preferences ===== */

/**
 * Everything the settings tab owns that the server doesn't.
 *
 * These are all genuinely wired to behaviour - nothing here is a switch that does nothing.
 * Where a preference sets the STARTING value of a control (the search limit, the candidate
 * filters), it is applied when that control initialises and the control stays free to be
 * changed for one search without changing the default. A default you can't temporarily
 * override is an annoyance, not a preference.
 */
export interface Preferences {
  /* --- search --- */
  /** Initial value of the limit stepper. MusicBrainz caps a page at 100. */
  searchLimit: number
  /** Start every search with the "studio only" release-type filter applied. */
  searchStudioOnly: boolean
  /**
   * How the results list is ordered. One of the ids in interface/scripts/sort.js.
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
 * Read preferences without a hook, for the vanilla half.
 *
 * main.js needs these at module scope to seed the limit stepper and the candidate filters,
 * and it cannot call a Preact hook. Exported through window.deadwax - see bridge.ts.
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

export function usePreferences(): [Preferences, (partial: Partial<Preferences>) => void, () => void] {
  const [value, setValue] = useState<Preferences>(readPreferences)

  const update = useCallback((partial: Partial<Preferences>) => {
    setValue((current) => {
      const next = { ...current, ...partial }
      writeRaw(STORAGE_KEYS.preferences, JSON.stringify(next))
      return next
    })
  }, [])

  const reset = useCallback(() => {
    writeRaw(STORAGE_KEYS.preferences, JSON.stringify(PREFERENCE_FALLBACK))
    setValue(PREFERENCE_FALLBACK)
  }, [])

  return [value, update, reset]
}
