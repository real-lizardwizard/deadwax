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
 *    unlike the main page's "N lengths" chip did, never marks one). Its TITLES are chooseBase's; its
 *    LENGTHS are the default pressing's (one of those holding it), so the pressing the page opens
 *    on is always the usual tracklist itself, whatever order MusicBrainz listed the pressings in.
 *    chooseBase lends the lengths of whichever such pressing came FIRST, and with a single mix
 *    listed first the default read "another version of Borderline" against itself (review).
 *  - THE DROPDOWN shows the default, one pressing of each other format that has the usual tracklist
 *    (so a vinyl is one tap away), every pressing that differs, then "N more pressings with the
 *    usual tracklist", which expands. The pressing chosen is always in view - and since
 *    2.0.0-player.41 so is every pressing you hold (`held`, by release id from /library/owned), each
 *    marked "In your library": v0.9.1's ask, "a way to see which editions are already in my library
 *    when I'm searching for new ones".
 *  - EACH PRESSING'S FACTS (2.0.0-player.50): what else tells one CD from another - its status, full
 *    date, labels, catalogue number and barcode, as MusicBrainz gives them (pressingFacts) - in the
 *    dropdown's rows and the page's line for the one chosen; and an album of more than
 *    PRESSING_FILTER_MIN pressings gets a text filter over them (filterPressings).
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
  /** '' when MusicBrainz says it has none, null when nobody has entered one */
  barcode?: string | null
  'artist-credit'?: ArtistCredit[]
  'label-info'?: readonly { label?: { name?: string } | null; 'catalog-number'?: string | null }[]
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
  /** what else tells it apart, as MusicBrainz gives it (2.0.0-player.50): "Official · 2008-04-28 ·
   *  Cat. no. 1764013 · Barcode 602517640132" - pressingFacts */
  facts: string
  /** how it compares with the usual tracklist, in a few words */
  note: string
  kind: PressingKind
  /** the one the page opens on */
  isDefault: boolean
  /** a pressing your library holds (2.0.0-player.41): marked "In your library", never folded away */
  held: boolean
  /** (2.0.0-player.52) held by the store but not yours - logins on, a library of your own: marked "In the store" */
  inStore?: boolean
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

//? MusicBrainz's word for a release with no catalogue number: there is nothing to tell it apart by
const NO_CATALOGUE = '[none]'

/**
 * What else tells a pressing apart (2.0.0-player.50), as MusicBrainz gives it - the facts the main page's
 * releases grid had columns for, which pressingLabel leaves out: its status ("Official", "Promotion",
 * "Bootleg"), its full date when it is more than the year the label already says, its labels when the
 * label line shows a disambiguation in their place (and any after the first one it shows), its catalogue
 * numbers, its barcode, and "Worldwide" for the release the label line leaves its country off. Each said
 * once, in that order: "Official · 2008-04-28 · Cat. no. 1764013 · Barcode 602517640132". Nothing made up
 * - '' when MusicBrainz says nothing more - and nothing the label line already says.
 */
export function pressingFacts(release: PageRelease): string {
  const parts: string[] = []
  const status = (release.status ?? '').trim()
  if (status) parts.push(status)
  const date = (release.date || release['release-events']?.[0]?.date || '').trim()
  if (date.length > 4) parts.push(date)
  const named = !release.disambiguation?.trim()
  const shown = named ? release['label-info']?.find((info) => info?.label?.name)?.label?.name?.trim() ?? null : null
  const labels = [...new Set((release['label-info'] ?? []).map((info) => info?.label?.name?.trim() ?? '').filter(Boolean))]
    .filter((name) => name !== shown)
  if (labels.length) parts.push(labels.join(' / '))
  const numbers = [...new Set((release['label-info'] ?? []).map((info) => info?.['catalog-number']?.trim() ?? ''))]
    .filter((number) => number && number !== NO_CATALOGUE)
  if (numbers.length) parts.push(`Cat. no. ${numbers.join(' / ')}`)
  const barcode = (release.barcode ?? '').trim()
  if (barcode) parts.push(`Barcode ${barcode}`)
  if (release.country === 'XW') parts.push('Worldwide')
  return parts.join(' · ')
}

