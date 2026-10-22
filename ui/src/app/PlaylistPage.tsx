import { useEffect, useLayoutEffect, useMemo, useRef, useState } from 'preact/hooks'

import { ApiError } from '../api/http'
import { deletePlaylist, editPlaylist, playlist as fetchPlaylist, type Playlist, type PlaylistWithSongs } from '../api/playlists'
import { trackTime } from '../lib/format'
import { isAbort, latestOnly } from '../lib/latest'
import { dragOffset, dropIndex } from '../lib/pins'
import {
  DISCARD_QUESTION, NEEDS_A_NAME, PLAYLIST_CHANGED, PLAYLIST_COMMENT_MAX, PLAYLIST_EMPTY, PLAYLIST_GONE, PLAYLIST_NAME_MAX, SHARED_NOTE,
  canEdit, deleteQuestion, dragDistance, edgeScroll, editBody, hiddenEditWords, hiddenWords, moveRow, ownerLine, playlistAlbums,
  readOnlyWords, removeRow, songsLine, startEdit, stubFor, withHeld, type EditState,
} from '../lib/playlists'
import type { QueuePick } from '../lib/upNext'
import { Cover } from '../player/Cover'
import { playedAlbum, rememberQueue, toQueueTrack, type AlbumWithSongs } from '../player/api'
import { queued } from '../player/levelling'
import { CheckIcon, ChevronDownIcon, ChevronLeftIcon, ChevronUpIcon, CloseIcon, GripIcon, MoreIcon, PlayIcon, PlayingBars, PlaylistIcon, ShuffleIcon } from '../player/icons'
import type { Player } from '../player/usePlayer'
import { ConfirmLine } from './ConfirmLine'
import { announcePlaylistChanged, forgetPlaylist, keepPlaylist, keptPlaylist, onPlaylistChanged } from './usePlaylists'

/** A row being dragged in Edit: which, from where, the pointer's start and now, the page's scroll at the start,
 *  the rows' pitch, and the pointer. */
interface Drag {
  key: string
  start: number
  y: number
  clientY: number
  scroll: number
  dy: number
  pitch: number
  pointer: number
}

/** What the fixed chrome at the bottom is - the tab bar, the mini player, a desktop's player bar - whose tops a
 *  dragged row scrolls the page short of. */
const BOTTOM_CHROME = '.app-tabbar, .pl-mini, .app-playbar'

/**
 * One playlist (2.0.0-player.58, `#/<tab>/playlist/<id>`) - laid out as an album's page (its classes, so a desktop
 * puts the cover beside the title as it does an album's): Navidrome's 2x2 mosaic, the name, whose it is, its
 * description, Play and Shuffle, the songs with each one's own cover, the count and length at the foot.
 *
 * PLAYING is playTracks with the songs in hand - the page has every one once it has drawn them - from Play, Shuffle
 * and a row's tap, straight from the click, nothing awaited (the gesture rule): the albums the songs are on
 * remembered first (lib/playlists.ts playlistAlbums - stubs, for Info, the turntable's disc art and Go to album -
 * and withHeld: an album's own answer held already is remembered as it is, never a stub over it), then the player. Play Next and Play Last are the song menu's (a row's •••, and the bar's for the whole playlist,
 * which also adds its songs to another playlist); Shuffle starts a shuffled queue Up Next can un-shuffle.
 *
 * ASKED as it opens (latestOnly) - drawn at once from the answer kept for it (usePlaylists keptPlaylist: going back
 * to it from an album remounts it, and App puts the scroll back before anything else could draw), else from the
 * row that opened it - again each time it shows after not showing, and when a write here changed it; never while
 * Edit is open (Done's base check catches a change made meanwhile). Edit is offered only once this mount's own ask
 * has answered (or its own Done): a kept answer, or one a write here has made old, is never Done's base. A refresh
 * that fails keeps what is drawn and says so, Edit waiting; a 404 says the playlist has gone.
 *
 * EDIT - yours, editable, at most 2,000 songs: the name, the description, sharing, and the songs - removed, or
 * reordered by Move up / Move down or by dragging the grip (the page scrolling itself near an edge) - all saved at
 * once with Done (`base`, the songs as drawn when Edit began, and the songs now: a playlist changed in another app
 * meanwhile is a 409, nothing saved, and it is drawn as it is now, the page at its top where that is said). Done
 * refused leaves Edit open with the reason, and the next Done sends `tried` - the songs the refused one sent, which
 * Navidrome may have taken before refusing; leaving Edit after one asks the playlist again. Cancel with changes asks
 * first. The reason and the question show in the bar, which stays in view however far down the rows are. Delete
 * playlist, last, asks too (ConfirmLine) - there is no undo. Somebody else's, or one from a file, says why there is no
 * Edit. Nothing drawn and the first ask failing: why, and Try again.
 *
 * It reads of the player only playTracks, whether it plays and the playing song's id - what an album page reads,
 * so App's pages memo needs no new key (ui/test/app-rules.sim.cjs holds both to it).
 */
