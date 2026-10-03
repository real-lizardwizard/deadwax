/**
 * The album you don't have (2.0.0-player.13): its pressing dropdown, the chosen pressing's
 * tracklist, and how that pressing differs from the usual one - pure, pinned by
 * ui/test/pressings.sim.cjs against real MusicBrainz groups (tests/fixtures/pressings/).
 *
 * James: "for both, I'd like the album page to show the tracklist instead of the release list.
 * Then there should be a dropdown somewhere to pick which release you're viewing, with the most
 * common as default", and "show the bonus track differences on an album that has them".
 *
 *  - THE DEFAULT is representativeRelease() (lib/tracklistDiff.ts, the main page's rule ported):
 *    the group's most common tracklist, then Official, CD or digital, no disambiguation, earliest.
 *    The same pressing a card's Find downloads as, and the one Get gets until you choose another.
 *  - "THE USUAL TRACKLIST" is chooseBase()'s: the most common, by titles in order. A pressing has it
 *    when nothing is added, left out, renamed or another version - a few seconds' difference in
 *    a length is MusicBrainz rounding or a pressing's own timing, and doesn't count (so the app,
 *    unlike the main page's "N lengths" chip, never marks one). Its TITLES are chooseBase's; its
 *    LENGTHS are the default pressing's (one of those holding it), so the pressing the page opens
 *    on is always the usual tracklist itself, whatever order MusicBrainz listed the pressings in.
 *    chooseBase lends the lengths of whichever such pressing came FIRST, and with a single mix
 *    listed first the default read "another version of Borderline" against itself (review).
 *  - THE DROPDOWN shows the default, one pressing of each other format that has the usual tracklist
 *    (so a vinyl is one tap away), every pressing that differs, then "N more pressings with the
 *    usual tracklist", which expands. The pressing chosen is always in view.
 *  - THE TRACKLIST is the chosen pressing's own - its titles, its lengths, its discs - with a Bonus
 *    row for a track the usual tracklist hasn't, "Other version" for one far enough from the usual
 *    length, "Renamed" for a new title at about the same length, and what it leaves out listed
 *    after it. Disc headings carry MusicBrainz's medium titles ("Disc 2 · Unreleased Tracks") by
 *    the album page's own rule (lib/discTitles.ts): shown for more than one disc, or any title.
 */

import type { ArtistCredit, ReleaseGroup } from '../api/types'
import { creditName } from './release'
import { groupKind, groupYear } from './searchResults'
import {
  chooseBase, diffTracklists, formatSeconds, releaseTracks, representativeRelease, tracklistKey,
  type Base, type MbTrack, type PressingRelease, type TracklistDiff,
} from './tracklistDiff'

/** A release as the page reads it: tracklistDiff's parts, and what its label is made of. */
export interface PageRelease extends PressingRelease {
  id: string
  title?: string
  country?: string
  'artist-credit'?: ArtistCredit[]
  'label-info'?: readonly { label?: { name?: string } | null }[]
  /** the album it is a pressing of - /release_group asks MusicBrainz for it (`inc=release-groups`) */
  'release-group'?: ReleaseGroup | null
}

/** A MusicBrainz id as MusicBrainz writes one - the pattern /release_group refuses anything else by. */
const MBID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/

/**
 * A group id from an address, as MusicBrainz writes it - lowercased, or null when it isn't one. A
 * link typed or pasted in upper case still opens; anything else is "not a MusicBrainz album link",
 * never a request deadwax would refuse with a 422 that reads as a URL (review).
 */
export function groupMbid(id: string): string | null {
  const lowered = id.trim().toLowerCase()
  return MBID.test(lowered) ? lowered : null
}

export type PressingKind = 'usual' | 'differs' | 'none'

export interface PressingRow {
  id: string
  /** "CD · 2008 · GB · Island" */
  label: string
  /** how it compares with the usual tracklist, in a few words */
  note: string
  kind: PressingKind
  /** the one the page opens on */
  isDefault: boolean
}

