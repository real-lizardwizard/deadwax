/**
 * Needs a look (2.0.0-player.25): the review queue in the app, on a desktop - pure, pinned by
 * ui/test/needslook.sim.cjs. The page is app/NeedsALook.tsx; the editors are the Edit panel's
 * (app/EditPanel.tsx), opened on a FOLDER. What is here is the main page's review queue
 * (its LibraryView.tsx's startReview, step, leaveQueue, retired with it in 2.0.0-player.66), its rules
 * carried over exactly:
 *
 *  - THE LIST is lib/metadataQueue.ts's queueAlbums(albums, facet) - the SAME function, so the same
 *    albums in the same order as the main page had them: new imports first, worst first, then alphabetical.
 *    "Needs a look" is an outstanding issue OR a new import (an album deadwax filed that nobody has
 *    looked at), never only one of them - the badge and the queue never count different things.
 *    The badge's count (GET /library/queue/summary) is that same list's length over the saved scan
 *    (`summaryTotal` is the page's side of it).
 *  - THE FACETS: All, Newly added (only when there is one), then one per kind of issue that has an
 *    album, with counts (`facets`) - each narrowing the list (`facetAlbums`), and a facet that has
 *    emptied falls back to All (`facetShown`). Last, Ignored (2.0.0-player.66, only when there is one):
 *    the albums whose every issue was accepted as it is - out of the queue, and with no other way back
 *    to the Edit panel for a folder Navidrome doesn't list. A view, not a count: All and the badge
 *    count outstanding issues and new imports only (`isIgnoredOnly`).
 *  - THE SESSION, started by clicking a row: the list as shown THEN, fixed - its paths, in that
 *    order, the clicked row current (`startSession`). Nothing moves under the pointer while it lasts:
 *    an album fixed, ignored or deleted stays in its row, saying which (`rowChanged`, `markFor`); a
 *    re-filed one is followed by its path. Stepping away from an album - Next, Previous, another row,
 *    the panel closing - marks the one left reviewed (that is what clears a new import), never one
 *    deleted (`stepTarget`'s `leaving`). An album gone when stepped to ends the session, as the main
 *    page's leaveQueue does. When it ends (the panel closes, the facet changes, the page is left) the
 *    list is worked out again from a fresh scan.
 */

import type { LibraryAlbum, MetadataIssueType, NavidromeCheck } from '../api/types'
import { isNewImport, issueLabel, outstandingIssues, queueAlbums } from './metadataQueue'

/** The facet for new imports - not an issue code (the scan's codes are snake_case words, never this). */
export const NEW_FACET = 'new'

/** The facet for albums whose issues were all accepted as they are (2.0.0-player.66) - not an issue code either. */
export const IGNORED_FACET = 'ignored'

/** The Ignored chip's title. */
const IGNORED_HINT = 'Albums whose issues you accepted as they are'

/**
 * An album out of the queue because every issue found on it was accepted ("It's fine as it is"): one
 * found issue at least is ignored, and none is outstanding (2.0.0-player.66). What the Ignored facet
 * lists - the one way back to such an album's Edit panel, where Un-ignore is, when Navidrome doesn't
 * list it (no album page to open it from).
 */
export function isIgnoredOnly(album: LibraryAlbum): boolean {
  return album.issues.some((code) => album.ignored_issues.includes(code)) && !outstandingIssues(album).length
}

/** A facet chip: what it narrows to (null: All), its words and how many albums it has. */
export interface Facet {
  id: string | null
  label: string
  count: number
  /** the issue's hint, for a chip's title */
  hint?: string
}

/** How many albums the page's All lists - what the badge counts over the same scan. */
export function summaryTotal(albums: readonly LibraryAlbum[]): number {
  return queueAlbums(albums, null).length
}

/**
 * The facet chips: All N; Newly added N, only when there is one; then one per kind of issue that has
 * an album outstanding, the most albums first (then by label, so the order holds still between scans);
 * last, Ignored N, only when there is one (2.0.0-player.66) - never counted in All.
 */
export function facets(albums: readonly LibraryAlbum[], issueTypes: Record<string, MetadataIssueType>): Facet[] {
  const waiting = queueAlbums(albums, null)
  const fresh = waiting.filter(isNewImport).length
  const counts = new Map<string, number>()
  for (const album of waiting) {
    for (const code of outstandingIssues(album)) counts.set(code, (counts.get(code) ?? 0) + 1)
  }
  const issues = [...counts.entries()]
    .map(([code, count]) => ({
      id: code,
      label: issueLabel(code, issueTypes),
      count,
      ...(issueTypes[code]?.hint ? { hint: issueTypes[code]!.hint } : {}),
    }))
    .sort((a, b) => b.count - a.count || a.label.localeCompare(b.label))
  const ignored = albums.filter(isIgnoredOnly).length
  return [
    { id: null, label: 'All', count: waiting.length },
    ...(fresh ? [{ id: NEW_FACET, label: 'Newly added', count: fresh }] : []),
    ...issues,
    ...(ignored ? [{ id: IGNORED_FACET, label: 'Ignored', count: ignored, hint: IGNORED_HINT }] : []),
  ]
}