/** An album with more pressings than this gets a text filter in its dropdown (2.0.0-player.50). */
export const PRESSING_FILTER_MIN = 30

/** Text as the dropdown's filter compares it: accents and case folded, anything but letters and digits a space. */
function foldText(text: string): string {
  return text.normalize('NFKD').replace(/\p{M}/gu, '').toLowerCase().replace(/[^\p{L}\p{N}]+/gu, ' ').trim()
}

/**
 * The dropdown's filter (2.0.0-player.50), for an album of more than PRESSING_FILTER_MIN pressings: the
 * pressings whose label, facts or note hold every word typed - "jp cd", "uicb 1004", "promotion" - in the
 * dropdown's own order, folded ones included; every pressing for nothing typed. A word is found in the
 * text as folded, or with its gaps closed up, so a catalogue number typed without its dash or space -
 * "uicb1004" - still finds UICB-1004 (review).
 */
export function filterPressings(rows: readonly PressingRow[], typed: string): PressingRow[] {
  const words = foldText(typed).split(' ').filter(Boolean)
  if (!words.length) return [...rows]
  return rows.filter((row) => {
    const text = foldText([row.label, row.facts, row.note, row.held ? (row.inStore ? 'in the collection' : 'in your library') : ''].join(' '))
    const closed = text.replace(/ /g, '')
    return words.every((word) => text.includes(word) || closed.includes(word))
  })
}

/**
 * What the dropdown's filter says as it narrows the list (review): how many pressings match the words
 * typed - "4 pressings match." - or that none does, as the list's own line says it; '' while nothing is
 * typed. Said by a live region always in the list while it has a filter, since VoiceOver reads a region
 * only once it is already there.
 */