export interface PressingsView {
  base: Base | null
  defaultId: string | null
  /** the pressing shown: the one asked for when the group has it, else the default */
  chosenId: string | null
  /** the dropdown's list, before "N more" */
  shown: PressingRow[]
  /** the pressings with the usual tracklist folded under "N more" */
  more: PressingRow[]
  /** each pressing's differences from the usual tracklist (null without a base, or tracks) */
  diffs: Map<string, TracklistDiff | null>
}

const plural = (count: number, word: string) => `${count} ${word}${count === 1 ? '' : 's'}`

/** Up to two names, then how many more: "Patience", "A and B", "A, B and 2 more". */
function names(titles: readonly string[]): string {
  if (titles.length <= 2) return titles.join(' and ')
  return `${titles.slice(0, 2).join(', ')} and ${titles.length - 2} more`
}

const FORMAT_WORDS: Record<string, string> = { 'Digital Media': 'Digital' }

/** A pressing's formats: "CD", '2×12" Vinyl', "USB Flash Drive + 3×12\" Vinyl". */
export function pressingFormat(release: Pick<PressingRelease, 'media'>): string {
  const runs: [string, number][] = []
  for (const medium of release.media ?? []) {
    const format = FORMAT_WORDS[medium.format ?? ''] ?? medium.format ?? ''
    if (!format) continue
    const last = runs[runs.length - 1]
    if (last && last[0] === format) last[1]++
    else runs.push([format, 1])
  }
  return runs.map(([format, count]) => (count > 1 ? `${count}×${format}` : format)).join(' + ')
}

/** The year a pressing came out, or ''. */
export function pressingYear(release: Pick<PressingRelease, 'date' | 'release-events'>): string {
  const year = (release.date || release['release-events']?.[0]?.date || '').slice(0, 4)
  return /^\d{4}$/.test(year) ? year : ''
}

//? XW is worldwide - it says nothing; XE is MusicBrainz's code for Europe
const COUNTRY_WORDS: Record<string, string> = { XW: '', XE: 'Europe' }

/** "CD · 2008 · GB · Island": formats, year, country, then what tells it apart - its disambiguation,
 *  else its first label. */
export function pressingLabel(release: PageRelease): string {
  const country = release.country ? (COUNTRY_WORDS[release.country] ?? release.country) : ''
  const label = release.disambiguation?.trim() || release['label-info']?.find((info) => info?.label?.name)?.label?.name || ''
  const parts = [pressingFormat(release), pressingYear(release), country, label].filter(Boolean)
  return parts.length ? parts.join(' · ') : release.title || 'A pressing'
}

/** Whether a pressing differs from the usual tracklist - a length's few seconds aside. */
export function differs(diff: TracklistDiff): boolean {
  return !!(diff.added.length || diff.removed.length || diff.renamed.length || diff.versions.length)
}

function pressingNote(kind: PressingKind, diff: TracklistDiff | null, isDefault: boolean, base: Base | null): string {
  if (kind === 'none') return 'No tracklist on MusicBrainz'
  if (!base || !diff) return 'The only tracklist MusicBrainz has'
  if (kind === 'usual') return isDefault ? `The usual tracklist · ${sharedBy(base)}` : 'Same tracklist as the usual one'
  const parts: string[] = []
  if (diff.added.length) parts.push(`+${plural(diff.added.length, 'bonus track')}: ${names(diff.added.map((t) => t.title))}`)
  if (diff.removed.length) parts.push(`Without ${diff.removed.length > 2 ? plural(diff.removed.length, 'track') : names(diff.removed.map((t) => t.title))}`)
  if (diff.renamed.length) parts.push(`${plural(diff.renamed.length, 'track')} renamed`)
  if (diff.versions.length) {
    const [only] = diff.versions
    parts.push(diff.versions.length === 1 && only
      ? `1 other version: ${only.title}, ${formatSeconds(only.to)}`
      : `${plural(diff.versions.length, 'other version')}: ${names(diff.versions.map((t) => t.title))}`)
  }
  return parts.join(' · ')
}

