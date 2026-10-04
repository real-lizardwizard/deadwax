/**
 * Editing an album from the app's desktop frame (2.0.0-player.21) - pure, pinned by
 * ui/test/routes.sim.cjs. The panel itself is app/EditPanel.tsx; the editors in it are the main
 * page's own (MetadataEditor, TrackTagEditor, the Get buttons, DeleteAlbumDialog), reused as they
 * are, so what is here is only what joins them to an album page.
 *
 * WHICH FOLDER. An album page knows the album by Navidrome's id; every editor works on a folder,
 * by its path under LIBRARY_PATH. The id bridge (GET /deadwax/store/album) answers that for an album
 * Navidrome knows by its MusicBrainz release: the store's live folders of it (`present`). Two ways
 * it can't, and what the panel does then (`editFolders`):
 *
 *  - The store has no row yet (an album copied in by another program, not indexed until a scan) -
 *    or the bridge didn't answer: the library's own scan, by the release id Navidrome reads from
 *    the files. Never by name: a tagged album is known by its id, and a name finds its other copies.
 *  - Navidrome knows the album by NO release - a stranger's rip, the very album the release editor
 *    exists to identify: the scan's folders that carry no release id either, by the album's name and
 *    its artist (folded as the search's held marks fold them), and its track count when that still
 *    leaves several. One is the folder; several the user chooses from (`needsChoice`) - a guess
 *    there could hand the release editor the wrong copy to rewrite.
 *
 * AFTER A WRITE (`EDIT_SETTLE_MS`, `FOLLOW_LOOKS_MS`, `followRelease`, `followsTo`): the page and
 * the library are asked again at once and once more after Navidrome has had time to scan. And an
 * apply that changed the album's RELEASE gives it a new id in Navidrome (its album id is made from
 * the release id when there is one), so the album's new id is looked for, by the new release, until
 * Navidrome has it - and the page then shows the album as it is now rather than one Navidrome no
 * longer has. A write that kept the release (tags, a rename, art, lyrics) keeps the id: nothing to
 * look for. App remembers each move (`noteMove`), so a page of the old id that comes back on top -
 * back to it, forward to it, another tab showing it - becomes the new one's too (`movedTo`).
 *
 * WHAT THE PANEL SAYS (`editStatus`) while it has no album to edit, and `deletesAll`: whether a
 * delete leaves Navidrome's album with nothing, so the page goes back from it.
 */

import { foldName } from './owned'

/** What the panel reads of the id bridge's answer (api/types.ts StoreAlbumResponse). */
export interface BridgeFolders {
  release_mbid: string | null
  present: readonly { path: string }[]
}

/** What the panel reads of an album in the library's scan (api/types.ts LibraryAlbum). */
export interface ScanAlbum {
  path: string
  album: string
  artist: string
  release_mbid: string
  track_count: number
}

/** The panel's tabs, as DesktopManage.dc.html draws them: underline tabs, in this order. */
export type EditTab = 'release' | 'tags' | 'artwork' | 'lyrics' | 'delete'

export const EDIT_TABS: readonly { id: EditTab; label: string }[] = [
  { id: 'release', label: 'Release' },
  { id: 'tags', label: 'Tags' },
  { id: 'artwork', label: 'Artwork' },
  { id: 'lyrics', label: 'Lyrics' },
  { id: 'delete', label: 'Delete' },
]

/** The tab an arrow key moves to from `tab`: the next or the one before, round the ends. */
export function tabAfter(tab: EditTab, step: number): EditTab {
  const at = EDIT_TABS.findIndex((entry) => entry.id === tab)
  const next = (((at + step) % EDIT_TABS.length) + EDIT_TABS.length) % EDIT_TABS.length
  return EDIT_TABS[next]!.id
}

/** Navidrome's album, as the album page had it when Edit was pressed - what finds its folder when
 *  the store can't. */
export interface EditAlbum {
  id: string
  name: string
  artist?: string
  songCount?: number
  musicBrainzId?: string
}

/** The fields of a Navidrome album answer the panel keeps (no songs: nothing here needs them). */
export function editAlbum(album: {
  id: string
  name: string
  artist?: string | undefined
  songCount?: number | undefined
  musicBrainzId?: string | undefined
}): EditAlbum {
  return {
    id: album.id,
    name: album.name,
    ...(album.artist ? { artist: album.artist } : {}),
    ...(typeof album.songCount === 'number' ? { songCount: album.songCount } : {}),
    ...(album.musicBrainzId?.trim() ? { musicBrainzId: album.musicBrainzId.trim() } : {}),
  }
}

