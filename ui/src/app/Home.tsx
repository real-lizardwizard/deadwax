import { useEffect, useMemo, useState } from 'preact/hooks'

import { RECENT_LISTED, notPlayedInAWhile } from '../lib/home'
import { isAbort, latestOnly } from '../lib/latest'
import type { RequestRow } from '../lib/requestsView'
import { albumPage, dropPrefetch, prefetchAlbum, type Album, type NavidromeStatus } from '../player/api'
import { Cover } from '../player/Cover'
import { Arriving } from './Arriving'
import { NeedsNavidrome } from './NeedsNavidrome'
import { Pinned, type PinnedArtist } from './Pinned'
import { movePin, removePin, usePins } from './usePins'

/** How many albums the shelf shows. */
export const RECENT_COUNT = 20

/** A Home handed no way to open an artist (a sim's): one function for every render, so the memo holds. */
const NO_ARTIST = () => {}

/** How long Home's shelves wait for the pins to answer before they are drawn without them - Pinned
 *  is at the top, and arriving after the shelves under it would move them under a finger. */
export const PINNED_WAIT_MS = 1500

const message = (error: unknown) => (error instanceof Error ? error.message : String(error))

/**
 * A row of album tiles you swipe along. A tile OPENS the album - it never plays it, since Play has to
 * be pressed in the tap that starts it, with the songs already in hand - and asks for the album's
 * songs as the finger lands (prefetchAlbum), so the page usually has them by the time it opens.
 */
function Tiles({ albums, onOpen }: { albums: readonly Album[]; onOpen: (album: Album) => void }) {
  return (
    <ul class="app-shelf">
      {albums.map((album) => (
        <li key={album.id} class="app-shelf-item">
          <button
            type="button"
            class="app-tile"
            onPointerDown={() => prefetchAlbum(album.id)}
            onPointerCancel={() => dropPrefetch(album.id)}
            onClick={() => onOpen(album)}
          >
            <Cover id={album.coverArt} size={260} class="app-tile-cover" />
            {/* one block, as the board has it: the two lines sit together under the cover */}
            <span class="app-tile-text">
              <span class="app-tile-title">{album.name}</span>
              <span class="app-tile-artist">{album.artist}</span>
            </span>
          </button>
        </li>
      ))}
    </ul>
  )
}

