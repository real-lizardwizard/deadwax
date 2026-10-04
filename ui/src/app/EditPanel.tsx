import type { RefObject } from 'preact'
import { useEffect, useLayoutEffect, useMemo, useRef, useState } from 'preact/hooks'

import * as libraryApi from '../api/library'
import { storeAlbum } from '../api/store'
import type { LibraryAlbum, StoreAlbumResponse } from '../api/types'
import { DeleteAlbumDialog } from '../components/DeleteAlbumDialog'
import { GetArtButton, GetDiscArtButton, GetLyricsButton } from '../components/LibraryParts'
import { MetadataEditor, type QueueContext } from '../components/MetadataEditor'
import { TrackTagEditor } from '../components/TrackTagEditor'
import { useLibrary } from '../hooks/useLibrary'
import { useTrackDetails } from '../hooks/useTrackDetails'
import {
  EDIT_SETTLE_MS, EDIT_SLIDE_MS, EDIT_TABS, FOLLOW_LOOKS_MS, deletesAll, editFolders, editStatus, folderOnly, followRelease, followsTo, needsChoice,
  tabAfter, trackLabel,
  type EditAlbum, type EditTab,
} from '../lib/albumEdit'
import { panelIsModal, type PanelStyle } from '../lib/appFrame'
import { albumArtUrl, trackTime } from '../lib/format'
import { isAbort, latestOnly } from '../lib/latest'
import type { FolderChange } from '../lib/needsLook'
import { tickTracks } from '../lib/tagEdit'
import { CloseIcon } from '../player/icons'
import { useSheet } from './useSheet'

/** An Edit pressed on an album page: the album as the page had it, and a new number each time, so
 *  the panel starts afresh for every press. */
export interface EditRequest {
  album: EditAlbum
  key: number
  folder?: undefined
}

/**
 * An album opened from Needs a look (2.0.0-player.25): a FOLDER, by the scan's path - known, so no id
 * bridge and no name guess - and where it sits in the queue, which the release editor is given as its
 * own `queue` (QueueContext: "3 of 17", Previous, Next, Apply becoming Next). A new number each time,
 * a step through the queue included, so each album starts afresh. `reread`: the library read again
 * underneath (the first album of a session; a step between two isn't, the scan in hand is the one the
 * session began on). `onChange`: what became of the album, told to the page that opened it.
 */
export interface FolderRequest {
  folder: string
  key: number
  queue?: QueueContext | undefined
  reread: boolean
  onChange?: ((change: FolderChange & { wrote: boolean }) => void) | undefined
  album?: undefined
}

export const isFolderRequest = (request: EditRequest | FolderRequest | null | undefined): request is FolderRequest =>
  !!request && request.folder !== undefined

/**
 * What became of the album, for App - each about the Navidrome album id it names:
 *  - `written`: a write landed (tags, a release, art, lyrics) - the album page asked again now, and
 *    the library's listeners told;
 *  - `settled`: Navidrome has had time to scan it - the page asked once more;
 *  - `moved`: applying another release gave the album a new id in Navidrome, and this is it;
 *  - `deleted`: its folder is gone - `last` when it was the album's only folder.
 */
export type AlbumChange =
  | { kind: 'written'; id: string }
  | { kind: 'settled'; id: string }
  | { kind: 'moved'; id: string; to: string }
  | { kind: 'deleted'; id: string; last: boolean }
  /** an album opened by its folder (Needs a look): a write (`wrote` - a file changed, not only a review
   *  row) or a delete, by path - there is no album page to follow */
  | { kind: 'folder'; from: string; path: string | null; wrote: boolean }

/** Ticked tracks, for editing their tags together - of one folder, cleared when it changes. */
interface Ticked {
  path: string
  files: Set<string>
  anchor: string | null
}

const NO_FILES: ReadonlySet<string> = new Set()

/** A while, or until `signal` says the wait is over (resolving either way - the caller asks
 *  current() before acting on it). */
function wait(ms: number, signal: AbortSignal | undefined): Promise<void> {
  return new Promise((resolve) => {
    if (ms <= 0 || signal?.aborted) {
      resolve()
      return
    }
    const timer = setTimeout(resolve, ms)
    signal?.addEventListener('abort', () => {
      clearTimeout(timer)
      resolve()
    }, { once: true })
  })
}

/** Where the Escape being dispatched right now came from: out in the PAGE beside the panel, from inside
 *  an editor laid over its tab (the tag editor, the delete confirmation - an INNER layer), or from the
 *  rest of the PANEL - or null, when no Escape is on its way. */
type EscapeFrom = 'page' | 'inner' | 'panel' | null

/**
 * Where an Escape comes from, for the editors' own. They listen for Escape on the whole document and
 * close themselves (the main page's floating windows always did); beside the page that is the page's
 * Escape (a search field clearing, a list closing), so what they ask for then is passed over - and an
 * Escape inside the tag editor or the delete confirmation is THEIRS, closing that layer alone, so the
 * release editor's close (listening whatever tab shows) passes it over too: one press, one layer. Taken
 * in the capture phase, ahead of their listeners and before any of them has changed anything, and
 * true only while that event is still on its way (its eventPhase is 0 once it has been dispatched).
 */