/** "shared by 9 of 10 pressings", "shared by all 4 pressings". */
export function sharedBy(base: Pick<Base, 'count' | 'total'>): string {
  return base.count === base.total ? `shared by all ${base.total} pressings` : `shared by ${base.count} of ${base.total} pressings`
}

/** A date to sort by: full dates first in a year, undated last (tracklistDiff's '~' trick). */
const sortDate = (release: PressingRelease) => `${release.date || release['release-events']?.[0]?.date || ''}~`

/**
 * Every pressing of a group as the dropdown lists them, and which is shown - `asked` is the one the
 * address names, when the group has it.
 */
export function pressingsView(releases: readonly PageRelease[], asked: string | null = null): PressingsView {
  const base = chooseBase(releases)
  const usualKey = base ? tracklistKey(base.tracks) : null
  const fallback = representativeRelease(releases)
  const defaultId = fallback?.id ?? releases[0]?.id ?? null
  const chosenId = asked && releases.some((release) => release.id === asked) ? asked : defaultId
  //? what every pressing is compared with: the usual titles at the DEFAULT pressing's lengths (it
  //? always holds them - representativeRelease picks from chooseBase's pool), never the lengths of
  //? whichever pressing MusicBrainz happened to list first
  const fallbackTracks = fallback ? releaseTracks(fallback) : []
  const reference = !base ? null
    : fallbackTracks.length && tracklistKey(fallbackTracks) === usualKey ? fallbackTracks : base.tracks

  const diffs = new Map<string, TracklistDiff | null>()
  const rows = releases.map((release): PressingRow & { format: string; date: string } => {
    const tracks = releaseTracks(release)
    const diff = reference && tracks.length ? diffTracklists(reference, tracks) : null
    diffs.set(release.id, diff)
    const kind: PressingKind = !tracks.length ? 'none'
      : !base ? 'usual'
      : diff && !differs(diff) && tracklistKey(tracks) === usualKey ? 'usual' : 'differs'
    const isDefault = release.id === defaultId
    return { id: release.id, label: pressingLabel(release), note: pressingNote(kind, diff, isDefault, base), kind, isDefault,
      format: pressingFormat(release), date: sortDate(release) }
  })

  const byDate = (a: { date: string; label: string }, b: { date: string; label: string }) =>
    a.date < b.date ? -1 : a.date > b.date ? 1 : a.label < b.label ? -1 : a.label > b.label ? 1 : 0
  const first = rows.find((row) => row.isDefault)
  const usual = rows.filter((row) => !row.isDefault && row.kind === 'usual').sort(byDate)
  const differing = rows.filter((row) => !row.isDefault && row.kind === 'differs').sort(byDate)
  const none = rows.filter((row) => !row.isDefault && row.kind === 'none').sort(byDate)

  //? one pressing of each other format with the usual tracklist stays in view: a vinyl is one tap away
  const formats = new Set([first?.format ?? ''])
  const formatShown = usual.filter((row) => {
    if (formats.has(row.format)) return false
    formats.add(row.format)
    return true
  })
  const folded = usual.filter((row) => !formatShown.includes(row) && row.id !== chosenId)
  const chosenFolded = usual.filter((row) => !formatShown.includes(row) && row.id === chosenId)

  const strip = ({ format: _format, date: _date, ...row }: PressingRow & { format: string; date: string }): PressingRow => row
  const shown = [...(first ? [first] : []), ...formatShown, ...chosenFolded, ...differing, ...none].map(strip)
  return { base, defaultId, chosenId, shown, more: folded.map(strip), diffs }
}