/** The albums a facet lists, in queueAlbums' order: the queue narrowed to one kind of issue, or to
 *  the new imports (which queueAlbums puts first anyway) - or the albums whose issues were all
 *  accepted, alphabetical (artist, then album), as queueAlbums orders albums of one severity. */
export function facetAlbums(albums: readonly LibraryAlbum[], facet: string | null): LibraryAlbum[] {
  if (facet === NEW_FACET) return queueAlbums(albums, null).filter(isNewImport)
  if (facet === IGNORED_FACET) {
    return albums.filter(isIgnoredOnly).sort((a, b) => a.artist.localeCompare(b.artist) || a.album.localeCompare(b.album))
  }
  return queueAlbums(albums, facet)
}

/** The facet to show: the one asked for while it has albums, else All - a facet that has emptied
 *  (its last album fixed) falls back, rather than leaving a page that lists nothing under a chip
 *  that isn't drawn. */
export function facetShown(chips: readonly Facet[], facet: string | null): string | null {
  if (facet === null) return null
  return chips.some((chip) => chip.id === facet && chip.count > 0) ? facet : null
}

/** What became of an album during a session, said in its row. */
export type RowMark = 'fixed' | 'ignored' | 'deleted'

export const MARK_WORDS: Readonly<Record<RowMark, string>> = {
  fixed: 'Fixed',
  ignored: 'Ignored',
  deleted: 'Deleted',
}

export interface SessionRow {
  /** where the album lives now: followed when a write re-files it */
  path: string
  /** the album as last known: as listed, or as the panel's last write left it */
  album: LibraryAlbum
  /** the album as it was listed when the session began - what a mark is judged against */
  listed: LibraryAlbum
  mark: RowMark | null
  /** a write has told the page about it since the session began */
  heard: boolean
}

export interface LookSession {
  rows: SessionRow[]
  index: number
  /** the facet the list was narrowed by */
  facet: string | null
}

/** A session from the list as shown, with the row at `path` current - null when it isn't listed. */
export function startSession(list: readonly LibraryAlbum[], path: string, facet: string | null): LookSession | null {
  const index = list.findIndex((album) => album.path === path)
  if (index < 0) return null
  return {
    rows: list.map((album) => ({ path: album.path, album, listed: album, mark: null, heard: false })),
    index,
    facet,
  }
}

/**
 * What a row says once the album has changed: judged against what put it in the list. Fixed - every
 * issue it had is gone, none of them ignored; Ignored - gone, and some of them accepted as they are.
 * Nothing for an album that still has something outstanding (an un-ignore puts it back), nor for a
 * clean new import, which had nothing to fix.
 */
export function markFor(listed: LibraryAlbum, after: LibraryAlbum): RowMark | null {
  const was = outstandingIssues(listed)
  if (!was.length || outstandingIssues(after).length) return null
  return was.some((code) => after.ignored_issues.includes(code)) ? 'ignored' : 'fixed'
}

/** What the Edit panel says became of an album it was opened on from this page. */
export interface FolderChange {
  /** the album's path before the write */
  from: string
  /** the album as the panel's reload has it - null when it couldn't be found, or was deleted */
  album: LibraryAlbum | null
  deleted: boolean
}

/**
 * The session after a write to one of its albums: the row found by the path it had, followed to the
 * path it has now, its album and its mark brought up to date (the current row when it has that path,
 * else the first that does). Its place never changes.
 */
export function rowChanged(session: LookSession, change: FolderChange): LookSession {
  //? the current row first: every write comes from its panel, and after a disc folder merges into
  //? another row's folder two rows share a path (2.0.0-player.25 review)
  const at = session.rows[session.index]?.path === change.from
    ? session.index
    : session.rows.findIndex((row) => row.path === change.from)
  if (at < 0) return session
  const row = session.rows[at]!
  const next: SessionRow = change.deleted
    ? { ...row, mark: 'deleted', heard: true }
    : change.album
      ? { ...row, path: change.album.path, album: change.album, mark: markFor(row.listed, change.album), heard: true }
      : row
  if (next === row) return session
  const rows = [...session.rows]
  rows[at] = next
  return { ...session, rows }
}

