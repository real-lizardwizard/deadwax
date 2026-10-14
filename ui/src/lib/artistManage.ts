/**
 * The artist page, as the main page had it (2.0.0-player.45) - pure, pinned by ui/test/artist.sim.cjs.
 *
 * The app's artist page (app/ArtistPage.tsx) gains what the main page's (components/ArtistDetails.tsx)
 * always showed: who MusicBrainz says they are in full - their other names, when they began and
 * ended, their genres, links and line-up - what the library holds of them, and, for an admin, the two
 * writers that page drove: their pictures (src/artist_art.py, the fifth) and moving their albums under
 * the name MusicBrainz uses now (src/artist_refile.py, the eighth). Both through the routes the main
 * page uses, every one of which takes the LIBRARY'S name for the artist - the album artist the scan
 * read, which is how the main page's tree groups albums.
 *
 * WHICH NAMES. The app's page is one per artist (Navidrome's, or MusicBrainz's by id), while the
 * library may file them under several names - Ye's page holds Donda, filed as "Kanye West", and BULLY,
 * filed as "Ye". `libraryNames` finds every name the library files this artist's albums under, from
 * /library/owned's folders: by their one MusicBrainz artist id when the page knows who they are (a
 * collaboration's ids never count - its folder is its own), and for a folder that carries no id, by
 * Navidrome's album of it or by the artist's name.
 *
 * Each name is one /library/artist answer (a summary: albums, tracks, size, years, the folder they
 * share or why there isn't one, the pictures on disk), and `libraryFacts` joins them into the page's
 * "In your library". Pictures go into ONE folder - the current name's when the library has it, else
 * the only name's (`imagesFolder`); albums under several names are moved first. "Now: <name>" and Move
 * albums to it show when a name the library files them under isn't MusicBrainz's name for them now
 * (`namesToMove`, the main page's own test: the names differ).
 */

import type { ArtistFacts, ArtistImageCandidate, ArtistImagesPreview, ArtistMatch, ArtistMember, ArtistSummary } from '../api/types'
import type { ArtistRefilePlan, ArtistRefileResults } from '../api/library'
import { mbidOf, everyOwned } from './artistPage'
import { formatSize } from './format'
import { foldName, type OwnedIndex } from './owned'

/** The line-up's first members shown: the rest under "N earlier members" (the main page's ten). */
export const MEMBERS_SHOWN = 10
/** The links shown: the rest under "N more links" (the main page showed these and no more). */
export const LINKS_SHOWN = 8

/** Who the page is about, as far as finding their folders goes. */
export interface ArtistWho {
  /** their MusicBrainz id, when the page knows it */
  mbid: string | null
  /** the name to match an untagged folder by: Navidrome's for them, else MusicBrainz's */
  name: string | null
  /** the releases of the albums Navidrome lists under them */
  releases: readonly string[]
}

/**
 * Every name the library files this artist's albums under (the scan's album artist, as the library
 * routes take it), in a steady order. A folder by several artists (a collaboration) is never one of
 * theirs; a folder by one artist is theirs when that is the page's artist - or, with no id known to
 * the page, when it goes by their name; a folder carrying no artist id when Navidrome lists its album
 * under them, or it goes by their name.
 */
export function libraryNames(index: OwnedIndex | null, who: ArtistWho): string[] {
  const mbid = mbidOf(who.mbid)
  const name = foldName(who.name)
  const releases = new Set(who.releases.map(mbidOf).filter((id): id is string => !!id))
  const names = new Set<string>()
  for (const album of everyOwned(index)) {
    const artist = album.artist ?? ''
    if (!artist.trim()) continue
    const ids = (album.albumartist_mbids ?? []).map(mbidOf).filter((id): id is string => !!id)
    if (ids.length > 1) continue
    const byName = !!name && foldName(artist) === name
    const byRelease = !!mbidOf(album.release_mbid) && releases.has(mbidOf(album.release_mbid)!)
    const theirs = mbid ? (ids.length === 1 ? ids[0] === mbid : byName || byRelease) : byName || byRelease
    if (theirs) names.add(artist)
  }
  return [...names].sort((a, b) => foldName(a).localeCompare(foldName(b)) || a.localeCompare(b))
}

/** The names that aren't MusicBrainz's name for them now: what Move albums to <name> moves. */
export function namesToMove(names: readonly string[], current: string | null | undefined): string[] {
  const now = (current ?? '').trim()
  if (!now) return []
  return names.filter((name) => name !== now)
}

/** "1991", "1991-2014" - '' for neither. */
export function yearsText(first: string | null | undefined, last: string | null | undefined): string {
  const from = (first ?? '').trim()
  const to = (last ?? '').trim()
  if (!from) return to
  return !to || to === from ? from : `${from}–${to}`
}