function useEscapeFrom(box: RefObject<HTMLElement>, inner: { current: boolean }): () => EscapeFrom {
  const escape = useRef<{ event: Event; from: Exclude<EscapeFrom, null> } | null>(null)
  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key !== 'Escape') {
        escape.current = null
        return
      }
      const from = !box.current?.contains(event.target as Node | null) ? 'page' : inner.current ? 'inner' : 'panel'
      escape.current = { event, from }
    }
    document.addEventListener('keydown', onKeyDown, true)
    return () => document.removeEventListener('keydown', onKeyDown, true)
  }, [])
  //? one function for the panel's life, so an editor handed it doesn't take its listener off and on
  return useMemo(() => () => {
    const at = escape.current
    return at !== null && at.event.eventPhase !== 0 ? at.from : null
  }, [])
}

/**
 * Edit an album, beside its page (2.0.0-player.21) - the desktop's Edit panel, as
 * DesktopManage.dc.html draws it: "Edit album" and a close button, and underline tabs.
 *
 *  - RELEASE: the main page's metadata editor (components/MetadataEditor.tsx), as it is - its search
 *    as it opens, `selectedId` apart from `selected`, only the newest pick's tracklist, the preview
 *    from the planner the write recomputes, the rename held back for Navidrome and the wait said.
 *  - TAGS: the album's tracks with a tick box each (Shift ticks a run, as the main page's table), and
 *    the main page's tag editor (TrackTagEditor) for the ticked ones - or all of them, none ticked -
 *    its file list fixed as it opens.
 *  - ARTWORK: the cover and CD art - Get cover and Get CD art, the main page's buttons. A cover is
 *    replaced in Release, comparing the two (the main page's rule: never one click from the list).
 *  - LYRICS: how many tracks have a .lrc, and Get lyrics.
 *  - DELETE: the main page's confirmation, with the folder's contents read as the tab opens.
 *
 * OPENED FROM NEEDS A LOOK (2.0.0-player.25) the request names a FOLDER (FolderRequest): no bridge
 * and no name guess, the album taken from the scan by its path; the release editor given where it sits
 * in the queue (its own `queue`, QueueContext - "3 of 17", Previous, Next, Apply becoming Next); the
 * library read again underneath only for a session's first album; and what became of it told by path
 * (`toFolder`): to the page that opened it, and to App (`kind: 'folder'`). A delete there leaves the
 * panel open, saying so, with Next album to go on. The album-page path below is unchanged.
 *
 * WHICH FOLDER comes from the id bridge (GET /deadwax/store/album, by the page's Navidrome id) and,
 * where the store has none, the library's scan (lib/albumEdit.ts editFolders) - asked through one
 * latestOnly(), its answer counting only for the Edit it was asked for; the scan is the main page's
 * (hooks/useLibrary.ts: the saved scan, then a real one), read as the panel first opens - the album
 * taken only from the real one - and read again underneath on every Edit after, the album taken from
 * the scan in hand at once and followed to the fresh one when it lands. Several found by name alone,
 * and the user says which; a set kept one folder per disc starts on the first, the others a choice
 * away. The album is HELD as the album itself, set once, and updated explicitly from the array a
 * reload resolves with - never derived from the list a write reloads (the main page's lesson: a rename
 * landed as two commits, and between them neither path resolved). What the body says instead of an
 * album is lib/albumEdit.ts's editStatus.
 *
 * AFTER A WRITE: App is told (`written` - the page and the library ask again), the album's folders
 * are asked again, the page once more once Navidrome has had time to scan (`settled` - a delete of one
 * folder of several too), and - after an apply that changed the album's release - its new id in
 * Navidrome looked for until found (`moved`). A latestOnly() for the asking again, the next write
 * calling the last one's off; and one of its own for the looking, which only a newer look calls off
 * (or the panel going) - a write straight after an apply (CD art, a hand edit) must not leave the page
 * on an id Navidrome no longer has.
 *
 * A side panel like Sources and Info (useSheet.ts), and the desktop's alone: not modal, no scroll
 * lock, focus in to the close button and back to Edit, Escape closing it only from inside it - and
 * an editor's own Escape (they listen on the document) passed over when it came from the page. The
 * tag editor and the delete confirmation are a layer over their tab: Escape in them closes them alone
 * (useSheet's `covered`, and the release editor's close passing it over). A control that removes
 * itself hands focus on inside the panel, never to the page. It stays mounted while the desktop frame
 * shows; the editors in it are let go once it has closed (at once as a column, once a drawer has slid
 * away), so nothing of theirs - the cover viewer's Escape on the window - outlives it.
 */
