import type { LibraryTrack, TrackDetails } from '../api/types'
import { formatSize } from './format'

/**
 * The fields the library's track viewer can show, how to read each one, and how the columns are
 * arranged.
 *
 * One registry for both places a field appears - as a column in an album's track table and as
 * a row in one track's property list - so the menu that toggles them means the same thing in
 * both. That is the whole reason for a registry rather than hand-written markup: the viewer's
 * contents are chosen by the user, so the markup cannot know them in advance.
 */

/**
 * Everything the viewer knows about one track.
 *
 * `track` is the scan's copy: always present, so the basic columns fill in the moment an album
 * is selected. `details` is the file read just now by /library/tracks, and arrives a moment
 * later. Where both have a value the file's own wins, because it is the fresher of the two - the
 * scan is cached on the folder's mtime, which a retag by another tool doesn't move.
 */
export interface TrackRow {
  track: LibraryTrack
  details: TrackDetails | undefined
}

export type FieldGroup = 'Tags' | 'Audio' | 'MusicBrainz' | 'File'

export const FIELD_GROUPS: readonly FieldGroup[] = ['Tags', 'Audio', 'MusicBrainz', 'File']

export interface TrackField {
  id: string
  label: string
  group: FieldGroup
  /** A CSS grid track size, for the table column. */
  width: string
  /** Set in the data face, because it is a number or an id that reads in columns. */
  mono?: boolean
  /** On before anyone has chosen. */
  initial: boolean
  /**
   * True when the scan already carries this, so the cell can fill in before the file's own
   * details arrive. False fields show a placeholder until then rather than a misleading blank.
   */
  fromScan: boolean
  value: (row: TrackRow) => string
  /**
   * When the value shown is a default rather than something the file says, why - the disc of a
   * file with no disc tag. The cell is dimmed and carries this as its tooltip, because a default
   * that looks exactly like a tag is a small lie about what is on disk. null when it is real.
   */
  inferred?: (row: TrackRow) => string | null
}

/** A tag from the file's details, or '' until they arrive. */
const tag = (key: string) => (row: TrackRow) => row.details?.tags[key] ?? ''

/**
 * A number the track carries, from the file itself once it has been read.
 *
 * Once the details are in they win outright, even when they say "none": the scan is cached on
 * the folder's mtime, which a retag by another program doesn't move, so a scan still holding a
 * disc number the file no longer carries is simply out of date.
 */
function fileNumber(row: TrackRow, key: 'position' | 'disc'): number | null {
  const n = row.details ? row.details[key] : row.track[key]
  return n === undefined ? null : n
}

function trackTime(seconds: number | null | undefined): string {
  if (!seconds) return ''
  const whole = Math.round(seconds)
  return `${Math.floor(whole / 60)}:${String(whole % 60).padStart(2, '0')}`
}

function channels(n: number | null | undefined): string {
  if (!n) return ''
  if (n === 1) return 'Mono'
  if (n === 2) return 'Stereo'
  if (n === 6) return '5.1'
  return `${n} ch`
}