/** "Recently added": Navidrome's newest albums (getAlbumList2 `newest`). */
function RecentlyAdded({ onOpen }: { onOpen: (album: Album) => void }) {
  const [albums, setAlbums] = useState<Album[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const requests = useMemo(latestOnly, [])

  function load() {
    const request = requests.begin()
    setError(null)
    albumPage('newest', 0, request.signal, RECENT_COUNT).then(
      (page) => {
        if (request.current()) setAlbums(page)
      },
      (reason: unknown) => {
        if (request.current() && !isAbort(reason)) setError(message(reason))
      },
    )
  }

  useEffect(() => {
    load()
    return () => requests.supersede()
  }, [requests])

  return (
    <section class="app-section app-shelf-section" aria-labelledby="app-recent-title">
      <h2 id="app-recent-title" class="app-section-title app-shelf-title">
        Recently added
      </h2>
      {error ? (
        <div class="pl-notice">
          <p>{error}</p>
          <button type="button" class="pl-text-button" onClick={load}>
            Try again
          </button>
        </div>
      ) : albums === null ? (
        <div class="pl-spinner" aria-label="Loading" />
      ) : albums.length ? (
        <Tiles albums={albums} onOpen={onOpen} />
      ) : (
        <p class="pl-notice">No albums in Navidrome yet.</p>
      )}
    </section>
  )
}

/**
 * "Not played in a while" (2.0.0-player.18): Navidrome's albums played longest ago - from its
 * `recent` list, RECENT_LISTED long, by each album's OpenSubsonic `played` (lib/home.ts has the rule:
 * more than 30 days ago, the longest ago first, up to 20). The last section, so it can
 * arrive when it likes without moving anything above it - and with nothing to show (fewer than four,
 * a Navidrome that doesn't send `played`, or one that didn't answer) there is no section at all,
 * heading included: a shelf that hides itself when it has little to say says nothing of a failure
 * either, which Recently added, beside it, says for both.
 */
function NotPlayedInAWhile({ onOpen }: { onOpen: (album: Album) => void }) {
  const [albums, setAlbums] = useState<Album[] | null>(null)
  const requests = useMemo(latestOnly, [])

  useEffect(() => {
    const request = requests.begin()
    albumPage('recent', 0, request.signal, RECENT_LISTED).then(
      (page) => {
        if (request.current()) setAlbums(notPlayedInAWhile(page, Date.now()))
      },
      () => {
        //? no shelf: see above
      },
    )
    return () => requests.supersede()
  }, [requests])

  if (!albums?.length) return null
  return (
    <section class="app-section app-shelf-section" aria-labelledby="app-not-played-title">
      <h2 id="app-not-played-title" class="app-section-title app-shelf-title">
        Not played in a while
      </h2>
      <Tiles albums={albums} onOpen={onOpen} />
    </section>
  )
}

/**
 * What Home draws from Navidrome, inside its gate: Pinned at the top, then Recently added, then Not
 * played in a while. The pins are asked afresh each time Home comes into view (`shown`); the shelves
 * are drawn once the pins have answered, or failed to, or PINNED_WAIT_MS has passed WHILE Home showed
 * - Recently added already asking, out of sight, meanwhile - so Pinned landing never moves the
 * shelves under a finger.
 * Each shelf is a memoised element, so the pins changing leaves twenty tiles alone.
 */
function Shelves({
  shown,
  onOpen,
  onOpenArtist,
}: {
  shown: boolean
  onOpen: (album: Album) => void
  onOpenArtist: (artist: PinnedArtist) => void
}) {
  const { pins, problem } = usePins(shown ? 'fresh' : false)
  //? the wait counts only while Home shows - afresh each time it comes into view, until it has once
  //? run out: counted out of sight, it could be over before the pins were even asked for, and Pinned
  //? would land above the shelves as Home came into view
  const [waited, setWaited] = useState(false)
  useEffect(() => {
    if (!shown || waited) return
    const timer = setTimeout(() => setWaited(true), PINNED_WAIT_MS)
    return () => clearTimeout(timer)
  }, [shown])
  const recent = useMemo(() => <RecentlyAdded onOpen={onOpen} />, [onOpen])
  const notPlayed = useMemo(() => <NotPlayedInAWhile onOpen={onOpen} />, [onOpen])
  const ready = pins !== null || problem !== null || waited

  return (
    <>
      {!ready && <div class="pl-spinner" aria-label="Loading" />}
      <div class="app-home-shelves" hidden={!ready}>
        <Pinned pins={pins} problem={problem} onOpenAlbum={onOpen} onOpenArtist={onOpenArtist} onMove={movePin} onRemove={removePin} />
        {recent}
        {notPlayed}
      </div>
    </>
  )
}

/**
 * Home, the first tab, as Home.dc.html draws it: what's arriving - only while something is
 * (2.0.0-player.12) - then, since 2.0.0-player.18, what you pinned, what was added recently, and what
 * you haven't played in a while. James: Home is the PLAYER's, not the librarian's; none of it is
 * faked, and each part with nothing to say draws nothing (Pinned says how to pin something).
 *
 * Arriving is deadwax's, not Navidrome's, so it draws whatever Navidrome says; the rest open albums in
 * Navidrome and are gated on it. They are memoised on what they read: App re-renders Home as the
 * downloads move, and that must not re-render the shelves each time.
 */
export function Home({
  status,
  onRetry,
  onOpen,
  onOpenArtist = NO_ARTIST,
  arriving,
  onSeeAll,
  arrivingTrouble = false,
  shown = false,
}: {
  status: NavidromeStatus | null
  onRetry: () => void
  onOpen: (album: Album) => void
  /** a pinned artist's card: their page (2.0.0-player.18) */
  onOpenArtist?: (artist: PinnedArtist) => void
  /** the downloads on their way, up to three - none, and there is no Arriving section at all */
  arriving: readonly RequestRow[]
  /** "See all", and a tap on an Arriving card: the Requests tab's list, at its root */
  onSeeAll: () => void
  /** deadwax didn't answer the last look: Arriving says its cards are the last answer */
  arrivingTrouble?: boolean
  /** Home is what shows (App's watching): the pins are asked again as it comes into view */
  shown?: boolean
}) {
  const shelves = useMemo(
    () => (
      <NeedsNavidrome status={status} onRetry={onRetry}>
        <Shelves shown={shown} onOpen={onOpen} onOpenArtist={onOpenArtist} />
      </NeedsNavidrome>
    ),
    [status, onRetry, onOpen, onOpenArtist, shown],
  )

  return (
    <section class="app-home">
      <header class="pl-large-header">
        <h1 class="pl-large-title">Home</h1>
      </header>
      <Arriving rows={arriving} onSeeAll={onSeeAll} trouble={arrivingTrouble} />
      {shelves}
    </section>
  )
}