export function EditPanel({
  open,
  request,
  opener,
  onClose,
  onChanged,
  panel = 'column',
  covered = false,
}: {
  open: boolean
  request: EditRequest | FolderRequest | null
  opener?: { current: HTMLElement | null } | undefined
  onClose: () => void
  onChanged: (change: AlbumChange) => void
  /** how it is drawn: a drawer over the page's edge, or a third column */
  panel?: PanelStyle
  /** the desktop's visualizer is over everything (2.0.0-player.20): inert under it, an Escape the visualizer's */
  covered?: boolean
}) {
  const modal = panelIsModal(panel)
  const box = useRef<HTMLDivElement>(null)
  const closeButton = useRef<HTMLButtonElement>(null)
  const scroller = useRef<HTMLDivElement>(null)
  const tablist = useRef<HTMLDivElement>(null)
  const tagsPane = useRef<HTMLDivElement>(null)

  //? read when an answer lands, not as the render that started it saw them
  const changed = useRef(onChanged)
  changed.current = onChanged
  const close = useRef(onClose)
  close.current = onClose
  const requestNow = useRef(request)
  requestNow.current = request

  const library = useLibrary(open)
  const libraryReady = library.loaded && !library.stale

  //? the id bridge's answer for the album, and the Edit it answered (or failed to) - its answer
  //? counts only for that one
  const lookups = useMemo(latestOnly, [])
  const [answer, setAnswer] = useState<StoreAlbumResponse | null>(null)
  const [askedFor, setAskedFor] = useState<number | null>(null)
  const asked = request !== null && askedFor === request.key
  //? the album being edited - held, never derived (see the note above)
  const [subject, setSubject] = useState<LibraryAlbum | null>(null)
  //? a new editor for each album and folder: the release editor keeps itself across an apply
  const [session, setSession] = useState(0)
  const [tab, setTab] = useState<EditTab>('release')
  const [tagsSeen, setTagsSeen] = useState(false)
  const [ticked, setTicked] = useState<Ticked | null>(null)
  //? the tag editor's files, fixed as it opens (its preview is never recomputed against a selection
  //? that changed underneath it)
  const [editingTags, setEditingTags] = useState<{ path: string; filenames: string[] } | null>(null)
  const [deleted, setDeleted] = useState<string | null>(null)
  const afterWrites = useMemo(latestOnly, [])
  const follows = useMemo(latestOnly, [])
  //? every write the panel makes, counted: a read of the library begun before one is older than what
  //? that write's own reload followed
  const writes = useRef(0)

  //? The editors let go once the panel has closed - at once as a column (gone in a frame), once a
  //? drawer has slid away - so nothing in them outlives it: the cover viewer, left open, would go on
  //? taking the next Escape anywhere in the app (it listens on the window). Every Edit is a new
  //? request, so nothing worth keeping goes with them.
  const [letGo, setLetGo] = useState(!open)
  useEffect(() => {
    if (open) {
      setLetGo(false)
      return
    }
    const timer = setTimeout(() => setLetGo(true), panel === 'drawer' ? EDIT_SLIDE_MS : 0)
    return () => clearTimeout(timer)
  }, [open])
  const drawn = !!subject && !!request && !deleted && !letGo

  //? an editor laid over its tab - the tag editor, the delete confirmation - takes Escape for itself:
  //? the panel doesn't close under it (`covered`), nor does the release editor's close let it through
  const inner = drawn && ((tab === 'tags' && editingTags !== null && editingTags.path === subject!.path) || tab === 'delete')
  const innerNow = useRef(inner)
  innerNow.current = inner
  useSheet({ open, covered: inner || covered, onClose, lockClass: 'app-edit-open', first: closeButton, opener, modal, area: box })
  const escapeFrom = useEscapeFrom(box, innerNow)

  //? A control that removes itself (Edit N tracks…, the tag editor's Close, Delete's Cancel, Look
  //? again, a folder chosen) hands focus on inside the panel once the swap has drawn - never to the
  //? page, where an Escape would be the page's and close nothing here. Only when focus was lost with
  //? it (fallen to the page's body - or never taken, a click in WebKit): focus anywhere else stays.
  const focusNext = useRef<(() => HTMLElement | null | undefined) | null>(null)
  useLayoutEffect(() => {
    const pick = focusNext.current
    if (!pick) return
    focusNext.current = null
    const active = document.activeElement
    if (active && active !== document.body) return
    pick()?.focus({ preventScroll: true })
  })
  const toTab = (which: EditTab) => () => tablist.current?.querySelector<HTMLElement>(`[data-tab="${which}"]`)

  /** The id bridge asked which folders the album is - by the page's Navidrome id. An album opened by
   *  its folder needs nothing asked: the folder is known. */
  const lookUp = (at: EditRequest | FolderRequest) => {
    if (isFolderRequest(at)) {
      //? an earlier album-page Edit's lookup still out must not land on this folder's request
      lookups.supersede()
      setAnswer(null)
      setAskedFor(at.key)
      return
    }
    const ticket = lookups.begin()
    setAskedFor(null)
    storeAlbum({ navidrome_id: at.album.id }, ticket.signal).then(
      (found) => {
        if (!ticket.current()) return
        setAnswer(found)
        setAskedFor(at.key)
      },
      (reason: unknown) => {
        //? the bridge not answering leaves the scan to find it, by the release Navidrome said
        if (ticket.current() && !isAbort(reason)) setAskedFor(at.key)
      },
    )
  }

  //? every Edit pressed: the album's folders asked afresh, everything about the last one let go - as
  //? it opens, never for a request kept from before (the panel mounted again, closed, as the window
  //? crosses back into the desktop frame). After the first, the library is read again underneath
  //? (the app is a player left open for hours; another device, or the main page, may have changed the
  //? album since): the album is taken from the scan in hand at once, and followed to the fresh one -
  //? or let go, its folder gone, to be taken again from what the fresh one says - unless a write has
  //? been made meanwhile, whose own reload followed it already.
  const lookedUp = useRef<number | null>(null)
  useEffect(() => {
    if (!open || !request || lookedUp.current === request.key) return
    lookedUp.current = request.key
    //? a step through the queue (skip, Previous, Next album) takes the editor that had focus away with
    //? the album it was on: focus goes on to the Release tab once the swap has drawn, never to the page
    //? (2.0.0-player.25 review) - only when it was in the panel, or nowhere (a click in WebKit)
    if (isFolderRequest(request)) {
      const active = document.activeElement
      if (!active || active === document.body || box.current?.contains(active)) focusNext.current = toTab('release')
    }
    setAnswer(null)
    setSubject(null)
    setSession((n) => n + 1)
    setTab('release')
    setTagsSeen(false)
    setTicked(null)
    setEditingTags(null)
    setDeleted(null)
    lookUp(request)
    if (!library.loaded || library.loading) return
    //? a step through the queue: the scan in hand is the one the session began on
    if (isFolderRequest(request) && !request.reread) return
    const key = request.key
    const since = writes.current
    void library.reload(false).then((fresh) => {
      if (!fresh.length || lookedUp.current !== key || writes.current !== since) return
      setSubject((current) => (current ? fresh.find((album) => album.path === current.path) ?? null : current))
    })
  }, [open, request?.key])

  //? "Look again": the bridge, and the library's scan
  const lookAgain = () => {
    const at = requestNow.current
    if (at) lookUp(at)
    void library.reload(false)
    focusNext.current = () => scroller.current
  }

  //? what the editors ask to close - passed over for an Escape out in the page, and (the release
  //? editor's, listening whatever tab shows) for one in a layer over its tab - each one function for
  //? the panel's life (they re-listen whenever it changes)
  const closeFromEditor = useMemo(() => () => {
    const from = escapeFrom()
    if (from !== 'page' && from !== 'inner') close.current()
  }, [])
  const closeTagEditor = useMemo(() => () => {
    if (escapeFrom() === 'page') return
    setEditingTags(null)
    focusNext.current = () => tagsPane.current?.querySelector<HTMLElement>('.app-edit-tags-open')
  }, [])
  const cancelDelete = useMemo(() => () => {
    if (escapeFrom() === 'page') return
    setTab('release')
    focusNext.current = toTab('release')
  }, [])

  //? the lookup, and what comes after a write, are let go only as the panel goes - or the next one
  useEffect(() => () => {
    lookups.supersede()
    afterWrites.supersede()
    follows.supersede()
  }, [])

  const folders = useMemo(
    () => (request && asked && libraryReady
      ? (isFolderRequest(request) ? folderOnly(request.folder) : editFolders(answer, library.albums, request.album))
      : null),
    [request, asked, libraryReady, answer, library.albums],
  )

  //? the album, once its folder is known and the real scan is in - taken once, and again should a
  //? fresh read have let it go
  useEffect(() => {
    if (subject || deleted || !folders || !folders.paths.length || needsChoice(folders)) return
    const found = library.albums.find((album) => album.path === folders.paths[0])
    if (found) setSubject(found)
  }, [folders, subject])

  const scrollTop = () => {
    if (scroller.current) scroller.current.scrollTop = 0
  }

  /** Another folder of the album, or the one chosen of several by name. */
  const chooseFolder = (path: string) => {
    const found = library.albums.find((album) => album.path === path)
    if (!found) return
    setSubject(found)
    setSession((n) => n + 1)
    setTicked(null)
    setEditingTags(null)
    scrollTop()
  }

  /** The album as a reload has it: followed to its new folder only while it is still the one shown. */
  const follow = (fresh: readonly LibraryAlbum[], oldPath: string, newPath = oldPath): LibraryAlbum | null => {
    const updated = fresh.find((album) => album.path === newPath) ?? null
    if (updated) setSubject((current) => (current && current.path === oldPath ? updated : current))
    return updated
  }

  /** The id the Edit a write was made under names the album by now: App moves it with the page. */
  const idOf = (at: EditRequest) => {
    const now = requestNow.current
    return now?.key === at.key && !isFolderRequest(now) ? now.album.id : at.album.id
  }

  /** Navidrome asked again once it has had time to scan what a write changed: the page asked once more. */
  const settleLater = (at: EditRequest) => {
    const ticket = afterWrites.begin()
    void wait(EDIT_SETTLE_MS, ticket.signal).then(() => {
      if (ticket.current()) changed.current({ kind: 'settled', id: idOf(at) })
    })
    return ticket
  }

  /** What became of an album opened by its folder (Needs a look): told to the page that opened it, by
   *  the path it had, and to App (the library's listeners, the count) - by path, there being no album
   *  page to follow. */
  const toFolder = (at: FolderRequest, from: string, album: LibraryAlbum | null, wrote: boolean, deleted = false) => {
    at.onChange?.({ from, album, deleted, wrote })
    changed.current({ kind: 'folder', from, path: deleted ? null : album?.path ?? from, wrote })
  }

  /** After a write: App told, the folders asked again, the page again once Navidrome has scanned -
   *  and, when the album's release changed, its new id looked for until Navidrome has it. `at` is the
   *  Edit the write was made under - an apply that waited for Navidrome can land after another album's
   *  Edit was pressed - and its album's id the latest App has given it (a move changes it). */
  const afterWrite = (at: EditRequest, release: string | null, lookFor: string | null) => {
    writes.current += 1
    changed.current({ kind: 'written', id: idOf(at) })
    const ticket = settleLater(at)
    if (release) {
      storeAlbum({ release_mbid: release }, ticket.signal).then(
        (found) => {
          if (ticket.current() && requestNow.current?.key === at.key) setAnswer(found)
        },
        () => {},
      )
    }
    if (lookFor) lookForMove(idOf(at), lookFor)
  }

  /** The album's new id in Navidrome, looked for by its new release until Navidrome has it - through a
   *  latestOnly of its own: only a newer look calls it off (or the panel going), never another write. */
  const lookForMove = (from: string, release: string) => {
    const ticket = follows.begin()
    void (async () => {
      for (const delay of FOLLOW_LOOKS_MS) {
        await wait(delay, ticket.signal)
        if (!ticket.current()) return
        try {
          const found = await storeAlbum({ release_mbid: release }, ticket.signal)
          if (!ticket.current()) return
          //? the page's own id is no answer: Navidrome can still list the album at the folder the
          //? apply's rename left - scanned between the tags and the rename - until it scans the move
          const to = followsTo(from, found.navidrome_id)
          if (!to) continue
          changed.current({ kind: 'moved', id: from, to })
          return
        } catch {
          if (!ticket.current()) return
        }
      }
    })()
  }

  /* ----- what the editors are told ----- */

  //? the release editor's apply: the album followed to where it lives now (the same folder unless
  //? it was renamed), and - when its release changed - its new id in Navidrome looked for
  const releaseApplied = (at: EditRequest | FolderRequest, album: LibraryAlbum) => async (newPath: string) => {
    writes.current += 1
    const fresh = await library.reload(false)
    const updated = follow(fresh, album.path, newPath)
    if (isFolderRequest(at)) {
      toFolder(at, album.path, updated, true)
      return
    }
    const release = updated?.release_mbid || null
    afterWrite(at, release, followRelease(album.release_mbid, release))
  }

  //? an ignore or an un-ignore changes no file - only the review row, and so the count
  const ignoreAlbum = async (album: LibraryAlbum, issues: string[]) => {
    const at = requestNow.current
    await libraryApi.ignoreIssues(album.path, issues)
    writes.current += 1
    const updated = follow(await library.reload(false), album.path)
    if (isFolderRequest(at)) toFolder(at, album.path, updated, false)
  }

  const unignoreAlbum = async (album: LibraryAlbum) => {
    const at = requestNow.current
    await libraryApi.unignoreAlbum(album.path)
    writes.current += 1
    const updated = follow(await library.reload(false), album.path)
    if (isFolderRequest(at)) toFolder(at, album.path, updated, false)
  }

  //? tags, a cover, CD art, lyrics: the folder stays, and so does the release
  const wrote = (at: EditRequest, album: LibraryAlbum) => async () => {
    writes.current += 1
    follow(await library.reload(false), album.path)
    afterWrite(at, album.release_mbid || null, null)
  }

  //? ...and for an album opened by its folder: the page that opened it told, by path
  const wroteFolder = (at: FolderRequest, album: LibraryAlbum) => async () => {
    writes.current += 1
    const updated = follow(await library.reload(false), album.path)
    toFolder(at, album.path, updated, true)
  }

  const written = (at: EditRequest | FolderRequest, album: LibraryAlbum) =>
    isFolderRequest(at) ? wroteFolder(at, album) : wrote(at, album)

  //? deleted: App closes the panel, and goes back from the page when nothing of the album is left in
  //? Navidrome (`last`); after one folder of several the page stays, asked again now and once Navidrome
  //? has scanned the folder gone
  const albumDeleted = (at: EditRequest | FolderRequest, album: LibraryAlbum, last: boolean) => () => {
    if (requestNow.current?.key === at.key) {
      setDeleted(album.path)
      setEditingTags(null)
    }
    writes.current += 1
    void library.reload(false)
    //? opened from Needs a look: the panel stays - the row says Deleted, and Next goes on
    if (isFolderRequest(at)) {
      toFolder(at, album.path, null, true, true)
      return
    }
    changed.current({ kind: 'deleted', id: idOf(at), last })
    if (!last) settleLater(at)
  }

  /* ----- the tabs ----- */

  const choose = (next: EditTab) => {
    setTab(next)
    if (next === 'tags') setTagsSeen(true)
    scrollTop()
  }

  //? a tab list's keys: the arrows move the choice, and focus with it
  const onTabKeyDown = (event: KeyboardEvent) => {
    const step = event.key === 'ArrowRight' ? 1 : event.key === 'ArrowLeft' ? -1 : 0
    if (!step) return
    event.preventDefault()
    const next = tabAfter(tab, step)
    choose(next)
    ;(event.currentTarget as HTMLElement).querySelector<HTMLElement>(`[data-tab="${next}"]`)?.focus()
  }

  //? the track list's details, read live - only once Tags has been opened (the main page's rule: a
  //? dozen files are opened only for the album you are looking at)
  const details = useTrackDetails(subject && tagsSeen ? subject.path : null, library.albums)

  const tick = (filename: string, range: boolean) => {
    if (!subject) return
    const order = subject.tracks.map((track) => track.filename)
    setTicked((current) => {
      const mine = current?.path === subject.path
      return { path: subject.path, ...tickTracks(order, mine ? current.files : NO_FILES, mine ? current.anchor : null, filename, range) }
    })
  }

  const tickAll = (on: boolean) => {
    if (!subject) return
    setTicked({ path: subject.path, files: on ? new Set(subject.tracks.map((track) => track.filename)) : new Set(), anchor: null })
  }

  const checked = subject && ticked?.path === subject.path ? ticked.files : NO_FILES

  //? the tag editor opened on these files: focus into it - its first field once the files are read,
  //? its close button until then
  const openTagEditor = (path: string, filenames: string[]) => {
    setEditingTags({ path, filenames })
    focusNext.current = () => tagsPane.current?.querySelector<HTMLElement>('#tags-window input:not([type="checkbox"])')
      ?? tagsPane.current?.querySelector<HTMLElement>('#tags-window .window-close')
  }

  /* ----- what the body says ----- */

  const status = request ? editStatus({
    deleted,
    problem: library.problem,
    error: library.error,
    albums: library.albums.length,
    loaded: library.loaded,
    stale: library.stale,
    asked,
    folders,
    holding: !!subject,
    listed: !!folders && folders.paths.length === 1 && library.albums.some((album) => album.path === folders.paths[0]),
    release: answer?.release_mbid ?? request.album?.musicBrainzId ?? null,
  }) : null

  const choosing = !!folders && needsChoice(folders) && !subject && !deleted
  //? where the album sits in the queue, when it was opened from Needs a look
  const queue = isFolderRequest(request) ? request.queue : undefined

  return (
    <div class={`app-layer app-edit-layer${open ? ' is-open' : ''} is-panel is-${panel}`} aria-hidden={!open || covered} inert={!open || covered}>
      <div class="app-backdrop" onClick={onClose} />
      {/* the box takes focus from a click on anything in it that can't, so Escape there is still
          from inside it */}
      <div ref={box} class="app-edit" role="dialog" aria-modal={modal ? 'true' : 'false'} aria-labelledby="app-edit-title" tabIndex={-1}>
        <header class="app-edit-head">
          <h2 id="app-edit-title" class="app-edit-title">Edit album</h2>
          <button ref={closeButton} type="button" class="app-edit-close" aria-label="Close the editor" onClick={onClose}>
            <CloseIcon class="app-edit-close-icon" />
          </button>
        </header>

        <div ref={tablist} class="app-edit-tabs" role="tablist" aria-label="Edit album" onKeyDown={onTabKeyDown}>
          {EDIT_TABS.map((entry) => {
            const chosen = entry.id === tab
            return (
              <button
                key={entry.id}
                type="button"
                role="tab"
                id={`app-edit-tab-${entry.id}`}
                class={`app-edit-tab${chosen ? ' is-on' : ''}`}
                data-tab={entry.id}
                aria-selected={chosen}
                aria-controls={subject ? `app-edit-panel-${entry.id}` : undefined}
                tabIndex={chosen ? 0 : -1}
                onClick={() => choose(entry.id)}
              >
                {entry.label}
              </button>
            )
          })}
        </div>

        {/* a set kept one folder per disc - or several by name, one chosen: which one is edited */}
        {subject && folders && folders.paths.length > 1 && !deleted && (
          <label class="app-edit-folder">
            <span class="app-edit-label">Folder</span>
            <select
              class="app-edit-select"
              value={subject.path}
              onChange={(event) => chooseFolder((event.currentTarget as HTMLSelectElement).value)}
            >
              {(folders.paths.includes(subject.path) ? folders.paths : [subject.path, ...folders.paths]).map((path) => (
                <option key={path} value={path}>{path}</option>
              ))}
            </select>
          </label>
        )}

        <div ref={scroller} class="app-edit-body" tabIndex={-1}>
          {status && (
            <div class="app-edit-state" role="status">
              {status.busy && <span class="app-sweep app-edit-sweep" aria-hidden="true" />}
              <p class="app-edit-note">{status.text}</p>
              {status.retry && (
                <button type="button" class="app-edit-button" disabled={library.loading || !asked} onClick={lookAgain}>
                  Look again
                </button>
              )}
              {status.mainPage && (
                <a class="app-edit-link" href="/" target="_blank" rel="noopener">
                  Open the main page
                </a>
              )}
              {/* deleted from Needs a look: the queue goes on from here */}
              {deleted && queue && queue.position < queue.total && (
                <button type="button" class="app-edit-button" onClick={queue.onNext}>
                  Next album ▷
                </button>
              )}
            </div>
          )}

          {choosing && (
            <div class="app-edit-state">
              <p class="app-edit-note">
                Navidrome knows this album by no MusicBrainz release, and {folders!.paths.length} untagged folders in the
                library have its name. Which one is it?
              </p>
              <ul class="app-edit-choices">
                {folders!.paths.map((path) => (
                  <li key={path}>
                    <button
                      type="button"
                      class="app-edit-choice"
                      onClick={() => {
                        chooseFolder(path)
                        focusNext.current = toTab(tab)
                      }}
                    >
                      {path}
                    </button>
                  </li>
                ))}
              </ul>
            </div>
          )}

          {drawn && subject && request && (
            <>
              <div id="app-edit-panel-release" class="app-edit-pane" role="tabpanel" aria-labelledby="app-edit-tab-release" hidden={tab !== 'release'}>
                <MetadataEditor
                  key={session}
                  album={subject}
                  issueTypes={library.issueTypes}
                  queue={queue}
                  onClose={closeFromEditor}
                  onApplied={releaseApplied(request, subject)}
                  onIgnore={ignoreAlbum}
                  onUnignore={unignoreAlbum}
                />
              </div>

              <div ref={tagsPane} id="app-edit-panel-tags" class="app-edit-pane" role="tabpanel" aria-labelledby="app-edit-tab-tags" hidden={tab !== 'tags'}>
                {editingTags && editingTags.path === subject.path ? (
                  <TrackTagEditor
                    key={`${session}:${editingTags.filenames.join('\n')}`}
                    album={subject}
                    filenames={editingTags.filenames}
                    details={details}
                    onClose={closeTagEditor}
                    onApplied={written(request, subject)}
                  />
                ) : (
                  <TagsList
                    album={subject}
                    checked={checked}
                    onTick={tick}
                    onTickAll={tickAll}
                    onEdit={(filenames) => openTagEditor(subject.path, filenames)}
                  />
                )}
              </div>

              <div id="app-edit-panel-artwork" class="app-edit-pane" role="tabpanel" aria-labelledby="app-edit-tab-artwork" hidden={tab !== 'artwork'}>
                <ArtworkTab album={subject} onDone={written(request, subject)} />
              </div>

              <div id="app-edit-panel-lyrics" class="app-edit-pane" role="tabpanel" aria-labelledby="app-edit-tab-lyrics" hidden={tab !== 'lyrics'}>
                <LyricsTab album={subject} onDone={written(request, subject)} />
              </div>

              {/* drawn only while it shows: what the folder holds is read as it opens, never kept */}
              <div id="app-edit-panel-delete" class="app-edit-pane" role="tabpanel" aria-labelledby="app-edit-tab-delete" hidden={tab !== 'delete'}>
                {tab === 'delete' && (
                  <DeleteAlbumDialog
                    key={subject.path}
                    album={subject}
                    onCancel={cancelDelete}
                    onDeleted={albumDeleted(request, subject, deletesAll(folders, subject.track_count, request.album))}
                  />
                )}
              </div>
            </>
          )}
        </div>
      </div>
    </div>
  )
}