/** What going to row `index` comes to. */
export type StepTarget =
  /** nothing: the row it is on, or past either end */
  | { kind: 'stay' }
  /** the session ends: the album stepped to has gone (deleted outside, or here) */
  | { kind: 'end'; leaving: string | null }
  | { kind: 'step'; session: LookSession; leaving: string | null }

/**
 * Going from the current row to row `index`: `leaving` is the album to mark reviewed - the one left,
 * unless it was deleted (marking it would write a row for a folder that isn't there). `present` says
 * whether a path is in the page's own scan; a row a write has told the page about is taken as there
 * whatever that scan says (it may predate a rename), and a deleted one never is.
 */
export function stepTarget(session: LookSession, index: number, present: (path: string) => boolean): StepTarget {
  if (index === session.index || index < 0 || index >= session.rows.length) return { kind: 'stay' }
  const here = session.rows[session.index]
  const leaving = here && here.mark !== 'deleted' ? here.path : null
  const there = session.rows[index]!
  if (there.mark === 'deleted' || (!there.heard && !present(there.path))) return { kind: 'end', leaving }
  return { kind: 'step', session: { ...session, index }, leaving }
}

/** The album to mark reviewed as a session ends (the panel closing is stepping away too). */
export function leavingAtEnd(session: LookSession): string | null {
  const here = session.rows[session.index]
  return here && here.mark !== 'deleted' ? here.path : null
}

/** The words above the list: what the page is - Navidrome not listing an album among them (2.0.0-player.46). */
export const NEEDS_LOOK_LINE =
  "Albums whose tags, folder or cover want attention or that Navidrome doesn't list, and albums deadwax filed that "
  + "you haven't looked at yet."

/** Said when ignores can't be saved (2.0.0-player.42) - the main page's warning, in the app's words. */
export const IGNORES_UNSAVED = "Ignores can't be saved: deadwax couldn't open its job store (DB_PATH), so an album you "
  + "accept with \u201cIt's fine as it is\u201d will come back."

/**
 * Whether to warn that ignores can't be saved (2.0.0-player.42), as the main page's queue warned: the
 * library's own answer says review tracking is off (`review_tracking_enabled`, once a read has landed),
 * or the count's route does (`tracking_enabled` - null until it has answered). Either one is enough:
 * both are deadwax saying it has no job store, and an "It's fine as it is" that silently comes back
 * is the thing to warn of.
 */
export function ignoresUnsaved(library: { loaded: boolean; reviewTracking: boolean }, summaryTracking: boolean | null): boolean {
  return (library.loaded && !library.reviewTracking) || summaryTracking === false
}

/** Said when Navidrome isn't set up (2.0.0-player.46): nothing is checked against it. */
export const NAVIDROME_UNSET = "Navidrome isn't set up, so no album is checked against what it lists - set it up in "
  + "deadwax's settings (Connections)."

/** Said when Navidrome was scanning as it was last asked - past tense, as it stays true once the scan
 *  has ended: until a read asks again, only the albums found missing before are marked. */
export const NAVIDROME_SCANNING = 'Navidrome was scanning when last asked, so only albums found missing before are '
  + 'marked \u201cNot in Navidrome\u201d.'

/** Said when a read of the disk landed before Navidrome's first answer. */
export const NAVIDROME_WAITING = "Navidrome hasn't answered yet, so no album is checked against it until the library "
  + 'is read again.'

/** Said when Navidrome couldn't be asked: why, as deadwax said it. */
export const navidromeFailed = (problem: string | null): string =>
  `Couldn't ask Navidrome which albums it has: ${problem || 'no reason given'}`

/**
 * What the page says ONCE about the albums' check against Navidrome (2.0.0-player.46) - "Not in
 * Navidrome" is raised only once Navidrome has answered, and Navidrome unset or failing raises
 * nothing, so the page says why there may be none. Null when there is nothing to say (checked, or no
 * answer at all). Said in the page's status line - always there, a row tall, one line of words - so
 * its coming and going moves no row, not even mid-session (2.0.0-player.46 review).
 */
export function navidromeNote(check: NavidromeCheck | null): string | null {
  if (check?.state === 'unset') return NAVIDROME_UNSET
  if (check?.state === 'failed') return navidromeFailed(check.problem)
  if (check?.state === 'scanning') return NAVIDROME_SCANNING
  if (check?.state === 'checking') return NAVIDROME_WAITING
  return null
}

/** What VoiceOver hears for "Needs a look" with its count: "Needs a look, 3 albums". */
export function needsLookLabel(label: string, count: number | null): string {
  return count && count > 0 ? `${label}, ${count} album${count === 1 ? '' : 's'}` : label
}