/** What a page's "In your library" says, from the summaries of every name they're filed under. */
export interface LibraryFacts {
  albums: number
  tracks: number
  /** "1.2 GB" - '' for nothing measured */
  size: string
  years: string
  /** the folders their albums share, one per name that has one */
  folders: string[]
  /** why there is no one folder - a name's own problem, or their albums under several names */
  problem: string | null
}

/** The library's summaries joined (`summaries`: one per name, in libraryNames' order). */
export function libraryFacts(summaries: readonly Pick<ArtistSummary, 'artist' | 'path' | 'folder_problem' | 'album_count' | 'track_count' | 'total_size' | 'first_year' | 'last_year'>[]): LibraryFacts | null {
  if (!summaries.length) return null
  const years = summaries.flatMap((one) => [one.first_year, one.last_year]).map((year) => (year ?? '').trim()).filter(Boolean).sort()
  const folders = summaries.map((one) => one.path).filter((path): path is string => !!path)
  const problems = summaries.map((one) => one.folder_problem).filter((problem): problem is string => !!problem)
  return {
    albums: summaries.reduce((sum, one) => sum + (one.album_count || 0), 0),
    tracks: summaries.reduce((sum, one) => sum + (one.track_count || 0), 0),
    size: formatSize(summaries.reduce((sum, one) => sum + (one.total_size || 0), 0)),
    years: yearsText(years[0], years[years.length - 1]),
    folders,
    problem: summaries.length > 1
      ? `Their albums are filed under ${summaries.length} names - ${listed(summaries.map((one) => one.artist))}`
      : problems[0] ?? null,
  }
}

/** "a and b", "a, b and c" */
export function listed(items: readonly string[]): string {
  if (items.length < 2) return items[0] ?? ''
  return `${items.slice(0, -1).join(', ')} and ${items[items.length - 1]}`
}

/** Where their pictures go: the name whose folder takes them, or why none does. */
export interface ImagesFolder {
  /** the library name the images routes are asked about - null: none can be */
  name: string | null
  /** why Artist images… can't be used (null: it can, or the folder isn't known yet) */
  reason: string | null
}

/**
 * The folder Artist images… writes into: the current name's when the library files them under it,
 * else the only name's. Under several names and none of them current, none - they're moved first;
 * a name whose albums share no folder says why (the summary's own words, as the main page's button).
 */
export function imagesFolder(
  names: readonly string[], current: string | null | undefined, summaries: ReadonlyMap<string, Pick<ArtistSummary, 'path' | 'folder_problem'> | null>,
): ImagesFolder {
  if (!names.length) return { name: null, reason: null }
  const now = (current ?? '').trim()
  const name = now && names.includes(now) ? now : names.length === 1 ? names[0]! : null
  if (!name) {
    return {
      name: null,
      reason: now
        ? `Their albums are filed under ${names.length} names - move them under ${now} first, so their pictures have one folder`
        : `Their albums are filed under ${names.length} names, so there's no one folder for their pictures`,
    }
  }
  const summary = summaries.get(name)
  if (summary === null) return { name, reason: "deadwax couldn't read their folder just now" }
  if (summary && !summary.path) return { name, reason: capital(summary.folder_problem ?? 'they have no folder of their own') }
  return { name, reason: null }
}

const capital = (text: string) => text.charAt(0).toUpperCase() + text.slice(1)

const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December']

/** A date as MusicBrainz writes one, in words: "1991", "June 1977", "8 June 1977" - anything else as given. */
export function factDate(value: string | null | undefined): string {
  const text = (value ?? '').trim()
  const match = /^(\d{4})(?:-(\d{2})(?:-(\d{2}))?)?$/.exec(text)
  if (!match) return text
  const [, year, month, day] = match
  const name = month ? MONTHS[Number(month) - 1] : undefined
  if (!name) return year!
  return day && Number(day) > 0 ? `${Number(day)} ${name} ${year}` : `${name} ${year}`
}

/** One row of the facts: a label and what it says. */
export interface FactRow {
  label: string
  value: string
}

/**
 * When they began and ended, in the words their kind takes: a person is Born and Died, a group (an
 * orchestra, a choir) Founded and Dissolved, anything else Began and Ended - each with its date, and
 * an end MusicBrainz knows of without a date said so. Nothing for what isn't known.
 */
export function lifeRows(facts: Pick<ArtistFacts, 'type' | 'began' | 'ended' | 'ended_on'> | null): FactRow[] {
  if (!facts) return []
  const [start, end] = facts.type === 'Person' ? ['Born', 'Died']
    : facts.type === 'Group' || facts.type === 'Orchestra' || facts.type === 'Choir' ? ['Founded', 'Dissolved']
    : ['Began', 'Ended']
  const rows: FactRow[] = []
  if (facts.began) rows.push({ label: start, value: factDate(facts.began) })
  if (facts.ended_on) rows.push({ label: end, value: factDate(facts.ended_on) })
  else if (facts.ended) rows.push({ label: end, value: 'yes, date not known' })
  return rows
}

