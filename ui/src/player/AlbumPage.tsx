import { Fragment } from 'preact'
import { useEffect, useMemo, useRef, useState } from 'preact/hooks'

import { addToMyLibrary, removeFromMyLibrary } from '../api/me'
import { storeAlbum } from '../api/store'
import type { StoreAlbumResponse } from '../api/types'
import type { ViewerImage } from '../components/ArtViewer'
import { AlbumProperties } from '../app/AlbumProperties'
import { CoverViewer } from '../app/CoverViewer'
import { pinsUnsaved, PinToggle } from '../app/PinToggle'
import { keepJoinFocus } from '../app/StoreState'
import { hasLibrary } from '../app/useMyLibrary'
import { takeOpener } from '../app/useSheet'
import { sayPins, setPinned, usePins } from '../app/usePins'
import { discHeadings } from '../lib/discTitles'
import { formatDuration, sharedFormat, trackTime } from '../lib/format'
import { editAlbum, type EditAlbum } from '../lib/albumEdit'
import { albumEdit } from '../lib/permissions'
import { albumProperties } from '../lib/albumProperties'
import { alsoChips, otherPressingsGroup } from '../lib/idBridge'
import { isAbort, latestOnly } from '../lib/latest'
import { announceAddedToLibrary, announceRemovedFromLibrary } from '../lib/libraryEvents'
import { pinOf, type AlbumPinTarget } from '../lib/pins'
import type { QueuePick } from '../lib/upNext'
import { ADD_FROM_PAGE, albumMine } from '../lib/whose'
import { album as fetchAlbum, coverFullUrl, coverUrl, prefetchAlbum, rememberPlayed, toQueueTrack, type Album, type AlbumWithSongs } from './api'
import { CheckIcon, ChevronLeftIcon, ChevronRightIcon, MoreIcon, PlayIcon, PlayingBars, ShuffleIcon } from './icons'
import { Cover } from './Cover'
import { queued, warmAlbum } from './levelling'
import type { Player } from './usePlayer'
import { accessNow, seesDetail, useAccess } from '../app/access'
import { errorNote } from '../app/ErrorNote'
import { heroTitleClass } from '../lib/titles'
import { DESCRIPTION_WAIT_MS, inBlock } from '../lib/describe'
import { DescriptionBlock } from '../app/Description'
import { useDescription } from '../app/useDescription'