export function pressingFilterWords(matching: number, typed: string): string {
  const words = typed.trim()
  if (!words) return ''
  if (!matching) return `No pressing matches “${words}”.`
  return `${matching} ${matching === 1 ? 'pressing matches' : 'pressings match'}.`
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
 * Which pressing of a group is shown: the one `asked` for (the address's) when the group has it, else the
 * default - the representative pressing. pressingsView's `chosenId`, also asked before the view is made by the
 * album you don't have, which lays what the line under Get says of that pressing over the library's answer
 * before the view's marks are drawn from it (lib/whose.ts withStoreLine).
 */
export function chosenPressingId(
  releases: readonly PageRelease[],
  asked: string | null = null,
  defaultId: string | null = representativeRelease(releases)?.id ?? releases[0]?.id ?? null,
): string | null {
  return asked && releases.some((release) => release.id === asked) ? asked : defaultId
}

/**
 * Every pressing of a group as the dropdown lists them, and which is shown - `asked` is the one the
 * address names, when the group has it; `held`, the release ids your library holds (lowercase), each
 * marked and kept out of the fold. `yours` (2.0.0-player.52): with logins on and a library of your own, the
 * release ids of those that are YOURS - a held one not among them is marked "In the store"; null (logins off)
 * when the store is your library.
 */
export function pressingsView(
  releases: readonly PageRelease[],
  asked: string | null = null,
  held: ReadonlySet<string> = new Set(),
  yours: ReadonlySet<string> | null = null,
): PressingsView {
  const base = chooseBase(releases)
  const usualKey = base ? tracklistKey(base.tracks) : null
  const fallback = representativeRelease(releases)
  const defaultId = fallback?.id ?? releases[0]?.id ?? null
  const chosenId = chosenPressingId(releases, asked, defaultId)
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
    const holds = held.has(release.id.toLowerCase())
    return { id: release.id, label: pressingLabel(release), facts: pressingFacts(release), note: pressingNote(kind, diff, isDefault, base), kind, isDefault,
      held: holds, ...(holds && yours && !yours.has(release.id.toLowerCase()) ? { inStore: true } : {}),
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
  //? the chosen pressing and every pressing you hold stay out of the fold, in the list's own order
  const keptOut = (row: { id: string; held: boolean }) => row.id === chosenId || row.held
  const folded = usual.filter((row) => !formatShown.includes(row) && !keptOut(row))
  const chosenFolded = usual.filter((row) => !formatShown.includes(row) && keptOut(row))

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
  /** the song the album was opened from (2.0.0-player.53, Search's songs): marked, and scrolled to */
  song: boolean
}

/** "Disc 2 · Unreleased Tracks", or "Disc 2" for a disc without a title. */
export function discHeading(position: number, title: string | null | undefined): string {
  const named = (title ?? '').trim()
  return named ? `Disc ${position} · ${named}` : `Disc ${position}`
}

/**
 * The chosen pressing's tracklist, row by row, with its differences from the usual one marked
 * (`diff` null: nothing to mark). Running positions match the diff's. `isSong` (2.0.0-player.53): which
 * tracks are the song the album was opened from (lib/songs.ts songMatcher) - none without one.
 */
export function trackRows(release: PageRelease | null, diff: TracklistDiff | null, isSong: ((track: MbTrack) => boolean) | null = null): TrackRow[] {
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
        song: !!isSong && isSong(track),
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
 * the whole library). `place` (2.0.0-player.52): where a held album is - "in the store" when, with a
 * library of your own, none of what the store holds of it is yours, and "another pressing in your library"
 * when one is but not the pressing on screen, which the store holds (lib/whose.ts groupPagePlace): never
 * "in your library" over a store line saying "In the store, not in your library".
 */
export function metaLine(header: { year: string; kind: string }, held: boolean | null, place = 'in your library'): string {
  const holding = held === null ? '' : held ? place : 'not in your library'
  return [header.year, header.kind, holding].filter(Boolean).join(' · ')
}

/**
 * What the meta line says of the library (2.0.0-player.50): 'held' by an id - the group's or a
 * pressing's; 'maybe' when nothing is held by id but a folder with NO MusicBrainz ids has the album's
 * name and an artist's it could be filed under (lib/owned.ts's name match) - which can't say it is this
 * album, so it is said as a maybe, dashed as the main page's card said it; 'not'; or null until the
 * library has answered.
 */
export function holdingOf(holding: { held: readonly unknown[]; guessed: readonly unknown[] } | null): 'held' | 'maybe' | 'not' | null {
  if (!holding) return null
  return holding.held.length ? 'held' : holding.guessed.length ? 'maybe' : 'not'
}

/**
 * The release group a Get on this page builds its download from (2.0.0-player.15, through
 * lib/releasePayload.ts) - the group Search handed over, else the one the pressings carry - so the
 * album is searched under its credit and filed under its current name and its own year, exactly as
 * the main page's Find on the same pressing did. Where MusicBrainz gave no credit for the group (a
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

/** The album's page on musicbrainz.org (2.0.0-player.50) - the release group; a pressing's is
 *  lib/albumProperties.ts releaseUrl. Both open beside the app. */
export const releaseGroupUrl = (group: string): string => `https://musicbrainz.org/release-group/${encodeURIComponent(group)}`

/** The Cover Art Archive's front for the pressing shown, then for the album as a whole. */
export function coverAddresses(releaseId: string | null, groupId: string, size = 500): string[] {
  const addresses: string[] = []
  if (releaseId) addresses.push(`https://coverartarchive.org/release/${encodeURIComponent(releaseId)}/front-${size}`)
  addresses.push(`https://coverartarchive.org/release-group/${encodeURIComponent(groupId)}/front-${size}`)
  return addresses
}
