/**
 * One tracklist for a release group, and what each pressing changes about it - the TypeScript
 * twin of interface/scripts/tracklistDiff.mjs (2.0.0-player.13), for the app's album-you-don't-
 * have page: its pressing dropdown defaults to the pressing representativeRelease() picks, and each
 * pressing says how it differs from the group's most common tracklist.
 *
 * A PORT, not a new answer. The Docker image's UI stage copies only ui/, so the app can't import
 * the .mjs the main page uses; and the main page can't import this. Both stay until the main page
 * retires, and ui/test/tracklist.sim.cjs runs BOTH against the same real MusicBrainz groups in
 * tests/fixtures/pressings/*.json, so the two can never pick a different pressing or call a
 * different track a bonus. Change one, change the other, and the sim says whether they agree.
 *
 * The reasoning lives in the .mjs and in CLAUDE.md's "One tracklist per release group": the base
 * is the MOST COMMON tracklist (not the first release), tracks pair by folded title along the
 * longest common run, and a length difference is rounding, a length change, or another version.
 */

/** Differences in length up to this many seconds are MusicBrainz rounding, not a change. */
export const LENGTH_TOLERANCE_S = 2

/** Past this (or 8% of the track) a difference is another recording of the song, not rounding. */
export const OTHER_VERSION_S = 15
export const OTHER_VERSION_SHARE = 0.08

/** A track as MusicBrainz shapes it in a release fetched with its recordings. */
export interface MbTrack {
  number?: string
  position?: number
  title?: string
  length?: number | null
  recording?: { title?: string; length?: number | null }
}

/** A medium (a disc, a record) as MusicBrainz shapes it. */
export interface MbMedium {
  position?: number
  format?: string
  title?: string
  tracks?: readonly MbTrack[] | unknown[]
}

/** The parts of a release this reads. */
export interface PressingRelease {
  id?: string
  status?: string
  date?: string
  disambiguation?: string
  media?: readonly MbMedium[]
  'release-events'?: readonly { date?: string }[]
}

/** A track as this pressing prints it. */
export interface PressedTrack {
  title: string
  /** seconds; null when MusicBrainz has no length */
  length: number | null
  /** the pressing's own numbering: "1", "A1", "B5" */
  number: string
  disc: number
}

export interface Base {
  /** the release that stands for the base: the first holding that tracklist, in the order given */
  index: number
  tracks: PressedTrack[]
  /** how many releases share it */
  count: number
  /** how many releases list any tracks */
  total: number
}

export interface AddedTrack {
  position: number
  title: string
  length: number | null
  /** the track it follows in this pressing, null at the very start */
  after: string | null
}

export interface RemovedTrack {
  position: number
  title: string
  length: number | null
}

export interface RenamedTrack {
  position: number
  from: string
  to: string
}

export interface TimedChange {
  position: number
  title: string
  from: number
  to: number
  delta: number
}

export interface TracklistDiff {
  added: AddedTrack[]
  removed: RemovedTrack[]
  renamed: RenamedTrack[]
  /** another version of the song: past OTHER_VERSION_S or OTHER_VERSION_SHARE */
  versions: TimedChange[]
  /** a length change past LENGTH_TOLERANCE_S, short of another version */
  lengths: TimedChange[]
  same: number
}

export type ChipKind = 'same' | 'added' | 'removed' | 'renamed' | 'version' | 'lengths'

/**
 * A title as it should be COMPARED. Curly and straight apostrophes are the same apostrophe -
 * MusicBrainz has both "It's a Fire" and "It’s a Fire" among Dummy's pressings.
 */