export function PlaylistPage({
  id,
  preview,
  player,
  onBack,
  backLabel,
  shown,
  onDeleted,
  onQueueMenu,
}: {
  id: string
  /** the row that opened it - the hero draws at once */
  preview: Playlist | null
  player: Player
  onBack: () => void
  backLabel: string
  /** its tab current and the app in front */
  shown: boolean
  /** deleted here: App says so and - this page still what shows - goes back */
  onDeleted: (name: string, id: string) => void
  /** a song's ••• or the playlist's own: the song menu, the songs in hand */
  onQueueMenu?: ((event: MouseEvent, pick: QueuePick<AlbumWithSongs>) => void) | undefined
}) {
  const [answer, setAnswer] = useState<PlaylistWithSongs | null>(() => keptPlaylist(id))
  //? (review) what is drawn is how the playlist stands - this mount's own ask answered, or its own Done - and so Edit
  //? may begin from it; a kept answer drawn at once is for Back's place and for playing, never Done's base
  const [fresh, setFresh] = useState(false)
  const [gone, setGone] = useState(false)
  const [refreshFailed, setRefreshFailed] = useState<string | null>(null)
  const [note, setNote] = useState<string | null>(null)
  const [asks, setAsks] = useState(0)
  const requests = useMemo(latestOnly, [])
  //? Edit: where it began, what it is now, the save out, why it was refused, a question asked
  const [start, setStart] = useState<EditState | null>(null)
  const [edit, setEdit] = useState<EditState | null>(null)
  const [saving, setSaving] = useState(false)
  const [editProblem, setEditProblem] = useState<string | null>(null)
  const [asking, setAsking] = useState<'discard' | 'delete' | null>(null)
  const [deleting, setDeleting] = useState(false)
  const [deleteProblem, setDeleteProblem] = useState<string | null>(null)
  const [said, setSaid] = useState('')
  const [drag, setDrag] = useState<Drag | null>(null)
  const dragNow = useRef<Drag | null>(null)
  dragNow.current = drag
  const editing = edit !== null
  const editingNow = useRef(false)
  editingNow.current = editing
  const bar = useRef<HTMLElement>(null)
  const list = useRef<HTMLOListElement>(null)
  const toggle = useRef<HTMLButtonElement>(null)
  const deleteButton = useRef<HTMLButtonElement>(null)
  //? where focus goes once a change has drawn - never dropped to the page, where a keyboard's or VoiceOver's place goes
  const refocus = useRef<{ key: string; which: 'up' | 'down' | 'remove' } | 'toggle' | 'delete' | null>(null)
  //? (review) the songs the last Done that FAILED sent: Navidrome may have taken them before failing (PART_SAVED, or
  //? the read after the write), so the next Done says so (`tried`) - and leaving Edit then asks the playlist again
  const tried = useRef<string[] | null>(null)

  //? asked as it opens, again when `asks` moves (shown again, a write here) - never while Edit is open
  useEffect(() => {
    if (editingNow.current) return
    const request = requests.begin()
    fetchPlaylist(id, request.signal).then(
      (found) => {
        if (!request.current() || editingNow.current) return
        keepPlaylist(found)
        setAnswer(found)
        setFresh(true)
        setGone(false)
        setRefreshFailed(null)
      },
      (reason: unknown) => {
        if (!request.current() || isAbort(reason)) return
        if (reason instanceof ApiError && reason.status === 404) {
          forgetPlaylist(id)
          setGone(true)
          return
        }
        setRefreshFailed(reason instanceof Error ? reason.message : String(reason))
      },
    )
    return () => requests.supersede()
  }, [id, asks, requests])

  const wasShown = useRef(shown)
  useEffect(() => {
    const before = wasShown.current
    wasShown.current = shown
    if (shown && !before) setAsks((n) => n + 1)
  }, [shown])
  useEffect(() => onPlaylistChanged((changed, now) => {
    if (changed !== id) return
    //? changed here without its answer (an add from the picker - Now Playing's ••• over this page): no Edit from
    //? what is drawn until the ask answers
    if (!now) setFresh(false)
    setAsks((n) => n + 1)
  }), [id])

  const shownPlaylist: Playlist | null = answer?.playlist ?? (preview?.id === id ? preview : null)
  const songs = gone ? [] : answer?.songs ?? []
  //? each song as the queue takes it - its own album, cover and format; one with no album id names none (null)
  const tracks = useMemo(() => (answer ? answer.songs.map((song) => {
    const track = toQueueTrack(song, stubFor(song))
    return song.albumId ? track : { ...track, albumId: null }
  }) : []), [answer])
  const albums = useMemo(() => (answer ? playlistAlbums(answer.songs) : []), [answer])
  const playingId = player.track?.id
  const total = songs.reduce((sum, song) => sum + (song.duration ?? 0), 0)
  const editable = !!answer && !gone && canEdit(answer.playlist, answer.songs.length)
  const canBegin = editable && fresh
  const readOnly = answer && !gone ? readOnlyWords(answer.playlist, answer.songs.length) : null

  //? the albums remembered for these songs, at the tap: an album's own answer held already kept as it is
  const remembered = (stubs: readonly AlbumWithSongs[]) => withHeld(stubs, playedAlbum)
  const play = (start: number | null, shuffle = false) => {
    if (!tracks.length) return
    rememberQueue(remembered(albums))
    player.playTracks(queued(tracks, 'songs'), start, shuffle)
  }

  const songMenu = (event: MouseEvent, index: number) => {
    const song = songs[index]
    const track = tracks[index]
    if (!song || !track || !onQueueMenu) return
    const album = albums.find((each) => each.id === song.albumId)
    onQueueMenu(event, { label: song.title, tracks: [track], albums: album ? remembered([album]) : [] })
  }

  /* ===== Edit ===== */

  useLayoutEffect(() => {
    const wanted = refocus.current
    refocus.current = null
    if (!wanted) return
    if (wanted === 'toggle' || wanted === 'delete') {
      ;(wanted === 'toggle' ? toggle.current : deleteButton.current)?.focus({ preventScroll: true })
      return
    }
    const row = list.current ? [...list.current.querySelectorAll<HTMLElement>('[data-row]')].find((each) => each.dataset.row === wanted.key) : undefined
    const live = (which: string) => row?.querySelector<HTMLButtonElement>(`.app-pin-${which}:not([aria-disabled="true"])`) ?? null
    const target = wanted.which === 'remove'
      ? row?.querySelector<HTMLButtonElement>('.app-pin-remove') ?? toggle.current
      : live(wanted.which) ?? live(wanted.which === 'up' ? 'down' : 'up')
    target?.focus({ preventScroll: true })
  })

  const beginEdit = () => {
    if (!answer || !canBegin) return
    const began = startEdit(answer.songs, answer.playlist)
    setStart(began)
    setEdit(began)
    setEditProblem(null)
    setAsking(null)
    setNote(null)
    setSaid('')
  }
  const leaveEdit = () => {
    if (tried.current) {
      tried.current = null
      setFresh(false)
      setAsks((n) => n + 1)
    }
    setStart(null)
    setEdit(null)
    setAsking(null)
    setEditProblem(null)
    setDeleteProblem(null)
    setDrag(null)
  }
  const blankName = !!edit && !edit.name.trim()
  const done = () => {
    if (!edit || !start || saving) return
    const body = editBody(start, edit)
    if (!body) {
      leaveEdit()
      return
    }
    if (blankName) return
    setSaving(true)
    setEditProblem(null)
    editPlaylist(id, tried.current ? { ...body, tried: tried.current } : body).then(
      (saved) => {
        setSaving(false)
        tried.current = null
        setAnswer(saved)
        setFresh(true)
        leaveEdit()
        announcePlaylistChanged(id, saved)
      },
      (caught: unknown) => {
        setSaving(false)
        if (caught instanceof ApiError && caught.status === 409) {
          //? changed in another app since Edit began: nothing saved - drawn as it is now, and said so
          tried.current = null
          leaveEdit()
          setFresh(false)
          setNote(PLAYLIST_CHANGED)
          setAsks((n) => n + 1)
          //? said where the playlist begins, which is drawn afresh: Done was tapped wherever the rows had got to
          if (typeof window.scrollTo === 'function') window.scrollTo(0, 0)
          return
        }
        if (caught instanceof ApiError && caught.status === 404) {
          tried.current = null
          leaveEdit()
          setGone(true)
          return
        }
        tried.current = body.song_ids
        setEditProblem(caught instanceof Error ? caught.message : String(caught))
      },
    )
  }
  const cancel = () => {
    if (!edit || !start || saving) return
    if (editBody(start, edit)) setAsking('discard')
    else leaveEdit()
  }
  const change = (patch: Partial<EditState>) => setEdit((was) => (was ? { ...was, ...patch } : was))

  const move = (index: number, by: -1 | 1) => {
    if (!edit || saving) return
    const to = index + by
    const row = edit.rows[index]
    if (!row || to < 0 || to >= edit.rows.length) return
    refocus.current = { key: row.key, which: by < 0 ? 'up' : 'down' }
    change({ rows: moveRow(edit.rows, index, to) })
    setSaid(`${row.title}: ${to + 1} of ${edit.rows.length}`)
  }
  const remove = (index: number) => {
    if (!edit || saving) return
    const row = edit.rows[index]
    if (!row) return
    const next = edit.rows[index + 1] ?? edit.rows[index - 1]
    refocus.current = next ? { key: next.key, which: 'remove' } : 'toggle'
    change({ rows: removeRow(edit.rows, index) })
    setSaid(`${row.title} removed`)
  }

  //? the drag: by the grip only, one pointer, the rows' pitch measured as it starts - and the page scrolling itself
  //? while the row is near an edge, the row's distance counting that scroll
  const distance = (held: Drag, clientY: number) => dragDistance(clientY, held.y, window.scrollY, held.scroll)
  const startDrag = (event: PointerEvent, key: string, index: number) => {
    if (dragNow.current || saving || event.button > 0) return
    const grip = event.currentTarget as HTMLElement
    const row = grip.closest('li')
    if (!row) return
    const after = row.nextElementSibling as HTMLElement | null
    const before = row.previousElementSibling as HTMLElement | null
    const pitch = after ? after.offsetTop - row.offsetTop : before ? row.offsetTop - before.offsetTop : row.offsetHeight
    grip.setPointerCapture?.(event.pointerId)
    event.preventDefault()
    const held = { key, start: index, y: event.clientY, clientY: event.clientY, scroll: window.scrollY, dy: 0, pitch, pointer: event.pointerId }
    dragNow.current = held
    setDrag(held)
  }
  const followDrag = (event: PointerEvent) => {
    const held = dragNow.current
    if (!held || event.pointerId !== held.pointer) return
    const next = { ...held, clientY: event.clientY, dy: distance(held, event.clientY) }
    dragNow.current = next
    setDrag(next)
  }
  const endDrag = (event: PointerEvent) => {
    const held = dragNow.current
    if (!held || event.pointerId !== held.pointer || !edit) return
    const to = dropIndex(held.start, distance(held, event.clientY), held.pitch, edit.rows.length)
    dragNow.current = null
    setDrag(null)
    if (to === held.start) return
    const row = edit.rows[held.start]
    change({ rows: moveRow(edit.rows, held.start, to) })
    if (row) setSaid(`${row.title}: ${to + 1} of ${edit.rows.length}`)
  }
  const dropDrag = (event: PointerEvent) => {
    const held = dragNow.current
    if (held && event.pointerId === held.pointer) {
      dragNow.current = null
      setDrag(null)
    }
  }
  const dragging = drag !== null
  useEffect(() => {
    if (!dragging || typeof requestAnimationFrame !== 'function') return
    let frame = 0
    const tick = () => {
      const held = dragNow.current
      if (!held) return
      const top = bar.current?.getBoundingClientRect().bottom ?? 0
      const chrome = [...document.querySelectorAll<HTMLElement>(BOTTOM_CHROME)].map((each) => each.getBoundingClientRect()).filter((box) => box.height > 0)
      const bottom = Math.min(window.innerHeight, ...chrome.map((box) => box.top))
      const step = edgeScroll(held.clientY, top, bottom)
      if (step) {
        window.scrollBy(0, step)
        const next = { ...held, dy: distance(held, held.clientY) }
        dragNow.current = next
        setDrag(next)
      }
      frame = requestAnimationFrame(tick)
    }
    frame = requestAnimationFrame(tick)
    return () => cancelAnimationFrame(frame)
  }, [dragging])

  const removePlaylist = () => {
    if (!shownPlaylist || deleting) return
    const name = shownPlaylist.name
    setDeleting(true)
    setDeleteProblem(null)
    deletePlaylist(id).then(
      () => {
        setDeleting(false)
        forgetPlaylist(id)
        announcePlaylistChanged(id)
        onDeleted(name, id)
      },
      (caught: unknown) => {
        setDeleting(false)
        setDeleteProblem(caught instanceof Error ? caught.message : String(caught))
      },
    )
  }

  const landing = drag && edit ? dropIndex(drag.start, drag.dy, drag.pitch, edit.rows.length) : -1
  const hidden = answer && !gone ? answer.hidden : 0
  const busy = saving || deleting

  return (
    <section class="pl-album-page app-playlist-page">
      <header ref={bar} class="pl-nav-bar app-album-bar app-playlist-bar">
        {editing ? (
          <button type="button" class="app-text-button app-playlist-cancel" aria-disabled={busy} onClick={cancel}>
            Cancel
          </button>
        ) : (
          <button type="button" class="pl-back" onClick={onBack}>
            <ChevronLeftIcon class="pl-back-icon" />
            <span class="pl-back-label">{backLabel}</span>
          </button>
        )}
        {onQueueMenu && (
          <button
            type="button"
            class="app-pin-toggle is-icon app-album-more"
            aria-label="More for this playlist"
            aria-haspopup="dialog"
            aria-disabled={!tracks.length || editing || gone}
            onClick={(event) => {
              if (tracks.length && !editing && !gone && shownPlaylist) onQueueMenu(event as unknown as MouseEvent, { label: shownPlaylist.name, tracks, albums: remembered(albums) })
            }}
          >
            <MoreIcon class="app-pin-icon" />
          </button>
        )}
        {(editable || editing) && (
          <button
            ref={toggle}
            type="button"
            class="app-playlist-chip app-playlist-edit-toggle"
            aria-disabled={editing ? busy || blankName : !canBegin}
            onClick={editing ? done : beginEdit}
          >
            {editing ? (saving ? 'Saving…' : 'Done') : 'Edit'}
          </button>
        )}
        {/* (review) Done's reason and Cancel's question in the bar - it stays in view, wherever the rows have got to */}
        {editing && (editProblem || asking === 'discard') && (
          <div class="app-playlist-ask">
            {editProblem && <p class="app-store-line is-refused app-playlist-bar-line" role="alert">{editProblem}</p>}
            {asking === 'discard' && (
              <ConfirmLine words={DISCARD_QUESTION} confirm="Discard" keep="Keep editing" onConfirm={() => {
                refocus.current = 'toggle'
                leaveEdit()
              }} onKeep={() => {
                refocus.current = 'toggle'
                setAsking(null)
              }} />
            )}
          </div>
        )}
      </header>

      {shownPlaylist && (
        <div class="pl-album-hero">
          {shownPlaylist.coverArt ? (
            <Cover id={shownPlaylist.coverArt} size={800} class="pl-hero-cover" />
          ) : (
            <span class="pl-hero-cover app-playlist-hero-empty" aria-hidden="true">
              <PlaylistIcon class="app-playlist-hero-icon" />
            </span>
          )}
          <h1 class="pl-hero-title">{shownPlaylist.name}</h1>
          <p class="pl-hero-artist app-hero-plain app-playlist-owner">{ownerLine(shownPlaylist)}</p>
          {/* why there is no Edit, under whose it is; then the description - one slot, which a desktop's drawer places */}
          {((readOnly && !editing) || shownPlaylist.comment) && (
            <div class="app-playlist-notes">
              {readOnly && !editing && <p class="app-store-line app-playlist-readonly">{readOnly}</p>}
              {shownPlaylist.comment && <p class="app-playlist-comment">{shownPlaylist.comment}</p>}
            </div>
          )}
          <p class="pl-hero-meta">{answer && !gone ? songsLine(songs.length, total) : ''}</p>

          <div class="pl-hero-actions">
            <button type="button" class="pl-pill is-primary" disabled={!tracks.length || gone || editing} onClick={() => play(0)}>
              <PlayIcon class="pl-pill-icon" />
              Play
            </button>
            <button type="button" class="pl-pill" disabled={!tracks.length || gone || editing} onClick={() => play(null, true)}>
              <ShuffleIcon class="pl-pill-icon" />
              Shuffle
            </button>
          </div>
        </div>
      )}

      {hidden > 0 && !editing && <p class="app-store-line app-playlist-line">{hiddenWords(hidden)}</p>}
      {refreshFailed && !gone && answer && <p class="app-store-line is-refused app-playlist-line">{`Couldn't ask Navidrome for it again: ${refreshFailed}`}</p>}
      {note && !editing && <p class="app-store-line app-playlist-line" role="status">{note}</p>}
      {/* what an Edit changed, read out - always in the page, as iOS reads only a region already there */}
      <p class="app-visually-hidden" role="status" aria-live="polite" aria-atomic="true">{said}</p>

      {gone ? (
        <p class="pl-notice app-playlist-gone">{PLAYLIST_GONE}</p>
      ) : !answer ? (
        refreshFailed ? (
          //? (review) nothing in hand and the first ask failed: why, and Try again - never an empty page saying "again"
          <div class="pl-notice app-playlist-failed">
            <p>{`Couldn't open this playlist: ${refreshFailed}`}</p>
            <button type="button" class="pl-text-button" onClick={() => {
              setRefreshFailed(null)
              setAsks((n) => n + 1)
            }}>
              Try again
            </button>
          </div>
        ) : (
          <div class="pl-spinner" aria-label="Loading" />
        )
      ) : edit ? (
        <div class="app-playlist-editing">
          <label class="app-playlist-field">
            <span class="app-playlist-field-label">Name</span>
            <input
              class="app-playlist-input"
              type="text"
              value={edit.name}
              maxLength={PLAYLIST_NAME_MAX}
              autoCapitalize="sentences"
              autoComplete="off"
              aria-invalid={blankName}
              onInput={(event) => change({ name: (event.currentTarget as HTMLInputElement).value })}
            />
          </label>
          {blankName && <p class="app-store-line is-refused">{NEEDS_A_NAME}</p>}
          <label class="app-playlist-field">
            <span class="app-playlist-field-label">Description</span>
            <textarea
              class="app-playlist-input app-playlist-textarea"
              rows={2}
              value={edit.comment}
              maxLength={PLAYLIST_COMMENT_MAX}
              onInput={(event) => change({ comment: (event.currentTarget as HTMLTextAreaElement).value })}
            />
          </label>
          <div class="app-group app-playlist-share">
            <button
              type="button"
              role="checkbox"
              class="app-check-row"
              aria-checked={edit.public}
              aria-describedby="app-playlist-share-note"
              onClick={() => change({ public: !edit.public })}
            >
              <span class="app-check-label">Shared with everyone</span>
              <span class={`app-checkbox${edit.public ? ' is-on' : ''}`} aria-hidden="true">
                <CheckIcon class="app-checkbox-tick" />
              </span>
            </button>
          </div>
          <p id="app-playlist-share-note" class="app-store-line is-detail app-playlist-share-note">{SHARED_NOTE}</p>
          {hidden > 0 && <p class="app-store-line app-playlist-line">{hiddenEditWords(hidden)}</p>}

          <ol ref={list} class="app-playlist-edit">
            {edit.rows.map((row, index) => {
              const offset = drag ? dragOffset(index, drag.start, landing, drag.dy, drag.pitch) : 0
              return (
                <li
                  key={row.key}
                  data-row={row.key}
                  class={`app-pin-row app-card app-playlist-edit-row${drag?.key === row.key ? ' is-dragging' : ''}`}
                  style={offset ? { transform: `translateY(${offset}px)` } : undefined}
                >
                  <span class="app-pin-text">
                    <span class="app-pin-title">{row.title}</span>
                    <span class="app-pin-line">{row.artist}</span>
                  </span>
                  <button type="button" class="app-pin-move app-pin-up" aria-label={`Move ${row.title} up`} aria-disabled={index === 0 || saving} onClick={() => move(index, -1)}>
                    <span class="app-pin-move-face">
                      <ChevronUpIcon class="app-pin-move-icon" />
                    </span>
                  </button>
                  <button
                    type="button"
                    class="app-pin-move app-pin-down"
                    aria-label={`Move ${row.title} down`}
                    aria-disabled={index === edit.rows.length - 1 || saving}
                    onClick={() => move(index, 1)}
                  >
                    <span class="app-pin-move-face">
                      <ChevronDownIcon class="app-pin-move-icon" />
                    </span>
                  </button>
                  <button type="button" class="app-pin-move app-pin-remove" aria-label={`Remove ${row.title}`} aria-disabled={saving} onClick={() => remove(index)}>
                    <span class="app-pin-move-face">
                      <CloseIcon class="app-pin-move-icon" />
                    </span>
                  </button>
                  <span
                    class="app-pin-grip"
                    aria-hidden="true"
                    onPointerDown={(event) => startDrag(event, row.key, index)}
                    onPointerMove={followDrag}
                    onPointerUp={endDrag}
                    onPointerCancel={dropDrag}
                    onLostPointerCapture={dropDrag}
                  >
                    <GripIcon class="app-pin-grip-icon" />
                  </span>
                </li>
              )
            })}
          </ol>

          {asking === 'delete' ? (
            <ConfirmLine
              words={deleteQuestion(edit.name.trim() || shownPlaylist?.name || '')}
              confirm="Delete playlist"
              keep="Keep it"
              danger
              busy={deleting}
              busyLabel="Deleting…"
              problem={deleteProblem}
              onConfirm={removePlaylist}
              onKeep={() => {
                refocus.current = 'delete'
                setAsking(null)
              }}
            />
          ) : (
            <button ref={deleteButton} type="button" class="app-text-button is-danger app-playlist-delete" aria-disabled={busy} onClick={() => {
              if (!busy) setAsking('delete')
            }}>
              Delete playlist
            </button>
          )}
        </div>
      ) : !songs.length ? (
        <p class="pl-notice app-playlist-empty">{PLAYLIST_EMPTY}</p>
      ) : (
        <ol class="pl-tracks app-playlist-tracks">
          {songs.map((song, index) => {
            const isCurrent = playingId === song.id
            return (
              <li key={`${index}:${song.id}`} class="app-track-row">
                <button type="button" class={`pl-track app-playlist-track${isCurrent ? ' is-current' : ''}`} onClick={() => play(index)}>
                  <span class="app-playlist-track-art">
                    <Cover id={song.coverArt} size={96} class="app-playlist-track-cover" />
                    {isCurrent && (
                      <span class="app-playlist-track-bars">
                        <PlayingBars paused={!player.playing} />
                      </span>
                    )}
                  </span>
                  <span class="pl-track-text">
                    <span class="pl-track-title">{song.title}</span>
                    <span class="pl-track-artist">{[song.artist, song.album].filter(Boolean).join(' · ')}</span>
                  </span>
                  <span class="pl-track-time">{trackTime(song.duration)}</span>
                </button>
                {onQueueMenu && (
                  <button
                    type="button"
                    class="app-row-more"
                    aria-label={`More for ${song.title}`}
                    aria-haspopup="dialog"
                    onClick={(event) => songMenu(event as unknown as MouseEvent, index)}
                  >
                    <MoreIcon class="app-row-more-icon" />
                  </button>
                )}
              </li>
            )
          })}
        </ol>
      )}

      {answer && !gone && !editing && songs.length > 0 && <p class="pl-album-footer">{songsLine(songs.length, total)}</p>}
    </section>
  )
}
