import { Fragment } from 'preact'
import { useEffect, useMemo, useRef, useState } from 'preact/hooks'

import { storeAlbum } from '../api/store'
import type { StoreAlbumResponse } from '../api/types'
import type { ViewerImage } from '../components/ArtViewer'
import { AlbumProperties } from '../app/AlbumProperties'
import { CoverViewer } from '../app/CoverViewer'
import { PINS_UNSAVED, PinToggle } from '../app/PinToggle'
import { takeOpener } from '../app/useSheet'
import { sayPins, setPinned, usePins } from '../app/usePins'
import { discHeadings } from '../lib/discTitles'
import { formatDuration, sharedFormat, trackTime } from '../lib/format'
import { editAlbum, type EditAlbum } from '../lib/albumEdit'
import { albumProperties } from '../lib/albumProperties'
import { alsoChips, otherPressingsGroup } from '../lib/idBridge'
import { isAbort, latestOnly } from '../lib/latest'
import { pinOf, type AlbumPinTarget } from '../lib/pins'
import { album as fetchAlbum, coverFullUrl, coverUrl, prefetchAlbum, rememberPlayed, toQueueTrack, type Album, type AlbumWithSongs } from './api'
import { CheckIcon, ChevronLeftIcon, ChevronRightIcon, PlayIcon, PlayingBars, ShuffleIcon } from './icons'
import { Cover } from './Cover'
import type { Player } from './usePlayer'

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
 * Since 2.0.0-player.41 the row ends with "Other pressings ›" once the bridge says which MusicBrainz
 * album this is (the release group its folders carry): the album you don't have's page for it, over
 * this one - every pressing in its list, the ones you hold marked, Get on any - so the deluxe beside
 * the standard you have can be got (v0.9.1's ask). It lands with the Also chips, in the row drawn from
 * the first frame, and never gives way to them: they shorten, it doesn't. The row is unseen until the
 * bridge has answered (or failed) - its place held, so nothing below moves - and so what is in it,
 * the badge too, first shows where it stays: a phone's row is centred, and the badge slid sideways as
 * the chip landed. Beside an Also chip, in a row too narrow for all three whole (its own width, by a
 * container query - a phone, or a desktop's column narrowed by the Edit panel), it says "Pressings"
 * (its name still "Other pressings") and "In your library" keeps its green tick and gives its words
 * up (still read, never shown), leaving the Also chip room to say which pressing it is.
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
 */
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
}) {
  const [album, setAlbum] = useState<AlbumWithSongs | null>(null)
  const [error, setError] = useState<string | null>(null)
  const requests = useMemo(latestOnly, [])
  //? what the store holds of this album, and its other pressings - the id bridge
  const [store, setStore] = useState<StoreAlbumResponse | null>(null)
  //? the bridge failed to answer - so, answered or not, whether the album can be pinned is known
  const [storeFailed, setStoreFailed] = useState(false)
  const storeRequests = useMemo(latestOnly, [])
  const { pins, known: pinsKnown, canSave } = usePins(true)
  //? the cover, full size (2.0.0-player.44), and the control that opened it - focus goes back there
  const [viewing, setViewing] = useState<ViewerImage[] | null>(null)
  const viewOpener = useRef<HTMLElement | null>(null)

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
        setError(reason instanceof Error ? reason.message : String(reason))
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
    storeAlbum({ navidrome_id: id }, request.signal).then(
      (answer) => {
        if (request.current()) setStore(answer)
      },
      (reason: unknown) => {
        //? a check that can't be made draws no chip - and no pin, with no release to pin it by
        if (request.current() && !isAbort(reason) && !again) setStoreFailed(true)
      },
    )
    return () => storeRequests.supersede()
  }, [id, refresh, storeRequests])

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

  const play = (start: number | null, shuffle = false) => {
    if (!album || !tracks.length) return
    rememberPlayed(album)
    player.playTracks(tracks, start, shuffle)
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
        {!(storeDone && !release) && (
          <PinToggle
            look="icon"
            pinned={pinned}
            ready={storeDone && !!release && pinsKnown}
            unsaved={!canSave}
            onToggle={() => void setPinned(pinTarget, !pinned)}
            onRefused={() => sayPins(PINS_UNSAVED)}
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
                missing: 'Navidrome has no cover for this album',
              }])
            }}
          >
            <Cover id={shown.coverArt} size={800} class="app-cover-open-img" />
          </button>
        ) : (
          <Cover id={shown?.coverArt} size={800} class="pl-hero-cover" />
        )}
        <h1 class="pl-hero-title">{shown?.name ?? ''}</h1>
        {artistId && artistName && onArtist ? (
          <button type="button" class="pl-hero-artist app-hero-link" onClick={() => onArtist({ id: artistId, name: artistName })}>
            {artistName}
          </button>
        ) : (
          //? not a link: drawn plain once the album has said it names no artist to go to - never while
          //? it might still be one, which would flash from grey to the link's colour
          <p class={`pl-hero-artist${album ? ' app-hero-plain' : ''}`}>{artistName}</p>
        )}
        <p class="pl-hero-meta">
          {[shown?.genre, shown?.year, format].filter(Boolean).join(' · ')}
        </p>

        {/* drawn from the first frame: an "Also" chip landing in it moves nothing below. Unseen until the
            bridge has answered or failed (2.0.0-player.41), so "In your library" first shows where it
            stays - on a phone's centred row it slid sideways as "Other pressings" landed beside it */}
        <div class={`app-album-chips${storeDone ? '' : ' is-waiting'}`}>
          <span class="app-held-badge">
            <CheckIcon class="app-held-badge-icon" />
            <span class="app-held-badge-text">In your library</span>
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
              aria-label="Other pressings"
              onClick={() => onOpenGroup({ id: group, title: shown?.name ?? '' })}
            >
              {/* "Pressings" where an Also chip shares a row too narrow for all three whole (app.css's
                  container query), so the Also chip keeps what room there is */}
              <span class="app-other-long">Other pressings</span>
              <span class="app-other-short">Pressings</span>
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

      {error && <p class="pl-notice">{error}</p>}
      {!album && !error && <div class="pl-spinner" aria-label="Loading" />}

      <ol class="pl-tracks">
        {songs.map((song, index) => {
          const isCurrent = player.track?.id === song.id
          const heading = headings[index]
          const showArtist = song.artist && song.artist !== shown?.artist
          return (
            <Fragment key={song.id}>
              {heading && <li class="pl-disc">{heading}</li>}
              <li>
                <button
                  type="button"
                  class={`pl-track${isCurrent ? ' is-current' : ''}`}
                  onClick={() => play(index)}
                >
                  <span class="pl-track-number">
                    {isCurrent ? <PlayingBars paused={!player.playing} /> : song.track ?? ''}
                  </span>
                  <span class="pl-track-text">
                    <span class="pl-track-title">{song.title}</span>
                    {showArtist && <span class="pl-track-artist">{song.artist}</span>}
                  </span>
                  <span class="pl-track-time">{trackTime(song.duration)}</span>
                </button>
              </li>
            </Fragment>
          )
        })}
      </ol>

      {album && (
        <p class="pl-album-footer">
          {songs.length} {songs.length === 1 ? 'song' : 'songs'}
          {total ? `, ${formatDuration(total)}` : ''}
        </p>
      )}

      {/* what the main page's details pane says of the album (2.0.0-player.44), once the bridge has answered */}
      <AlbumProperties rows={albumProperties(store, storeFailed, releaseSaid)} />

      <CoverViewer images={viewing} onClose={() => setViewing(null)} opener={viewOpener} />
    </section>
  )
}