/** Where the folders came from: the store's rows of the release, the scan by the release id, the
 *  scan by name (no release anywhere), the folder itself (an album opened from Needs a look, by its
 *  path - 2.0.0-player.25), or nowhere. */
export type FoldersFrom = 'store' | 'release' | 'name' | 'folder' | 'none'

export interface EditFolders {
  paths: string[]
  from: FoldersFrom
}

const NOWHERE: EditFolders = { paths: [], from: 'none' }

/**
 * The folders an album page's album is, for the editors: the bridge's answer (null when it didn't
 * answer), the library's scan, and Navidrome's album. See the module's note.
 */
export function editFolders(answer: BridgeFolders | null, albums: readonly ScanAlbum[], album: EditAlbum): EditFolders {
  const present = [...new Set((answer?.present ?? []).map((row) => row.path).filter(Boolean))]
  if (present.length) return { paths: present, from: 'store' }

  const release = (answer?.release_mbid ?? album.musicBrainzId ?? '').trim().toLowerCase()
  if (release) {
    const tagged = albums.filter((scanned) => (scanned.release_mbid ?? '').trim().toLowerCase() === release)
    return tagged.length ? { paths: tagged.map((scanned) => scanned.path), from: 'release' } : NOWHERE
  }

  const name = foldName(album.name)
  const artist = foldName(album.artist)
  if (!name) return NOWHERE
  let named = albums.filter((scanned) =>
    !(scanned.release_mbid ?? '').trim() && foldName(scanned.album) === name && (!artist || foldName(scanned.artist) === artist))
  if (named.length > 1 && typeof album.songCount === 'number') {
    const same = named.filter((scanned) => scanned.track_count === album.songCount)
    if (same.length) named = same
  }
  return named.length ? { paths: named.map((scanned) => scanned.path), from: 'name' } : NOWHERE
}

/** The folders of an album opened by its folder (Needs a look): that one, nothing to find or choose. */
export function folderOnly(path: string): EditFolders {
  return path ? { paths: [path], from: 'folder' } : NOWHERE
}

/** Whether the user has to say which folder it is: several found by name alone. Several of the
 *  release (a set kept one folder per disc) start on the first, with the others a choice away. */
export function needsChoice(folders: EditFolders): boolean {
  return folders.from === 'name' && folders.paths.length > 1
}

/** Whether deleting the folder of `tracks` tracks leaves Navidrome's album with nothing, so the page
 *  goes back from it: it was the album's only folder - or, found by name among several, it holds as
 *  many songs as Navidrome lists for the album (same-named untagged folders can be albums of their
 *  own in Navidrome, told apart by their dates; several of ONE release are one album there). */
export function deletesAll(folders: EditFolders | null, tracks: number, album: EditAlbum | undefined): boolean {
  if (!folders || folders.paths.length <= 1) return true
  return folders.from === 'name' && typeof album?.songCount === 'number' && tracks >= album.songCount
}

/** What the panel's body says while it has no album to edit - or instead of one. */
export interface EditStatus {
  text: string
  busy?: boolean
  /** "Look again": the bridge asked again, and the library read again */
  retry?: boolean
  /** a link to the main page's library, to find the album there */
  mainPage?: boolean
}

export interface EditStatusFacts {
  /** the folder just deleted, if one was */
  deleted: string | null
  /** why the library can't be read at all (LIBRARY_PATH unset) - not an error */
  problem: string | null
  /** the library's last read failed */
  error: string | null
  /** how many albums the library lists */
  albums: number
  /** the library has answered at least once */
  loaded: boolean
  /** what is in hand is the saved scan, the real one not in yet */
  stale: boolean
  /** the id bridge has answered this Edit (or failed to) */
  asked: boolean
  folders: EditFolders | null
  /** an album is held, its editors drawn */
  holding: boolean
  /** the scan in hand lists the (one) folder - the panel is about to take it (2.0.0-player.25 review:
   *  a folder request is "asked" at once, so for a render the folder was known and not yet held) */
  listed?: boolean
  /** the release Navidrome (or the bridge) knows the album by, if any */
  release: string | null
}