export const TRACK_FIELDS: readonly TrackField[] = [
  {
    id: 'number', label: '#', group: 'Tags', width: '2.6em', mono: true,
    initial: true, fromScan: true,
    value: (row) => {
      const n = fileNumber(row, 'position')
      return n === null ? '' : String(n).padStart(2, '0')
    },
  },
  {
    id: 'disc', label: 'Disc', group: 'Tags', width: '3.8em', mono: true,
    initial: true, fromScan: true,
    //? A file with no disc tag is on disc 1: it sorts there, every player reads it that way, and
    //? applying a one-disc release now writes 1 over a stray other number. So the column says 1
    //? rather than nothing - dimmed, and saying why, since the file itself doesn't.
    value: (row) => String(fileNumber(row, 'disc') ?? 1),
    inferred: (row) => (
      fileNumber(row, 'disc') === null ? 'No disc number on the file - it reads as disc 1' : null
    ),
  },
  {
    id: 'artist', label: 'Artist', group: 'Tags', width: 'minmax(8em, 0.7fr)', initial: true,
    fromScan: true, value: ({ track, details }) => details?.tags['artist'] ?? track.artist,
  },
  {
    id: 'albumartist', label: 'Album artist', group: 'Tags', width: 'minmax(8em, 0.6fr)',
    initial: false, fromScan: true,
    value: ({ track, details }) => details?.tags['albumartist'] ?? track.albumartist,
  },
  {
    id: 'album', label: 'Album', group: 'Tags', width: 'minmax(8em, 0.6fr)', initial: false,
    fromScan: true, value: ({ track, details }) => details?.tags['album'] ?? track.album,
  },
  {
    id: 'date', label: 'Date', group: 'Tags', width: '6.5em', mono: true, initial: false,
    fromScan: true, value: ({ track, details }) => details?.tags['date'] ?? track.date,
  },
  {
    id: 'originaldate', label: 'Original date', group: 'Tags', width: '6.5em', mono: true,
    initial: false, fromScan: true,
    value: ({ track, details }) => details?.tags['originaldate'] ?? track.originaldate ?? '',
  },
  { id: 'genre', label: 'Genre', group: 'Tags', width: 'minmax(6em, 0.5fr)', initial: false, fromScan: false, value: tag('genre') },
  { id: 'composer', label: 'Composer', group: 'Tags', width: 'minmax(7em, 0.5fr)', initial: false, fromScan: false, value: tag('composer') },
  { id: 'conductor', label: 'Conductor', group: 'Tags', width: 'minmax(7em, 0.5fr)', initial: false, fromScan: false, value: tag('conductor') },
  { id: 'lyricist', label: 'Lyricist', group: 'Tags', width: 'minmax(7em, 0.5fr)', initial: false, fromScan: false, value: tag('lyricist') },
  { id: 'discsubtitle', label: 'Disc subtitle', group: 'Tags', width: 'minmax(7em, 0.5fr)', initial: false, fromScan: false, value: tag('discsubtitle') },
  {
    id: 'label', label: 'Label', group: 'Tags', width: 'minmax(7em, 0.5fr)', initial: false,
    fromScan: false,
    //? Vorbis files use either name and ID3 only knows `organization` - show whichever is there
    value: ({ details }) => details?.tags['label'] ?? details?.tags['organization'] ?? '',
  },
  { id: 'catalognumber', label: 'Catalog #', group: 'Tags', width: '8em', mono: true, initial: false, fromScan: false, value: tag('catalognumber') },
  { id: 'barcode', label: 'Barcode', group: 'Tags', width: '9em', mono: true, initial: false, fromScan: false, value: tag('barcode') },
  { id: 'isrc', label: 'ISRC', group: 'Tags', width: '9em', mono: true, initial: false, fromScan: false, value: tag('isrc') },
  { id: 'releasecountry', label: 'Country', group: 'Tags', width: '4.5em', initial: false, fromScan: false, value: tag('releasecountry') },
  { id: 'media', label: 'Media', group: 'Tags', width: '6em', initial: false, fromScan: false, value: tag('media') },
  { id: 'bpm', label: 'BPM', group: 'Tags', width: '3.5em', mono: true, initial: false, fromScan: false, value: tag('bpm') },
  { id: 'language', label: 'Language', group: 'Tags', width: '5em', initial: false, fromScan: false, value: tag('language') },
  { id: 'copyright', label: 'Copyright', group: 'Tags', width: 'minmax(8em, 0.5fr)', initial: false, fromScan: false, value: tag('copyright') },
  { id: 'comment', label: 'Comment', group: 'Tags', width: 'minmax(8em, 0.6fr)', initial: false, fromScan: false, value: tag('comment') },

  //? widths are measured against the HEADER label plus its padding, not the values - "Sample
  //? rate" is far wider than "44.1 kHz", and a header cut to "Samp…" names nothing
  {
    id: 'length', label: 'Length', group: 'Audio', width: '5em', mono: true,
    initial: true, fromScan: true,
    value: ({ track, details }) => trackTime(details?.length ?? track.length),
  },
  {
    id: 'format', label: 'Format', group: 'Audio', width: '5em', initial: true, fromScan: true,
    value: ({ track }) => track.format.toUpperCase(),
  },
  { id: 'codec', label: 'Codec', group: 'Audio', width: '6em', initial: false, fromScan: false, value: ({ details }) => details?.codec ?? '' },
  {
    id: 'bitrate', label: 'Bitrate', group: 'Audio', width: '6em', mono: true,
    initial: true, fromScan: false,
    value: ({ details }) => (details?.bitrate ? `${Math.round(details.bitrate / 1000)} kbps` : ''),
  },
  {
    id: 'sample_rate', label: 'Sample rate', group: 'Audio', width: '7em',
    mono: true, initial: true, fromScan: false,
    value: ({ details }) =>
      details?.sample_rate ? `${(details.sample_rate / 1000).toFixed(details.sample_rate % 1000 ? 1 : 0)} kHz` : '',
  },
  {
    id: 'bits', label: 'Bit depth', group: 'Audio', width: '6em', mono: true,
    initial: true, fromScan: false,
    value: ({ details }) => (details?.bits_per_sample ? `${details.bits_per_sample}-bit` : ''),
  },
  { id: 'channels', label: 'Channels', group: 'Audio', width: '6em', initial: false, fromScan: false, value: ({ details }) => channels(details?.channels) },

  { id: 'musicbrainz_trackid', label: 'Recording ID', group: 'MusicBrainz', width: '19em', mono: true, initial: false, fromScan: false, value: tag('musicbrainz_trackid') },
  { id: 'musicbrainz_releasetrackid', label: 'Track ID', group: 'MusicBrainz', width: '19em', mono: true, initial: false, fromScan: false, value: tag('musicbrainz_releasetrackid') },
  {
    id: 'musicbrainz_albumid', label: 'Release ID', group: 'MusicBrainz', width: '19em', mono: true,
    initial: false, fromScan: true,
    value: ({ track, details }) => details?.tags['musicbrainz_albumid'] ?? track.release_mbid,
  },
  { id: 'musicbrainz_releasegroupid', label: 'Release group ID', group: 'MusicBrainz', width: '19em', mono: true, initial: false, fromScan: false, value: tag('musicbrainz_releasegroupid') },
  { id: 'musicbrainz_artistid', label: 'Artist ID', group: 'MusicBrainz', width: '19em', mono: true, initial: false, fromScan: false, value: tag('musicbrainz_artistid') },

  {
    //? which songs carry their OWN picture - what a player shows instead of the album's cover
    id: 'pictures', label: 'Picture', group: 'File', width: '9em',
    initial: false, fromScan: false,
    value: ({ details }) => {
      const [first, ...rest] = details?.pictures ?? []
      if (!first) return ''
      return rest.length ? `${first.label} +${rest.length}` : first.label
    },
  },
  {
    id: 'size', label: 'Size', group: 'File', width: '5em', mono: true,
    initial: false, fromScan: true, value: ({ track }) => formatSize(track.size),
  },
  {
    id: 'filename', label: 'File name', group: 'File', width: 'minmax(10em, 1fr)', mono: true,
    initial: false, fromScan: true, value: ({ track }) => track.filename,
  },
]

