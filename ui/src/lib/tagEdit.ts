import type { TrackDetails, TrackTagEdit } from '../api/types'

/**
 * Editing tags by hand: which fields, what a selection holds in each, and what to send.
 *
 * Pure, so ui/test/tags.sim.cjs can hold it to account. The failure this guards against is a
 * silent one: a mass edit that sent the form's value back for a field you never touched would
 * overwrite every track's own with whatever the form happened to show - and nothing on screen
 * would say so until you looked at the files.
 */

export interface EditField {
  /** mutagen's easy-interface name - the one src/track_tags.py and the track viewer both use. */
  key: string
  label: string
  /** Numbers and dates are short, and sit two to a row. */
  short?: boolean
  /** Brings up the number pad on a phone. */
  numeric?: boolean
}

/**
 * The fields the editor offers, in the order it lists them.
 *
 * MUST match EDITABLE_TAGS in src/track_tags.py key for key, in order: tests/test_track_tags.py
 * reads this block and fails when the two drift. A field offered here that the server refuses
 * would fail on every save; one the server takes that isn't offered here is dead code.
 */
export const EDIT_FIELDS: readonly EditField[] = [
  { key: 'title', label: 'Title' },
  { key: 'artist', label: 'Artist' },
  { key: 'album', label: 'Album' },
  { key: 'albumartist', label: 'Album artist' },
  { key: 'tracknumber', label: 'Track', short: true, numeric: true },
  { key: 'discnumber', label: 'Disc', short: true, numeric: true },
  { key: 'date', label: 'Year', short: true },
  { key: 'originaldate', label: 'Original year', short: true },
  { key: 'genre', label: 'Genre' },
  { key: 'composer', label: 'Composer' },
]

/** What one field holds across the files being edited. */
export interface SharedValue {
  /** The value every file agrees on, or '' when they disagree - or all go without. */
  value: string
  /** The files disagree, so the field starts empty and an untouched field keeps each one's own. */
  mixed: boolean
}

export function sharedValue(files: readonly TrackDetails[], key: string): SharedValue {
  const values = new Set(files.map((file) => file.tags[key] ?? ''))
  if (values.size > 1) return { value: '', mixed: true }
  return { value: [...values][0] ?? '', mixed: false }
}

/**
 * The edits to send: every edited field, for every file being edited.
 *
 * Only EDITED fields. A field left alone is not in the draft, so it is in no edit - which is what
 * keeps mixed values mixed. An edited field that is empty goes as '' and removes the tag, which
 * the preview spells out before anything is written.
 */
export function buildEdits(
  filenames: readonly string[],
  draft: Readonly<Record<string, string>>,
): TrackTagEdit[] {
  const keys = Object.keys(draft)
  if (!keys.length) return []

  const tags = Object.fromEntries(keys.map((key) => [key, (draft[key] ?? '').trim()]))
  return filenames.map((filename) => ({ filename, tags: { ...tags } }))
}

const NUMBER = /^\d{1,4}(\/\d{1,4})?$/
const DATE = /^\d{4}(-\d{2}(-\d{2})?)?$/
const CONTROL = /[\x00-\x1f\x7f]/

/**
 * Why a value can't go in a field, or null. An empty value is fine: it removes the tag.
 *
 * Mirrors validate_tag() in src/track_tags.py, so a mistake shows under the field as you type
 * rather than a round trip later. The server's check is the one that counts.
 */
export function tagProblem(key: string, value: string): string | null {
  const text = value.trim()
  if (!text) return null
  if (text.length > 1000) return 'Longer than 1000 characters'
  if (CONTROL.test(text)) return 'One line only'
  if ((key === 'tracknumber' || key === 'discnumber') && !NUMBER.test(text)) {
    return 'Has to be a number, like 3 or 3/12'
  }
  if ((key === 'date' || key === 'originaldate') && !DATE.test(text)) {
    return 'Has to be a year or a date, like 2022 or 2022-07-29'
  }
  return null
}

/**
 * Tick one track, or a run of them.
 *
 * A shift-click takes every track between the last one clicked and this one to the state this
 * one is going to - ticking a run, or unticking it - the way a mail client's list does. With
 * nothing clicked before it, it is an ordinary click.
 */
export function tickTracks(
  order: readonly string[],
  ticked: ReadonlySet<string>,
  anchor: string | null,
  clicked: string,
  range: boolean,
): { files: Set<string>; anchor: string } {
  const next = new Set(ticked)
  const on = !ticked.has(clicked)
  const from = anchor === null ? -1 : order.indexOf(anchor)
  const to = order.indexOf(clicked)

  const run = range && from !== -1 && to !== -1
    ? order.slice(Math.min(from, to), Math.max(from, to) + 1)
    : [clicked]

  for (const name of run) {
    if (on) next.add(name)
    else next.delete(name)
  }

  return { files: next, anchor: clicked }
}