/** The line above the tracklist: what this pressing is against the usual one. `differs` draws it amber. */
export function summaryLine(view: PressingsView, releaseCount: number): { text: string; differs: boolean } {
  const row = [...view.shown, ...view.more].find((candidate) => candidate.id === view.chosenId)
  if (!row) return { text: '', differs: false }
  if (row.kind === 'none') return { text: 'MusicBrainz lists no tracks for this pressing', differs: false }
  if (!view.base) {
    return { text: releaseCount === 1 ? 'The only pressing MusicBrainz lists' : 'The only pressing with a tracklist on MusicBrainz', differs: false }
  }
  if (row.kind === 'usual') {
    return { text: row.isDefault ? `The usual tracklist, ${sharedBy(view.base)}` : 'Same tracklist as the usual one', differs: false }
  }
  const diff = view.diffs.get(row.id)
  if (!diff) return { text: '', differs: false }
  const clauses: string[] = []
  if (diff.added.length) clauses.push(`adds ${plural(diff.added.length, 'track')}`)
  if (diff.removed.length) clauses.push(`leaves out ${plural(diff.removed.length, 'track')}`)
  if (diff.renamed.length) clauses.push(`renames ${plural(diff.renamed.length, 'track')}`)
  if (diff.versions.length) clauses.push(`has another version of ${plural(diff.versions.length, 'track')}`)
  const said = clauses.length > 1 ? `${clauses.slice(0, -1).join(', ')} and ${clauses[clauses.length - 1]}` : clauses[0] ?? ''
  return { text: `This pressing ${said}`, differs: true }
}

/**
 * Whether any pressing of the album differs from the usual tracklist (2.0.0-player.19): the desktop's
 * tracklist then has its "Against the usual tracklist" column (DesktopRequestBonus.dc.html) - on
 * every pressing, the usual one too, so choosing another moves no column - and with every pressing
 * alike it has none (DesktopRequest.dc.html).
 */
export function anyPressingDiffers(view: Pick<PressingsView, 'shown' | 'more'> | null): boolean {
  return !!view && [...view.shown, ...view.more].some((row) => row.kind === 'differs')
}

export interface TrackMark {
  kind: 'bonus' | 'version' | 'renamed'
  chip: string
  /** the phone's line under the title: "Only on this pressing", "The usual version is 3:58" */
  note: string
  /** the same in the desktop table's words (2.0.0-player.19, DesktopRequestBonus.dc.html) - short
   *  enough to sit beside the chip in its 190px column: "only on this pressing", "usually 3:58" */
  brief: string
}

export interface TrackRow {
  key: string
  /** the disc heading to draw above this track, or null */
  heading: string | null
  /** its number on its own disc */
  number: string
  title: string
  /** m:ss, or '' when MusicBrainz has no length */
  length: string
  mark: TrackMark | null
}

/** "Disc 2 · Unreleased Tracks", or "Disc 2" for a disc without a title. */
export function discHeading(position: number, title: string | null | undefined): string {
  const named = (title ?? '').trim()
  return named ? `Disc ${position} · ${named}` : `Disc ${position}`
}

/**
 * The chosen pressing's tracklist, row by row, with its differences from the usual one marked
 * (`diff` null: nothing to mark). Running positions match the diff's.
 */
export function trackRows(release: PageRelease | null, diff: TracklistDiff | null): TrackRow[] {
  if (!release) return []
  const media = (release.media ?? []).filter((medium) => (medium.tracks ?? []).length)
  const headings = media.length > 1 || media.some((medium) => (medium.title ?? '').trim())
  const bonus = new Set(diff?.added.map((track) => track.position))
  const versions = new Map(diff?.versions.map((change) => [change.position, change]))
  const renamed = new Map(diff?.renamed.map((change) => [change.position, change]))

  const rows: TrackRow[] = []
  let position = 0
  media.forEach((medium, index) => {
    const disc = medium.position ?? index + 1
    ;(medium.tracks as MbTrack[]).forEach((track, onDisc) => {
      position++
      const ms = track.length ?? track.recording?.length
      const seconds = typeof ms === 'number' && Number.isFinite(ms) ? Math.round(ms / 1000) : null
      const version = versions.get(position)
      const rename = renamed.get(position)
      const mark: TrackMark | null = bonus.has(position) ? { kind: 'bonus', chip: 'Bonus', note: 'Only on this pressing', brief: 'only on this pressing' }
        : version ? { kind: 'version', chip: 'Other version', note: `The usual version is ${formatSeconds(version.from)}`, brief: `usually ${formatSeconds(version.from)}` }
        : rename ? { kind: 'renamed', chip: 'Renamed', note: `Usually “${rename.from}”`, brief: `usually “${rename.from}”` }
        : null
      rows.push({
        key: `${disc}:${onDisc}`,
        heading: headings && onDisc === 0 ? discHeading(disc, medium.title) : null,
        number: String(onDisc + 1),
        title: track.title || track.recording?.title || '',
        length: formatSeconds(seconds),
        mark,
      })
    })
  })
  return rows
}