/**
 * What the panel says, from what it knows. Two rules from review: an album HELD is being edited, so
 * nothing a later read finds - a hand edit renaming it out of the name it was found by, a refresh
 * that failed - puts "can't find it" over editors still working on it; and a read that failed is
 * said, with Look again, also when the saved scan came in and the real one didn't - else "Finding"
 * would stay up for good, nothing left to read the library again.
 */
export function editStatus(facts: EditStatusFacts): EditStatus | null {
  if (facts.deleted) return { text: `Deleted ${facts.deleted}.` }
  if (facts.problem) return { text: facts.problem }
  if (facts.holding) return null
  if (facts.error && (facts.stale || !facts.albums)) return { text: `deadwax couldn't read the library: ${facts.error}`, retry: true }
  if (!facts.asked || !facts.loaded || facts.stale) return { text: "Finding the album's folder…", busy: true }
  const folders = facts.folders
  if (!folders || !folders.paths.length) {
    return {
      text: facts.release
        ? 'deadwax has no folder of this album: Navidrome knows it by a MusicBrainz release no folder in the library is tagged with.'
        : "deadwax can't tell which folder this album is: Navidrome knows it by no MusicBrainz release, and no untagged folder in the library has its name.",
      retry: true,
      mainPage: true,
    }
  }
  //? the panel draws the folders to choose from instead
  if (needsChoice(folders)) return null
  //? listed and about to be taken: still finding, never "doesn't list" for the render before it is held
  if (facts.listed) return { text: "Finding the album's folder…", busy: true }
  return { text: `The library's scan doesn't list ${folders.paths[0]} yet.`, retry: true }
}

/** How long after a write the album page is asked again, the second time: Navidrome's watcher waits
 *  about five seconds after files change, then scans the folder. */
export const EDIT_SETTLE_MS = 10_000

/** When the album's new id is looked for after an apply changed its release: at once (the apply may
 *  have waited for Navidrome's scan already), then less often while Navidrome scans - about 45 s in
 *  all, and then given up. */
export const FOLLOW_LOOKS_MS: readonly number[] = [0, 3_000, 6_000, 12_000, 24_000]

/** The release to look for the album by after an apply: the album's release now, when it isn't the
 *  one it had - else nothing to look for, since Navidrome keeps the id of an album whose release
 *  stayed. */
export function followRelease(before: string | null | undefined, after: string | null | undefined): string | null {
  const now = (after ?? '').trim().toLowerCase()
  return now && now !== (before ?? '').trim().toLowerCase() ? now : null
}

/** The id the page moves to: Navidrome's album for the release, when it has one and it isn't the
 *  page's own - else none, and the look goes on: right after a rename Navidrome can still have the
 *  album under the old folder's id (it scanned the tags before the rename), and a Navidrome that
 *  keeps ids across a rename answers the page's own id every time. */
export function followsTo(pageId: string, found: string | null | undefined): string | null {
  return found && found !== pageId ? found : null
}

/** Remember that the album of id `from` is now `to` - and that `to` is live again, should an earlier
 *  move have left it (a release applied and then applied back: Navidrome's id for it is the same). */
export function noteMove(moves: Map<string, string>, from: string, to: string): void {
  moves.delete(to)
  if (from !== to) moves.set(from, to)
}

/** Where a page of id `id` goes: the end of its moves (A to B, then B to C, is C), or null when the
 *  id never moved - a loop is followed once round and stopped. */
export function movedTo(moves: ReadonlyMap<string, string>, id: string): string | null {
  const seen = new Set([id])
  let at = id
  for (let next = moves.get(at); next !== undefined && !seen.has(next); next = moves.get(at)) {
    seen.add(next)
    at = next
  }
  return at === id ? null : at
}

/** How long a drawer takes to slide away (player.css's --pl-sheet-duration is 420ms): the editors
 *  inside it are let go once it has, so nothing in them outlives the panel. */
export const EDIT_SLIDE_MS = 450

/** A track's number in the Tags tab: the disc first on a set ("2-04"), the number alone otherwise,
 *  a dot for a file with no number. */
export function trackLabel(track: { position: number | null; disc: number | null }, discs: number): string {
  if (track.position === null) return '·'
  if (discs <= 1) return String(track.position)
  return `${track.disc ?? 1}-${String(track.position).padStart(2, '0')}`
}