/** Who they are, row by row - what the About card lists after "Now" (which the page draws itself). */
export function aboutRows(facts: ArtistFacts | null): FactRow[] {
  if (!facts) return []
  const rows: FactRow[] = []
  if (facts.type) rows.push({ label: 'Type', value: facts.type })
  const from = facts.begin_area || facts.area || facts.country
  if (from) rows.push({ label: 'From', value: from })
  rows.push(...lifeRows(facts))
  if (facts.aliases.length) rows.push({ label: 'Other names', value: facts.aliases.join(', ') })
  return rows
}

/** A member's years with the band: "1991–", "1991–1999", "?–1999". */
export function memberYears(member: Pick<ArtistMember, 'began' | 'ended' | 'current'>): string {
  const began = (member.began ?? '').slice(0, 4) || '?'
  if (member.current) return `${began}–`
  const ended = (member.ended ?? '').slice(0, 4)
  return `${began}–${ended}`
}

/** A member's roles, the first three, as MusicBrainz names them: "lead vocals, guitar". */
export function memberRoles(member: Pick<ArtistMember, 'roles'>): string {
  return member.roles.slice(0, 3).join(', ')
}

/** A list folded at `shown`: what is drawn, and how many wait behind "N more". */
export function folded<T>(items: readonly T[], shown: number, open: boolean): { items: T[]; more: number } {
  if (open || items.length <= shown) return { items: [...items], more: 0 }
  return { items: items.slice(0, shown), more: items.length - shown }
}

/* ===== Artist images… (the main page's ArtistImagePicker, its rules) ===== */

/** What "everything, best source first" would write - the picker's starting point. */
export function bestUrls(preview: Pick<ArtistImagesPreview, 'best'>): Record<string, string> {
  return Object.fromEntries(Object.entries(preview.best).map(([kind, candidate]) => [kind, candidate.url]))
}

/** A picture chosen for a slot - or, chosen already, taken back: that slot isn't written. */
export function toggleChoice(chosen: Readonly<Record<string, string>>, kind: string, url: string): Record<string, string> {
  if (chosen[kind] === url) return Object.fromEntries(Object.entries(chosen).filter(([key]) => key !== kind))
  return { ...chosen, [kind]: url }
}

/** The pictures found, by the slot their source says they are. */
export function byKind(candidates: readonly ArtistImageCandidate[]): Record<string, ArtistImageCandidate[]> {
  const grouped: Record<string, ArtistImageCandidate[]> = {}
  for (const candidate of candidates) (grouped[candidate.kind] ??= []).push(candidate)
  return grouped
}

/** A slot's line beside its name: the file already on disk, or that nothing was found for it. */
export function slotLine(existing: string | null | undefined, found: number): string {
  if (existing) return `${existing} on disk`
  return found ? '' : 'none found for this'
}

/** What the picker says about the sources it couldn't ask - the keys deadwax's settings hold. */
export function imageNotes(preview: Pick<ArtistImagesPreview, 'has_key' | 'sources'>): string[] {
  if (!preview.has_key) {
    return ['Banners, logos and backgrounds come from fanart.tv and TheAudioDB, and both need a key - in deadwax\'s '
      + 'settings, under Connections. Without either there is only what Wikimedia Commons has, which is usually a '
      + 'single photograph - though you can put that in any slot below.']
  }
  if (!preview.sources?.fanarttv) {
    return ['fanart.tv isn\'t set up. Its artwork is voted on by the people using it, so it is usually the better of '
      + 'the two - a key of your own goes in deadwax\'s settings, under Connections.']
  }
  return []
}

/** What a save says: the files written, else the first problem, else that nothing needed writing. */
export function savedLine(results: { written: readonly string[]; problems: readonly string[] }): string {
  if (results.written.length) return `Saved ${results.written.join(', ')}.`
  return results.problems[0] ?? 'Nothing needed writing.'
}

/** A MusicBrainz artist found by a search, in a line: the name they matched as, who they are. */
export function matchLine(match: Pick<ArtistMatch, 'name' | 'matched_as' | 'disambiguation' | 'type' | 'country'>): string {
  return [
    match.matched_as && match.matched_as !== match.name ? `as ${match.matched_as}` : '',
    match.disambiguation,
    [match.type, match.country].filter(Boolean).join(' · '),
  ].filter(Boolean).join(' · ')
}

/* ===== Move albums to … (the main page's ArtistRefileDialog, across every name) ===== */