const FIELD_BY_ID = new Map(TRACK_FIELDS.map((field) => [field.id, field]))

export function fieldById(id: string): TrackField | undefined {
  return FIELD_BY_ID.get(id)
}

/**
 * The visible field ids, reconciled against what exists now.
 *
 * Ids that no longer exist are dropped, and fields the stored choice has never heard of take
 * their own default. Without the second half a field added in a later version would be off for
 * everyone who had ever touched the menu, with nothing to say it existed.
 */
export function reconcileVisible(saved: { visible: string[]; seen: string[] } | null): string[] {
  if (!saved) return TRACK_FIELDS.filter((f) => f.initial).map((f) => f.id)

  const seen = new Set(saved.seen)
  const visible = new Set(saved.visible)

  return TRACK_FIELDS
    .filter((field) => (seen.has(field.id) ? visible.has(field.id) : field.initial))
    .map((field) => field.id)
}

/* ------------------------------------------------------------------ arranging the columns */

/**
 * The title's id in a column order. Title is always shown, so it never appears in `visible` -
 * but it moves like any other column, which is why it needs an id at all.
 */
export const TITLE_COLUMN = 'title'

/** The title's size until you drag it: at least 10em, and twice anybody else's share of the rest. */
export const TITLE_WIDTH = 'minmax(10em, 2fr)'

/** The narrowest a dragged column may get, in px - enough for its first letters and the grip. */
export const MIN_COLUMN_PX = 36

/** The widest, so one wild drag can't send a column off into the next room. */
export const MAX_COLUMN_PX = 1200

/**
 * Every column in its default order: the number and the disc before the title, as they read on
 * a sleeve, then everything else in registry order.
 */
export function defaultOrder(): string[] {
  const lead = ['number', 'disc']
  return [
    ...lead,
    TITLE_COLUMN,
    ...TRACK_FIELDS.map((field) => field.id).filter((id) => !lead.includes(id)),
  ]
}

/**
 * A saved column order, reconciled against the columns that exist now.
 *
 * Unknown ids are dropped. A column the saved order has never heard of goes in beside its
 * default neighbour - after the nearest column that comes before it by default - rather than on
 * the end, so a field added by a later version turns up where it belongs instead of trailing
 * after everything you arranged. The same promise reconcileVisible's `seen` keeps.
 */