/** What the chosen pressing leaves out of the usual tracklist, with the usual lengths. */
export function leftOut(diff: TracklistDiff | null): { title: string; length: string }[] {
  return (diff?.removed ?? []).map((track) => ({ title: track.title, length: formatSeconds(track.length) }))
}

/**
 * The header: title, artist, year and kind - from the group Search handed over when there is one,
 * else from the group the pressings carry (`release-group`, which /release_group asks MusicBrainz
 * for, so a reload or a cold link says "Album" too), else from the pressings themselves: the chosen
 * one's title and credit, and the earliest year any pressing came out (which is what MusicBrainz's
 * first-release-date is).
 */
export function pageHeader(
  releases: readonly PageRelease[],
  chosen: PageRelease | null,
  preview: ReleaseGroup | null,
): { title: string; artist: string; year: string; kind: string } {
  const years = releases.map(pressingYear).filter(Boolean).sort()
  const group = preview ?? releases.find((release) => release['release-group'])?.['release-group'] ?? null
  return {
    title: group?.title || chosen?.title || releases[0]?.title || '',
    artist: creditName(group?.['artist-credit']) || creditName(chosen?.['artist-credit']) || '',
    year: (group && groupYear(group)) || years[0] || '',
    kind: group ? groupKind(group) : '',
  }
}

/**
 * The meta line under the artist: "2008 · Album · not in your library". `held` is null until the
 * library has said what it holds - and then the line says neither, rather than "not in your
 * library" for an album that turns out to be there (the first /library/owned after a restart walks
 * the whole library).
 */
export function metaLine(header: { year: string; kind: string }, held: boolean | null): string {
  const holding = held === null ? '' : held ? 'in your library' : 'not in your library'
  return [header.year, header.kind, holding].filter(Boolean).join(' · ')
}

/**
 * The release group a Get on this page builds its download from (2.0.0-player.15, through
 * lib/releasePayload.ts) - the group Search handed over, else the one the pressings carry - so the
 * album is searched under its credit and filed under its current name and its own year, exactly as
 * the main page's Find on the same pressing would. Where MusicBrainz gave no credit for the group (a
 * cold link whose pressings carry a bare group), the chosen pressing's credit stands in; with no
 * group at all, its title and the earliest date any pressing came out (first-release-date's meaning).
 */
export function getGroup(
  id: string,
  preview: ReleaseGroup | null,
  releases: readonly PageRelease[],
  chosen: PageRelease | null,
): Pick<ReleaseGroup, 'id' | 'title' | 'first-release-date' | 'artist-credit'> {
  const group = preview ?? releases.find((release) => release['release-group'])?.['release-group'] ?? null
  const dates = releases.map((release) => release.date || release['release-events']?.[0]?.date || '').filter(Boolean).sort()
  const credit = group?.['artist-credit']?.length ? group['artist-credit'] : chosen?.['artist-credit']
  return {
    id: group?.id || id,
    title: group?.title || chosen?.title || releases[0]?.title || '',
    'first-release-date': group ? group['first-release-date'] ?? '' : dates[0] ?? '',
    ...(credit ? { 'artist-credit': credit } : {}),
  }
}

/** The Cover Art Archive's front for the pressing shown, then for the album as a whole. */
export function coverAddresses(releaseId: string | null, groupId: string, size = 500): string[] {
  const addresses: string[] = []
  if (releaseId) addresses.push(`https://coverartarchive.org/release/${encodeURIComponent(releaseId)}/front-${size}`)
  addresses.push(`https://coverartarchive.org/release-group/${encodeURIComponent(groupId)}/front-${size}`)
  return addresses
}