/**
 * The album's tracks, a tick box each, as the main page's track table ticks them: one click ticks
 * one, Shift ticks the run from the last one clicked to this one's new state, the head's box ticks
 * or unticks them all. "Edit N tracks…" opens the tag editor on the ticked ones - or on all of them
 * with none ticked. Each box sits in a label filling its cell, the target a finger needs where the
 * pointer is coarse (a click on the label is the box's, Shift and all).
 */
function TagsList({
  album,
  checked,
  onTick,
  onTickAll,
  onEdit,
}: {
  album: LibraryAlbum
  checked: ReadonlySet<string>
  onTick: (filename: string, range: boolean) => void
  onTickAll: (on: boolean) => void
  onEdit: (filenames: string[]) => void
}) {
  const tracks = album.tracks
  const count = tracks.filter((track) => checked.has(track.filename)).length
  const all = count > 0 && count === tracks.length
  const some = count > 0 && !all
  const targets = tracks.map((track) => track.filename).filter((name) => !count || checked.has(name))

  return (
    <div class="app-edit-tags">
      <div class="app-edit-actions">
        <button type="button" class="app-edit-button app-edit-tags-open" disabled={!targets.length} onClick={() => onEdit(targets)}>
          {count ? `Edit ${count} track${count === 1 ? '' : 's'}…` : 'Edit all tracks…'}
        </button>
        <span class="app-edit-note">
          {count ? `${count} of ${tracks.length} ticked` : 'Tick tracks to edit only those; Shift ticks a run.'}
        </span>
      </div>

      <table class="app-edit-tracks">
        <thead>
          <tr>
            <th class="app-edit-tick">
              <label class="app-edit-hit">
                <input
                  type="checkbox"
                  aria-label={all ? 'Untick every track' : 'Tick every track'}
                  checked={all}
                  ref={(element) => {
                    if (element) element.indeterminate = some
                  }}
                  onChange={() => onTickAll(!all)}
                />
              </label>
            </th>
            <th class="app-edit-number">#</th>
            <th>Title</th>
            <th class="app-edit-length">Length</th>
          </tr>
        </thead>
        <tbody>
          {tracks.map((track) => {
            const on = checked.has(track.filename)
            return (
              <tr key={track.filename} class={on ? 'is-ticked' : ''}>
                <td class="app-edit-tick">
                  <label class="app-edit-hit">
                    <input
                      type="checkbox"
                      aria-label={`Tick ${track.title || track.filename}`}
                      checked={on}
                      onClick={(event) => onTick(track.filename, event.shiftKey)}
                    />
                  </label>
                </td>
                <td class="app-edit-number">{trackLabel(track, album.disc_count)}</td>
                <td class="app-edit-title-cell" title={track.filename}>{track.title || track.filename}</td>
                <td class="app-edit-length">{trackTime(track.length)}</td>
              </tr>
            )
          })}
        </tbody>
      </table>
    </div>
  )
}