/**
 * One album: its cover, Play and Shuffle, and its songs.
 *
 * Drawn from the grid's copy of the album straight away, so the cover and title are on screen
 * while the song list is still on its way. Only the newest request counts (lib/latest.ts), and
 * leaving the album calls its request off rather than letting it run on beside the music.
 *
 * Pushed on whichever tab opened it (lib/appRoutes.ts), so the back button says where it goes:
 * `backLabel` is the page below: the tab ("Home", "Library") when it was opened from a tile, and
 * the album below's own name when Go to album (Now Playing, since 2.0.0-player.10) opened this one
 * over another album page - which can be this same album, lower down; the router keeps the two
 * copies apart going back and forward (lib/appRoutes.ts, `forwardTo`).
 * Disc headings come from Navidrome's own `discTitles` (lib/discTitles.ts): "Disc 4 · <title>".
 *
 * Play remembers the album's answer for Info (rememberPlayed - the queue's songs carry only what
 * playing needs) and then calls the player, both in the tap: nothing is awaited between them.
 *
 * Since 2.0.0-player.17 the artist's name is a link to their page (Navidrome's album artist - the
 * artist the album is filed under), and under the meta line, where Album.dc.html draws it, a row
 * says "In your library" with an "Also: <edition> ›" chip for each other pressing of the album you
 * hold that Navidrome has - the id bridge (GET /store/album, asked as the page opens, through its
 * own latestOnly) says which. The row is drawn from the first frame, so a chip arriving moves
 * nothing a finger is reaching for; a chip opens that pressing's page over this one.
 *
 * Since 2.0.0-player.41 the row ends with "Pressings ›" (2.0.5's one name) once the bridge says which MusicBrainz
 * album this is (the release group its folders carry): the album you don't have's page for it, over
 * this one - every pressing in its list, the ones you hold marked, Get on any - so the deluxe beside
 * the standard you have can be got (v0.9.1's ask). It lands with the Also chips, in the row drawn from
 * the first frame, and never gives way to them: they shorten, it doesn't. The row is unseen until the
 * bridge has answered (or failed) - its place held, so nothing below moves - and so what is in it,
 * the badge too, first shows where it stays: a phone's row is centred, and the badge slid sideways as
 * the chip landed. Beside an Also chip, in a row too narrow for all three whole (its own width, by a
 * container query - a phone, or a desktop's column narrowed by the Edit panel), the Also chip gives way.
 * (2.0.5, UX batch 2) The chip is "Pressings ›" on every frame (it was "Other pressings" with room), and the
 * badge is a badge (app.css), keeping its words - in a narrow row it had left a bare tick in a box.
 *
 * Since 2.0.0-player.18 the bar's top right has the pin (Album.dc.html's): it pins the album to Home
 * by its release - the bridge's answer says which - and deadwax keys the pin on the store's row for
 * it, so it follows the album through a re-file. Drawn from the first frame, waiting until the bridge
 * has answered and the pins have (so it never says "not pinned" of an album that is); an album with no
 * release id to know it by has none (nothing would find it again).
 * Whether it is pinned comes from the app's one store of pins (app/usePins.ts), asked when none is
 * in hand or what is is old.
 *
 * Since 2.0.0-player.21, on a desktop and for an admin, Edit after Play and Shuffle (DesktopManage.dc.html:
 * a toggle, pressed while the Edit panel shows this album) - App's `onEdit`, handed the album as
 * Navidrome sent it, which is what the panel finds its folder by. Since 2.0.0-player.47 a phone has it too
 * (the Edit panel a sheet over the whole screen there): in the bar, beside the pin (`editAt` 'bar') - above
 * the title, so nothing under it moves whether or not it is drawn, and in reach from anywhere down the
 * page, the bar being sticky. Live once the album has answered. After an edit App asks the page again (`refresh`): the album
 * and the bridge are asked afresh and what is drawn stays until they answer - a refresh that fails
 * keeps it, since the album may be under a new id Navidrome hasn't scanned yet (App moves the page to
 * it once found).
 *
 * Since 2.0.0-player.44, on both frames: the cover opens full size in the cover viewer (app/CoverViewer.tsx,
 * the main page's ArtViewer - it only reads), Navidrome's own picture unresized; and at the foot, under the
 * songs, the album's Properties (app/AlbumProperties.tsx, lib/albumProperties.ts) - its year against this
 * pressing's, its size, its release on musicbrainz.org (opening beside the app) and when deadwax first saw
 * it - from the bridge's answer the page asks already, drawn once it has answered.
 *
 * Since 2.0.0-player.52 (step 6 of the multi-user plan), with logins on and a library of your own, "In your
 * library" means YOURS (lib/whose.ts albumMine): an album Navidrome has is in the store, always - it says "In
 * your library" when you starred it (Navidrome's `starred`, asked as you) or your library holds it (the
 * bridge's `yours`), with Remove from my library under Play; else "In the store", with Add to my library (or a
 * line saying why it can't be added). Each asks deadwax at once from its tap, waits (aria-disabled, so the
 * focus stays), and gives way to what happened, handing its focus to the line; a refusal is said in an alert.
 * Remove deletes nothing - its words say so - and asks for no confirmation: Add undoes it, and for an album
 * Add can't put back (no release id, or a folder deadwax hasn't found) the line after it says how to have it
 * back - star it in Amperfy (review). Whose it is waits for the album's own answer (its `starred`, never a
 * list's tile) and the bridge's; until both are in, the chips row is unseen and the line under Play holds
 * its place (review). With logins off, and for the break-glass admin, the badge reads "In your library" as
 * it always did and nothing is offered.
 *
 * Since 2.0.13 the album's DESCRIPTION (app/useDescription.ts, app/Description.tsx) - Wikidata's one-line subtitle
 * and Navidrome's or Wikipedia's paragraph - asked once the bridge has answered for this album (on a page come back
 * to, the answer it had is drawn from its first frame): under the hero when it is in hand as the songs are drawn -
 * they wait for it DESCRIPTION_WAIT_MS at most - else at the foot, above Properties (lib/describe.ts placeOf).
 *
 * Since 2.0.0-player.57 (Up Next, shuffle and repeat) every song's row ends with a ••• and the bar has one for
 * the whole album, between the phone's Edit and the pin - each opening the song menu (App's QueueMenu: Play
 * Next, Play Last) through `onQueueMenu`, with the songs in hand: the album's ••• is aria-disabled until they
 * are. This page names no Up Next action - the menu plays them, in its tap.
 */
