import { Fragment } from 'preact'
import { useEffect, useMemo, useRef, useState } from 'preact/hooks'

import { storeAlbum } from '../api/store'
import type { StoreAlbumResponse } from '../api/types'
import { PINS_UNSAVED, PinToggle } from '../app/PinToggle'
import { sayPins, setPinned, usePins } from '../app/usePins'
import { discHeadings } from '../lib/discTitles'
import { formatDuration, sharedFormat, trackTime } from '../lib/format'
import { editAlbum, type EditAlbum } from '../lib/albumEdit'
import { alsoChips } from '../lib/idBridge'
import { isAbort, latestOnly } from '../lib/latest'
import { pinOf, type AlbumPinTarget } from '../lib/pins'
import { album as fetchAlbum, prefetchAlbum, rememberPlayed, toQueueTrack, type Album, type AlbumWithSongs } from './api'
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
 * Navidrome sent it, which is what the panel finds its folder by; a phone has no editor, and is handed
 * none. Live once the album has answered. After an edit App asks the page again (`refresh`): the album
 * and the bridge are asked afresh and what is drawn stays until they answer - a refresh that fails
 * keeps it, since the album may be under a new id Navidrome hasn't scanned yet (App moves the page to
 * it once found).
 */
export function AlbumPage({
  id,
  preview,
  player,
  onBack,
  backLabel,
  onArtist,
  onOpenAlbum,
  onEdit,
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
  /** Edit, on a desktop and for an admin (2.0.0-player.21): the Edit panel for this album, or closed */
  onEdit?: ((event: MouseEvent, album: EditAlbum) => void) | undefined
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
  const songs = album?.song ?? []
  const tracks = useMemo(() => (album ? songs.map((song) => toQueueTrack(song, album)) : []), [album])
  const headings = discHeadings(songs, album?.discTitles)
  const format = sharedFormat(songs)
  const total = songs.reduce((sum, song) => sum + (song.duration ?? 0), 0)

  const chips = alsoChips(store, id)
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
        <Cover id={shown?.coverArt} size={800} class="pl-hero-cover" />
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

        {/* drawn from the first frame: an "Also" chip landing in it moves nothing below */}
        <div class="app-album-chips">
          <span class="app-held-badge">
            <CheckIcon class="app-held-badge-icon" />
            In your library
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
          {onEdit && (
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
    </section>
  )
}