export function foldTitle(title: string | null | undefined): string {
  return String(title || '')
    .toLowerCase()
    .replace(/[’‘`´]/g, "'")
    .replace(/[^\p{L}\p{N}']+/gu, ' ')
    .trim()
}

/** A release's tracks in running order, as this pressing prints them. */
export function releaseTracks(release: PressingRelease | null | undefined): PressedTrack[] {
  const tracks: PressedTrack[] = []
  for (const medium of release?.media || []) {
    for (const track of (medium.tracks || []) as MbTrack[]) {
      const ms = track.length ?? track.recording?.length
      tracks.push({
        title: track.title || track.recording?.title || '',
        length: typeof ms === 'number' && Number.isFinite(ms) ? Math.round(ms / 1000) : null,
        number: track.number ?? String(track.position ?? ''),
        disc: medium.position ?? 1,
      })
    }
  }
  return tracks
}

/** What makes two tracklists "the same" for choosing the base: the titles, in order. */
export function tracklistKey(tracks: readonly PressedTrack[]): string {
  return tracks.map((track) => foldTitle(track.title)).join('\n')
}

/**
 * The base: the most common tracklist among releases that list any tracks. Ties go to whichever
 * appears first. Null when fewer than two releases have tracks - one has nothing to be compared with.
 */
export function chooseBase(releases: readonly PressingRelease[]): Base | null {
  const counts = new Map<string, number>()
  const first = new Map<string, number>()

  releases.forEach((release, index) => {
    const tracks = releaseTracks(release)
    if (!tracks.length) return
    const key = tracklistKey(tracks)
    counts.set(key, (counts.get(key) || 0) + 1)
    if (!first.has(key)) first.set(key, index)
  })

  let withTracks = 0
  for (const count of counts.values()) withTracks += count
  if (withTracks < 2) return null

  let bestKey: string | null = null
  for (const [key, count] of counts) {
    if (bestKey === null || count > counts.get(bestKey)!) bestKey = key
  }

  const index = first.get(bestKey!)!
  return {
    index,
    tracks: releaseTracks(releases[index]),
    count: counts.get(bestKey!)!,
    total: withTracks,
  }
}

//? formats a folder name shouldn't be built around when a plainer pressing exists
const PLAIN_FORMATS = ['CD', 'Digital Media']

/**
 * The one pressing that stands for the album: the group's most common tracklist, then Official,
 * then a CD or digital release, then no disambiguation, then the earliest full date (a year alone
 * sorts after full dates in it), then the release id - so the answer never depends on the order
 * the list came in. Null when no release lists any tracks. The page's default pressing, and (from
 * the next slice) the one Get gets.
 */
export function representativeRelease<R extends PressingRelease>(releases: readonly R[]): R | null {
  const withTracks = releases.filter((release) => releaseTracks(release).length)
  if (!withTracks.length) return null

  const base = chooseBase(withTracks)
  const key = base ? tracklistKey(base.tracks) : null
  const pool = key ? withTracks.filter((release) => tracklistKey(releaseTracks(release)) === key) : withTracks

  const plain = (release: R) => (release.media || []).length > 0
    && (release.media || []).every((medium) => PLAIN_FORMATS.includes(medium.format as string))
  //? '~' sorts after every digit and '-': "1994~" after "1994-08-22", "~" alone after all dates
  const date = (release: R) => `${release.date || release['release-events']?.[0]?.date || ''}~`
  const rank = (release: R): (number | string)[] => [
    release.status === 'Official' ? 0 : 1,
    plain(release) ? 0 : 1,
    release.disambiguation ? 1 : 0,
    date(release),
    release.id || '',
  ]

  return pool.reduce((best, release) => {
    const [a, b] = [rank(release), rank(best)]
    for (let i = 0; i < a.length; i++) {
      if (a[i]! < b[i]!) return release
      if (a[i]! > b[i]!) return best
    }
    return best
  })
}

/** Whether a difference in length is another version of the song rather than rounding. */
export function isOtherVersion(deltaSeconds: number, baseSeconds: number | null): boolean {
  return Math.abs(deltaSeconds) >= Math.max(OTHER_VERSION_S, (baseSeconds || 0) * OTHER_VERSION_SHARE)
}

/**
 * What `tracks` changes about `base`. Paired by title along the longest common run, so an inserted
 * bonus track shifts nothing after it; of what is left, an added and a removed track of about the
 * same length are one renamed track. Positions are running positions in THIS pressing (1-based) -
 * a removed track's, in the base's.
 */
export function diffTracklists(
  base: readonly PressedTrack[],
  tracks: readonly PressedTrack[],
  tolerance: number = LENGTH_TOLERANCE_S,
): TracklistDiff {
  const a = base.map((t) => foldTitle(t.title))
  const b = tracks.map((t) => foldTitle(t.title))
  const n = a.length
  const m = b.length

  const lcs = Array.from({ length: n + 1 }, () => new Array<number>(m + 1).fill(0))
  for (let i = n - 1; i >= 0; i--) {
    for (let j = m - 1; j >= 0; j--) {
      lcs[i]![j] = a[i] === b[j] ? lcs[i + 1]![j + 1]! + 1 : Math.max(lcs[i + 1]![j]!, lcs[i]![j + 1]!)
    }
  }

  const added: AddedTrack[] = []
  const removed: RemovedTrack[] = []
  const versions: TimedChange[] = []
  const lengths: TimedChange[] = []
  let same = 0

  let i = 0
  let j = 0
  while (i < n || j < m) {
    if (i < n && j < m && a[i] === b[j]) {
      const from = base[i]!.length
      const to = tracks[j]!.length
      if (from !== null && to !== null && Math.abs(to - from) > tolerance) {
        const change = { position: j + 1, title: tracks[j]!.title, from, to, delta: to - from }
        ;(isOtherVersion(to - from, from) ? versions : lengths).push(change)
      } else {
        same++
      }
      i++
      j++
    } else if (j < m && (i >= n || lcs[i]![j + 1]! >= lcs[i + 1]![j]!)) {
      added.push({
        position: j + 1,
        title: tracks[j]!.title,
        length: tracks[j]!.length,
        after: j > 0 ? tracks[j - 1]!.title : null,
      })
      j++
    } else {
      removed.push({ position: i + 1, title: base[i]!.title, length: base[i]!.length })
      i++
    }
  }

  const renamed: RenamedTrack[] = []
  const pairedAdds = new Set<AddedTrack>()
  const pairedRemoves = new Set<RemovedTrack>()
  for (const add of added) {
    const match = removed.find((rem) => !pairedRemoves.has(rem)
      && (add.length === null || rem.length === null || Math.abs(add.length - rem.length) <= Math.max(tolerance, 5)))
    if (match) {
      pairedRemoves.add(match)
      pairedAdds.add(add)
      renamed.push({ position: add.position, from: match.title, to: add.title })
    }
  }

  return {
    added: added.filter((x) => !pairedAdds.has(x)),
    removed: removed.filter((x) => !pairedRemoves.has(x)),
    renamed,
    versions,
    lengths,
    same,
  }
}

/** Nothing added, removed, renamed or re-timed beyond the tolerance. */
export function isSameTracklist(diff: TracklistDiff): boolean {
  return !diff.added.length && !diff.removed.length && !diff.renamed.length
    && !diff.versions.length && !diff.lengths.length
}

/** The chips a release's row carries on the main page, most telling first. */
export function summarizeDiff(diff: TracklistDiff): { kind: ChipKind; label: string }[] {
  if (isSameTracklist(diff)) return [{ kind: 'same', label: 'Same tracklist' }]

  const plural = (count: number, word: string) => `${count} ${word}${count === 1 ? '' : 's'}`
  const chips: { kind: ChipKind; label: string }[] = []
  if (diff.added.length) chips.push({ kind: 'added', label: `+${plural(diff.added.length, 'track')}` })
  if (diff.removed.length) chips.push({ kind: 'removed', label: `−${plural(diff.removed.length, 'track')}` })
  if (diff.renamed.length) chips.push({ kind: 'renamed', label: `${diff.renamed.length} renamed` })
  if (diff.versions.length) chips.push({ kind: 'version', label: plural(diff.versions.length, 'other version') })
  if (diff.lengths.length) chips.push({ kind: 'lengths', label: plural(diff.lengths.length, 'length') })
  return chips
}

/** `257` -> `4:17`; null stays blank. */
export function formatSeconds(seconds: number | null | undefined): string {
  if (seconds === null || seconds === undefined) return ''
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`
}