/** The cover and CD art: what the folder has, and the main page's Get buttons where they can help. */
function ArtworkTab({ album, onDone }: { album: LibraryAlbum; onDone: () => void }) {
  const ownDisc = (album.disc_art ?? []).filter((name) => name.toLowerCase().startsWith('disc'))
  return (
    <div class="app-edit-sections">
      <section class="app-edit-section" aria-labelledby="app-edit-cover">
        <h3 id="app-edit-cover" class="app-edit-heading">Cover</h3>
        <div class="app-edit-cover-row">
          {album.art ? (
            <img class="app-edit-cover" src={albumArtUrl(album)} alt="" />
          ) : (
            <span class="app-edit-cover is-empty" aria-hidden="true" />
          )}
          <div class="app-edit-lines">
            <p class="app-edit-note">
              {album.art === 'file' ? 'A cover is saved beside the tracks.'
                : album.art === 'embedded' ? 'The cover is inside the files, with none beside them.'
                : 'No cover is saved with the album.'}
            </p>
            <GetArtButton album={album} onDone={onDone} class="app-edit-button" />
            {!album.release_mbid ? (
              <p class="app-edit-note">A cover is looked up by the album's release: match one in Release first.</p>
            ) : album.art ? (
              <p class="app-edit-note">To replace it, compare it with the release's in Release (Compare full size…).</p>
            ) : null}
          </div>
        </div>
      </section>

      <section class="app-edit-section" aria-labelledby="app-edit-disc">
        <h3 id="app-edit-disc" class="app-edit-heading">CD art</h3>
        <p class="app-edit-note">
          {(album.disc_art ?? []).length ? `Beside the tracks: ${(album.disc_art ?? []).join(', ')}.` : 'No picture of the disc beside the tracks.'}
        </p>
        <GetDiscArtButton album={album} onDone={onDone} class="app-edit-button" />
        {!album.release_mbid ? (
          <p class="app-edit-note">CD art is looked up by the album's release: match one in Release first.</p>
        ) : ownDisc.length ? (
          <p class="app-edit-note">deadwax never replaces CD art it saved.</p>
        ) : null}
      </section>
    </div>
  )
}

/** How many tracks have lyrics, and Get lyrics for the rest. */
function LyricsTab({ album, onDone }: { album: LibraryAlbum; onDone: () => void }) {
  return (
    <div class="app-edit-sections">
      <section class="app-edit-section" aria-labelledby="app-edit-lyrics">
        <h3 id="app-edit-lyrics" class="app-edit-heading">Lyrics</h3>
        <p class="app-edit-note">
          {album.lyrics_count} of {album.track_count} track{album.track_count === 1 ? ' has' : 's have'} lyrics saved beside
          {album.track_count === 1 ? ' it' : ' them'}, as a .lrc.
        </p>
        <GetLyricsButton album={album} onDone={onDone} class="app-edit-button" />
        {album.lyrics_count >= album.track_count && <p class="app-edit-note">Every track has lyrics.</p>}
        <p class="app-edit-note">The lyrics lead, and re-timing what is saved, are in the main page's settings.</p>
      </section>
    </div>
  )
}