/** (2.0.4) An album page whose album Navidrome no longer has (a 404). */
export const ALBUM_GONE = "This album isn't here any more - it may have been moved or deleted."

/** (2.0.5) The chip to every pressing of the album - one name, on a phone and a desktop alike. */
export const PRESSINGS = 'Pressings'

export function AlbumPage({
  id,
  preview,
  player,
  onBack,
  backLabel,
  onArtist,
  onOpenAlbum,
  onOpenGroup,
  onEdit,
  editAt = 'actions',
  editing = false,
  refresh = 0,
  onQueueMenu,
}: {
  id: string
  preview: Album | null
  player: Player
  onBack: () => void
  backLabel: string
  /** the artist's page, by Navidrome's id for them (2.0.0-player.17) */
  onArtist?: (artist: { id: string; name: string }) => void
  /** another pressing's page, from its "Also" chip */
  onOpenAlbum?: (album: Album) => void
  /** the album's MusicBrainz group, from "Other pressings" (2.0.0-player.41): every pressing, to get one */
  onOpenGroup?: (group: { id: string; title: string }) => void
  /** Edit, for an admin (2.0.0-player.21; a phone's too since 2.0.0-player.47): the Edit panel for this album, or closed */
  onEdit?: ((event: MouseEvent, album: EditAlbum) => void) | undefined
  /** where Edit is drawn: after Play and Shuffle (a desktop's), or in the bar beside the pin (a phone's) */
  editAt?: 'actions' | 'bar'
  /** the Edit panel shows this album: Edit pressed */
  editing?: boolean
  /** asked again after an edit: a new number each time */
  refresh?: number
  /** (2.0.0-player.57) a song's or the album's •••: the song menu (Play Next, Play Last), the songs in hand */
  onQueueMenu?: ((event: MouseEvent, pick: QueuePick<AlbumWithSongs>) => void) | undefined
}) {
  const [album, setAlbum] = useState<AlbumWithSongs | null>(null)
  //? (2.0.4) the errors themselves, said by errorNote (app/ErrorNote.tsx) in a listener's words
  const [error, setError] = useState<unknown>(null)
  const requests = useMemo(latestOnly, [])
  //? what the store holds of this album, and its other pressings - the id bridge
  const [store, setStore] = useState<StoreAlbumResponse | null>(null)
  //? (2.0.5) Properties' no-release line is for whoever can Edit albums (lib/albumProperties.ts)
  const access = useAccess()
  //? the bridge failed to answer - so, answered or not, whether the album can be pinned is known
  const [storeFailed, setStoreFailed] = useState(false)
  //? (2.0.13) which album the bridge last answered (or failed) for - the description is asked by THIS album's ids
  const [storeFor, setStoreFor] = useState<string | null>(null)
  const storeRequests = useMemo(latestOnly, [])
  const { pins, known: pinsKnown, canSave } = usePins(true)
  //? the cover, full size (2.0.0-player.44), and the control that opened it - focus goes back there
  const [viewing, setViewing] = useState<ViewerImage[] | null>(null)
  const viewOpener = useRef<HTMLElement | null>(null)
  //? (2.0.0-player.52) Add to my library / Remove from my library: what this page just did, the ask out, a refusal
  const [changed, setChanged] = useState<'added' | 'removed' | null>(null)
  const [mineBusy, setMineBusy] = useState(false)
  const [mineRefused, setMineRefused] = useState<unknown>(null)
  const mineButton = useRef<HTMLButtonElement | null>(null)

  //? the refresh last asked for: a new one is an edit's (2.0.0-player.21), asked afresh and drawn over
  //? what is on screen rather than blanking it
  const asked = useRef(refresh)

  useEffect(() => {
    const request = requests.begin()
    const again = asked.current !== refresh
    if (!again) {
      setAlbum(null)
      setError(null)
    }
    //? an edit's ask goes to Navidrome whatever was fetched ahead (prefetchAlbum's `fresh`)
    const answer = again ? prefetchAlbum(id, false, true).then(() => fetchAlbum(id, request.signal)) : fetchAlbum(id, request.signal)
    answer.then(
      (found) => {
        if (request.current()) setAlbum(found)
      },
      (reason: unknown) => {
        if (!request.current() || isAbort(reason) || again) return
        setError(reason)
      },
    )
    return () => requests.supersede()
  }, [id, refresh, requests])

  useEffect(() => {
    const request = storeRequests.begin()
    const again = asked.current !== refresh
    asked.current = refresh
    if (!again) {
      setStore(null)
      setStoreFailed(false)
    }
    //? another album, or this one asked afresh: what the page last did is told by deadwax's answer now
    setChanged(null)
    setMineRefused(null)
    storeAlbum({ navidrome_id: id }, request.signal).then(
      (answer) => {
        if (!request.current()) return
        setStore(answer)
        setStoreFor(id)
      },
      (reason: unknown) => {
        if (!request.current() || isAbort(reason)) return
        setStoreFor(id)
        //? a check that can't be made draws no chip - and no pin, with no release to pin it by
        if (!again) setStoreFailed(true)
      },
    )
    return () => storeRequests.supersede()
  }, [id, refresh, storeRequests])

  //? (2.0.0-player.62, Normalization's Part A) the album about to be played: once its songs are in hand, deadwax
  //? is asked to measure them ahead (fire and forget - not a playback action), so a first levelled play waits less.
  //? Not under Off, and not for an album with no FLAC song, which nothing levels
  useEffect(() => {
    if (album) warmAlbum(album)
  }, [album?.id])

  //? (2.0.13) the album's description - asked once the bridge has said which MusicBrainz album this is (its release
  //? group: Wikipedia's words), with Navidrome's id beside it (Navidrome's own). Under the hero when it is in hand as
  //? the songs are drawn - they wait for it DESCRIPTION_WAIT_MS at most - else at the page's foot, so a late one
  //? moves no song under a finger. Once drawn, the songs stay drawn (an edit's refresh keeps them)
  const songsDrawn = useRef<string | null>(null)
  const describing = useDescription('album', storeFor === id
    ? { mbid: store?.release_group_mbid ?? null, navidromeId: id } : null, songsDrawn.current === id, id)
  const [songsWaited, setSongsWaited] = useState<string | null>(null)
  useEffect(() => {
    if (!album) return
    const timer = setTimeout(() => setSongsWaited(id), DESCRIPTION_WAIT_MS)
    return () => clearTimeout(timer)
  }, [id, !!album])
  if (album && (describing.settled || songsWaited === id)) songsDrawn.current = id
  const drawSongs = !!album && songsDrawn.current === id
  //? its subtitle and paragraph, together - an album's hero holds Play and the chips from its first frame, so the
  //? subtitle heads the block rather than landing in the hero above them
  const describedBlock = inBlock('album', describing.description)

  const shown: Album | null = album ?? (preview?.id === id ? preview : null)
  //? what Navidrome has said of the album's release, for Properties' "not tagged" (review - never the
  //? bridge's null alone, which is also its answer for an id Navidrome doesn't have): the album's own
  //? answer's `musicBrainzId`, '' when that answer came without one (Navidrome 0.64.2 always sends it, ''
  //? for none; a server leaving it out has still answered for the album), a list's preview's until then
  const releaseSaid = album ? album.musicBrainzId ?? '' : shown?.musicBrainzId
  const songs = album?.song ?? []
  const tracks = useMemo(() => (album ? songs.map((song) => toQueueTrack(song, album)) : []), [album])
  const headings = discHeadings(songs, album?.discTitles)
  const format = sharedFormat(songs)
  const total = songs.reduce((sum, song) => sum + (song.duration ?? 0), 0)

  const chips = alsoChips(store, id)
  const group = otherPressingsGroup(store)
  const artistId = shown?.artistId ?? album?.artistId
  const artistName = shown?.artist ?? ''

  //? the pin: this album by its release, as the bridge has it - Navidrome's id while that is coming
  const release = store?.release_mbid ?? null
  const storeDone = store !== null || storeFailed
  const pinTarget: AlbumPinTarget = {
    kind: 'album', release_mbid: release, navidrome_id: id, label: shown?.name ?? '', sub: artistName, cover: shown?.coverArt ?? null,
  }
  const pinned = pinOf(pins, pinTarget) !== null

  //? (2.0.0-player.52) whose it is - yours, or the store's - and what is offered. Starred by the album's OWN
  //? answer, never a list's tile (review: one kept from before a Remove offered Remove again) - unknown until
  //? it comes, or false once it has failed (the page says so; Add is harmless if it was starred after all)
  const mine = albumMine({
    personal: hasLibrary(),
    starred: album ? !!album.starred : error ? false : null,
    storeDone,
    bridgeFailed: storeFailed,
    bridgeYours: store?.yours,
    present: store?.present.length ?? 0,
    release,
    releaseSaid: album ? album.musicBrainzId ?? '' : null,
    changed,
  })

  const changeMine = (action: 'add' | 'remove') => {
    if (mineBusy) return
    setMineBusy(true)
    setMineRefused(null)
    const first = store?.present[0]
    const asked = action === 'add'
      ? addToMyLibrary({
        artist: first?.artist || artistName, album_artist: first?.artist || artistName, artist_mbids: [],
        album: first?.album || shown?.name || '', year: first?.year || null, original_year: null, release_mbid: release,
        edition_tags: [], tracks: [], release_group_mbid: store?.release_group_mbid ?? null,
      })
      : removeFromMyLibrary(id)
    asked.then(
      () => {
        keepJoinFocus(mineButton.current, '.app-album-mine')
        setMineBusy(false)
        setChanged(action === 'add' ? 'added' : 'removed')
        if (action === 'add') announceAddedToLibrary()
        else announceRemovedFromLibrary()
      },
      (caught: unknown) => {
        setMineBusy(false)
        setMineRefused(caught)
      },
    )
  }

  const play = (start: number | null, shuffle = false) => {
    if (!album || !tracks.length) return
    rememberPlayed(album)
    player.playTracks(queued(tracks, 'album'), start, shuffle)
  }

  return (
    <section class="pl-album-page">
      <header class="pl-nav-bar app-album-bar">
        <button type="button" class="pl-back" onClick={onBack}>
          <ChevronLeftIcon class="pl-back-icon" />
          <span class="pl-back-label">{backLabel}</span>
        </button>
        {/* a phone's Edit (2.0.0-player.47): in the bar, so nothing under the title moves as it comes or goes */}
        {onEdit && editAt === 'bar' && (
          <button
            type="button"
            class="app-edit-toggle app-edit-chip"
            aria-pressed={editing}
            disabled={!album}
            onClick={(event) => {
              if (album) onEdit(event as unknown as MouseEvent, editAlbum(album))
            }}
          >
            Edit
          </button>
        )}
        {/* (2.0.0-player.57) the whole album's Play Next and Play Last - live once its songs are in hand */}
        {onQueueMenu && (
          <button
            type="button"
            class="app-pin-toggle is-icon app-album-more"
            aria-label="More for this album"
            aria-haspopup="dialog"
            aria-disabled={!album || !tracks.length}
            onClick={(event) => {
              if (album && tracks.length) onQueueMenu(event as unknown as MouseEvent, { label: album.name, tracks, albums: [album], as: 'album' })
            }}
          >
            <MoreIcon class="app-pin-icon" />
          </button>
        )}
        {!(storeDone && !release) && (
          <PinToggle
            look="icon"
            pinned={pinned}
            ready={storeDone && !!release && pinsKnown}
            unsaved={!canSave}
            onToggle={() => void setPinned(pinTarget, !pinned)}
            onRefused={() => sayPins(pinsUnsaved(seesDetail(accessNow())))}
          />
        )}
      </header>

      <div class="pl-album-hero">
        {shown?.coverArt ? (
          //? the hero's cover is the button (its class, so it sits where the cover sits on both frames),
          //? the picture filling it
          <button
            type="button"
            class="pl-hero-cover app-cover-open"
            aria-label="See the cover full size"
            onClick={(event) => {
              viewOpener.current = takeOpener(event)
              setViewing([{
                label: shown.name ?? '',
                sources: [coverFullUrl(shown.coverArt), coverUrl(shown.coverArt, 800)].filter((source): source is string => !!source),
                missing: 'No cover for this album',
              }])
            }}
          >
            <Cover id={shown.coverArt} size={800} class="app-cover-open-img" />
          </button>
        ) : (
          <Cover id={shown?.coverArt} size={800} class="pl-hero-cover" />
        )}
        <h1 class={heroTitleClass(shown?.name)} dir="auto">{shown?.name ?? ''}</h1>
        {artistId && artistName && onArtist ? (
          <button type="button" class="pl-hero-artist app-hero-link" dir="auto" onClick={() => onArtist({ id: artistId, name: artistName })}>
            {artistName}
          </button>
        ) : (
          //? not a link: drawn plain once the album has said it names no artist to go to - never while
          //? it might still be one, which would flash from grey to the link's colour
          <p class={`pl-hero-artist${album ? ' app-hero-plain' : ''}`} dir="auto">{artistName}</p>
        )}
        <p class="pl-hero-meta">
          {[shown?.genre, shown?.year, format].filter(Boolean).join(' · ')}
        </p>

        {/* drawn from the first frame: an "Also" chip landing in it moves nothing below. Unseen until the
            bridge has answered or failed (2.0.0-player.41), so "In your library" first shows where it
            stays - on a phone's centred row it slid sideways as "Other pressings" landed beside it */}
        <div class={`app-album-chips${storeDone && !mine.pending ? '' : ' is-waiting'}`}>
          <span class={`app-held-badge${mine.yours === true ? '' : ' is-store'}`}>
            {mine.yours === true && <CheckIcon class="app-held-badge-icon" />}
            <span class="app-held-badge-text">{mine.badge}</span>
          </span>
          {chips.map((chip) => (
            <button
              key={chip.navidromeId}
              type="button"
              class="app-chip app-also"
              onClick={() => onOpenAlbum?.({ id: chip.navidromeId, name: shown?.name ?? '', ...(artistName ? { artist: artistName } : {}) })}
            >
              <span class="app-also-label">{chip.label}</span>
              <ChevronRightIcon class="app-chip-icon" />
            </button>
          ))}
          {/* every pressing of the album, to get another (2.0.0-player.41) - last, and never shortened */}
          {group && onOpenGroup && (
            <button
              type="button"
              class="app-chip app-other-pressings"
              onClick={() => onOpenGroup({ id: group, title: shown?.name ?? '' })}
            >
              {/* (2.0.5) one name on every frame - it was "Other pressings" where there was room, "Pressings" where
                  not; the page it opens lists every pressing, this one too, as the picker's own "Pressings" does */}
              {PRESSINGS}
              <ChevronRightIcon class="app-chip-icon" />
            </button>
          )}
        </div>

        <div class="pl-hero-actions">
          <button type="button" class="pl-pill is-primary" disabled={!tracks.length} onClick={() => play(0)}>
            <PlayIcon class="pl-pill-icon" />
            Play
          </button>
          <button type="button" class="pl-pill" disabled={!tracks.length} onClick={() => play(null, true)}>
            <ShuffleIcon class="pl-pill-icon" />
            Shuffle
          </button>
          {/* a desktop's, for an admin (2.0.0-player.21): the Edit panel beside the page */}
          {onEdit && editAt === 'actions' && (
            <button
              type="button"
              class="pl-pill app-edit-toggle"
              aria-pressed={editing}
              disabled={!album}
              onClick={(event) => {
                if (album) onEdit(event as unknown as MouseEvent, editAlbum(album))
              }}
            >
              Edit
            </button>
          )}
        </div>
      </div>

      {/* (2.0.0-player.52) yours or the store's: Add to my library, or Remove from it - logins on only. While
          whose it is is still to come and the songs are drawn, the line and Add most likely to land hold
          their place, unseen (review: landing late, they pushed the songs down under a finger) */}
      {mine.pending && album && !mineRefused && (
        <div class="app-album-mine is-waiting" aria-hidden="true">
          <p class="app-store-line">{ADD_FROM_PAGE}</p>
          <button type="button" class="app-button app-album-mine-button" tabIndex={-1}>
            Add to my library
          </button>
        </div>
      )}
      {(mine.action || mine.note || !!mineRefused) && (
        <div class="app-album-mine" tabIndex={-1}>
          {mine.note && (
            <p class="app-store-line" role="status">
              {mine.note}
            </p>
          )}
          {mine.action && (
            <button
              ref={mineButton}
              type="button"
              class={mine.action === 'remove' ? 'app-text-button app-album-mine-button' : 'app-button app-album-mine-button'}
              aria-disabled={mineBusy}
              onClick={() => changeMine(mine.action!)}
            >
              {mine.action === 'add' ? (mineBusy ? 'Adding…' : 'Add to my library') : mineBusy ? 'Removing…' : 'Remove from my library'}
            </button>
          )}
          {!!mineRefused && (
            <p class="app-store-line is-refused" role="alert">
              {errorNote(mineRefused, { as: 'span' })}
            </p>
          )}
        </div>
      )}

      {describedBlock && describing.at === 'top' && <DescriptionBlock description={describedBlock} at="top" />}

      {error ? errorNote(error, { class: 'pl-notice', gone: ALBUM_GONE }) : null}
      {!drawSongs && !error && <div class="pl-spinner" aria-label="Loading" />}

      <ol class="pl-tracks">
        {(drawSongs ? songs : []).map((song, index) => {
          const isCurrent = player.track?.id === song.id
          const heading = headings[index]
          const showArtist = song.artist && song.artist !== shown?.artist
          return (
            <Fragment key={song.id}>
              {heading && <li class="pl-disc">{heading}</li>}
              <li class={onQueueMenu ? 'app-track-row' : undefined}>
                <button
                  type="button"
                  class={`pl-track${isCurrent ? ' is-current' : ''}`}
                  onClick={() => play(index)}
                >
                  <span class="pl-track-number">
                    {isCurrent ? <PlayingBars paused={!player.playing} /> : song.track ?? ''}
                  </span>
                  <span class="pl-track-text">
                    <span class="pl-track-title" dir="auto">{song.title}</span>
                    {showArtist && <span class="pl-track-artist" dir="auto">{song.artist}</span>}
                  </span>
                  <span class="pl-track-time">{trackTime(song.duration)}</span>
                </button>
                {/* (2.0.0-player.57) this song's Play Next and Play Last */}
                {onQueueMenu && album && (
                  <button
                    type="button"
                    class="app-row-more"
                    aria-label={`More for ${song.title}`}
                    aria-haspopup="dialog"
                    onClick={(event) => onQueueMenu(event as unknown as MouseEvent, { label: song.title, tracks: [toQueueTrack(song, album)], albums: [album] })}
                  >
                    <MoreIcon class="app-row-more-icon" />
                  </button>
                )}
              </li>
            </Fragment>
          )
        })}
      </ol>

      {drawSongs && album && (
        <p class="pl-album-footer">
          {songs.length} {songs.length === 1 ? 'song' : 'songs'}
          {total ? `, ${formatDuration(total)}` : ''}
        </p>
      )}

      {/* (2.0.13) a description that came after the songs were drawn: here, where it moves nothing under a finger */}
      {describedBlock && describing.at === 'foot' && <DescriptionBlock description={describedBlock} at="foot" />}

      {/* what the main page's details pane said of the album (2.0.0-player.44), once the bridge has answered */}
      <AlbumProperties rows={albumProperties(store, storeFailed, releaseSaid, undefined, albumEdit(access.permissions).editors)} />

      <CoverViewer images={viewing} onClose={() => setViewing(null)} opener={viewOpener} />
    </section>
  )
}