/** One name's plan, as /library/artist/refile/preview answers it for that name. */
export interface NamedPlan {
  name: string
  plan: ArtistRefilePlan
}

/** Every name's plan as one: each move and refusal, the problems once each. */
export interface RefileView {
  currentName: string
  toFolder: string
  moves: ArtistRefilePlan['moves']
  refused: ArtistRefilePlan['refused']
  problems: string[]
  /** nothing to move under any name */
  empty: boolean
}

/**
 * Every name's plan as one. Each name's plan is the route's for that name alone, which can't see the
 * others': two names each holding a folder of one name (`Kanye/Graduation (2007)` and `Kanye
 * West/Graduation (2007)`) would both plan the move to `Ye/Graduation (2007)` - so the later is shown
 * staying, as its apply will find it (review, 2.0.0-player.45: the preview said "Move 2 albums").
 */
export function refileView(plans: readonly NamedPlan[]): RefileView | null {
  if (!plans.length) return null
  const first = plans[0]!.plan
  const taken = new Set<string>()
  const moves: ArtistRefilePlan['moves'] = []
  const refused: ArtistRefilePlan['refused'] = []
  for (const { plan } of plans) {
    for (const move of plan.moves) {
      if (taken.has(move.target_path)) {
        refused.push({ album: move.album, path: move.path, reason: `another album moves to '${move.target_path}'` })
        continue
      }
      taken.add(move.target_path)
      moves.push(move)
    }
    refused.push(...plan.refused)
  }
  return {
    currentName: first.current_name,
    toFolder: first.to_folder,
    moves,
    refused,
    problems: [...new Set(plans.flatMap(({ plan }) => plan.problems))],
    empty: !moves.length,
  }
}

/** Whether Move can be pressed: a plan with something to move and no problem. */
export function canMove(view: RefileView | null): boolean {
  return !!view && !view.empty && !view.problems.length && view.moves.length > 0
}

/** A move's second line: "2 tracks, 2 retagged". */
export function moveLine(move: Pick<ArtistRefilePlan['moves'][number], 'files' | 'retag'>): string {
  return `${move.files} track${move.files === 1 ? '' : 's'}${move.retag.length ? `, ${move.retag.length} retagged` : ''}`
}

/** The button: "Move 2 albums". */
export function moveButton(moves: number): string {
  return `Move ${moves} album${moves === 1 ? '' : 's'}`
}

/** One name's apply, as the route answered it: the plan it recomputed, and what it did. */
export interface AppliedName {
  name: string
  plan: ArtistRefilePlan
  results: ArtistRefileResults
}

/**
 * What the applies said beyond what moved and failed (review, 2.0.0-player.45). `stayed`: each album
 * the preview showed moving that the apply's own plan kept where it is - another name's album got to
 * its folder first, a folder came since - said, never dropped. `emptied`: the names every album of
 * which moved, nothing refused or failed, before or at the apply: the names the library no longer
 * files them under - what the page follows (a page of a name still in use stays where it is).
 */
export function refileAfter(previewed: readonly NamedPlan[], applied: readonly AppliedName[], view: RefileView): { stayed: string[]; emptied: string[] } {
  const moving = new Set(view.moves.map((move) => move.path))
  const stayed = applied.flatMap(({ plan }) => (plan.refused ?? []).filter((one) => moving.has(one.path)).map((one) => `${one.album}: stays - ${one.reason}`))
  const emptied = previewed.filter(({ name, plan }) => {
    const done = applied.find((one) => one.name === name)
    if (!done || plan.refused.length || !plan.moves.length) return false
    if (plan.moves.some((move) => !moving.has(move.path))) return false
    return !(done.plan.refused ?? []).length && !done.results.failed.length && done.results.moved.length === plan.moves.length
  }).map(({ name }) => name)
  return { stayed, emptied }
}

/** What became of a move, every name's results joined. */
export function refileOutcome(results: readonly ArtistRefileResults[], toFolder: string): { moved: number; text: string; failures: string[] } {
  const moved = results.reduce((sum, one) => sum + one.moved.length, 0)
  const failures = results.flatMap((one) => one.failed.map((failed) => `${failed.album}: ${failed.reason}`))
  const pictures = results.flatMap((one) => one.pictures_moved)
  const removed = results.flatMap((one) => one.removed_folders)
  const parts = [
    moved ? `Moved ${moved} album${moved === 1 ? '' : 's'} into ${toFolder}/.` : 'Nothing was moved.',
    pictures.length ? `Their pictures came too: ${pictures.join(', ')}.` : '',
    removed.length ? `${listed(removed.map((folder) => `${folder}/`))} ${removed.length === 1 ? 'was' : 'were'} left empty and removed.` : '',
  ]
  return { moved, text: parts.filter(Boolean).join(' '), failures }
}