export function reconcileOrder(saved: readonly string[] | null | undefined): string[] {
  const defaults = defaultOrder()
  if (!saved?.length) return defaults

  const known = new Set(defaults)
  const order = [...new Set(saved.filter((id) => known.has(id)))]

  for (const [index, id] of defaults.entries()) {
    if (order.includes(id)) continue
    const neighbour = defaults.slice(0, index).reverse().find((other) => order.includes(other))
    order.splice(neighbour === undefined ? 0 : order.indexOf(neighbour) + 1, 0, id)
  }

  return order
}

/** A dragged width, kept to something a column can sensibly be. */
export function clampWidth(px: number): number {
  return Math.round(Math.min(MAX_COLUMN_PX, Math.max(MIN_COLUMN_PX, px)))
}

/** Saved widths, less any for a column that no longer exists or a size that makes no sense. */
export function reconcileWidths(
  saved: Readonly<Record<string, number>> | null | undefined,
): Record<string, number> {
  const known = new Set(defaultOrder())
  const widths: Record<string, number> = {}

  for (const [id, width] of Object.entries(saved ?? {})) {
    if (known.has(id) && Number.isFinite(width)) widths[id] = clampWidth(width)
  }

  return widths
}

/** The columns to draw: the order, narrowed to the visible fields, with the title always in. */
export function visibleColumns(order: readonly string[], visible: readonly string[]): string[] {
  const shown = new Set(visible)
  return order.filter((id) => id === TITLE_COLUMN || shown.has(id))
}

/**
 * Move one column to just before another, or to the end when `before` is null.
 *
 * Works on the FULL order, hidden columns included, so a column you hide and later show again
 * comes back where you put it rather than where it started.
 */
export function moveColumn(order: readonly string[], id: string, before: string | null): string[] {
  if (id === before) return [...order]

  const rest = order.filter((other) => other !== id)
  const at = before === null ? -1 : rest.indexOf(before)

  return at === -1 ? [...rest, id] : [...rest.slice(0, at), id, ...rest.slice(at)]
}

/** A grid track size's minimum, in em. The registry writes them in em; anything else counts as 6. */
export function minimumEm(width: string): number {
  const match = /(\d+(?:\.\d+)?)em/.exec(width)
  return match ? Number(match[1]) : 6
}

/**
 * The grid template for a row of columns, and the least width the table may shrink to.
 *
 * A column you have sized is exactly that many pixels. The rest keep their registry sizes -
 * mostly fractions - and share whatever is left, so widening one column narrows its flexible
 * neighbours rather than pushing the table off the side. Past everyone's minimum, the table
 * scrolls sideways in its own box instead of squeezing every column to an ellipsis.
 *
 * `leading` is sized tracks drawn before the columns and never moved: the tick boxes.
 */
/** The grid track a column takes when it has not been dragged to a width of its own. */
export function columnSize(id: string): string {
  return id === TITLE_COLUMN ? TITLE_WIDTH : fieldById(id)?.width ?? 'minmax(6em, 1fr)'
}

/**
 * Does this column stretch to fill the row?
 *
 * A flexible column absorbs whatever the others give up, wherever in the row it sits. That is
 * what makes a resize drag pin the flexible columns to its LEFT: without it, widening a column
 * takes the space out of the title beside it, the column's own left edge travels as far as its
 * right edge does, and the grip sits still while the table reflows under the cursor.
 */
export function isFlexible(id: string): boolean {
  return columnSize(id).includes('fr')
}

export function columnLayout(
  columns: readonly string[],
  widths: Readonly<Record<string, number>>,
  leading: readonly string[] = [],
): { template: string; minWidth: string } {
  const tracks = [...leading]
  let em = leading.reduce((total, size) => total + minimumEm(size), 0)
  let px = 0

  for (const id of columns) {
    const fixed = widths[id]
    if (fixed) {
      tracks.push(`${fixed}px`)
      px += fixed
      continue
    }

    const size = columnSize(id)
    tracks.push(size)
    em += minimumEm(size)
  }

  //? EXACTLY the tracks' own minimums. The table has to be at least that wide, or the header's
  //? strip would stop short of columns spilling past it - but any wider and the one flexible
  //? column left swallows the difference. An em of "slack" per column, carried over from the
  //? old sum, made widening the title by 100px widen the table by 250 and the artist by 60.
  return { template: tracks.join(' '), minWidth: `calc(${em}em + ${px}px)` }
}
