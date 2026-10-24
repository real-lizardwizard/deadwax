import { useEffect, useMemo, useState } from 'preact/hooks'

import { RECENT_LISTED, notPlayedInAWhile } from '../lib/home'
import { isAbort, latestOnly } from '../lib/latest'
import { sortAlbums } from '../lib/shelves'
import { EMPTY_LIBRARY, EMPTY_LIBRARY_HOW, NO_ALBUMS } from '../lib/yourLibrary'
import type { RequestRow } from '../lib/requestsView'
import { albumPage, dropPrefetch, prefetchAlbum, type Album, type NavidromeStatus } from '../player/api'
import { Cover } from '../player/Cover'
import { albumIndex } from './albumIndex'
import { Arriving } from './Arriving'
import { NeedsNavidrome } from './NeedsNavidrome'
import { Pinned, type PinnedArtist } from './Pinned'
import { movePin, removePin, usePins } from './usePins'
import { useYourAlbumsGeneration } from './useYourAlbums'
import { errorNote } from './ErrorNote'

/** How many albums the shelf shows. */
export const RECENT_COUNT = 20

/** A Home handed no way to open an artist (a sim's): one function for every render, so the memo holds. */
const NO_ARTIST = () => {}

/** Nothing new (logins off, or a sim's Home): one array for every render, so the memo holds. */
const NONE_NEW: readonly Album[] = []

/** How long Home's shelves wait for the pins to answer before they are drawn without them - Pinned
 *  is at the top, and arriving after the shelves under it would move them under a finger. */
export const PINNED_WAIT_MS = 1500

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
              <span class="app-tile-title" dir="auto">{album.name}</span>
              <span class="app-tile-artist" dir="auto">{album.artist}</span>
            </span>
          </button>
        </li>
      ))}
    </ul>
  )
}

/**
 * The albums Home's Recently added shows (2.0.5, UX batch 2 - James: "Home's Recently added shows the listener's OWN
 * library"): with a library of your own (`personal`), YOURS, newest first - the very list the Library's Recently added
 * draws (app/albumIndex.ts's `yours`, put in order by lib/shelves.ts, as LibraryHome does), so the two never differ;
 * with logins off (one library, the collection) Navidrome's newest (getAlbumList2 `newest`), as it always was.
 * (2.0.11 - James: "Recently added should be for the user's library, not deadwax's") yours newest by when each
 * entered YOUR library, its star (`'you'`), not by when the collection got it.
 */
export function recentlyAddedAlbums(personal: boolean, signal?: AbortSignal): Promise<Album[]> {
  if (personal) return albumIndex('yours').then((index) => sortAlbums(index.albums, 'newest', 'you').slice(0, RECENT_COUNT))
  return albumPage('newest', 0, signal, RECENT_COUNT)
}

/** "Recently added": the newest albums - yours with a library of your own (recentlyAddedAlbums). */
function RecentlyAdded({ personal, onOpen }: { personal: boolean; onOpen: (album: Album) => void }) {
  const [albums, setAlbums] = useState<Album[] | null>(null)
  //? (2.0.4) the error itself, said by errorNote (app/ErrorNote.tsx) in a listener's words
  const [error, setError] = useState<unknown>(null)
  const requests = useMemo(latestOnly, [])
  //? (2.0.5) yours asked again as your albums can have changed - an Add, a Remove, your library's count moving -
  //? as every reader of the list is (app/useYourAlbums.ts); nothing moves it with logins off
  const generation = useYourAlbumsGeneration()

  function load() {
    const request = requests.begin()
    setError(null)
    recentlyAddedAlbums(personal, request.signal).then(
      (page) => {
        if (request.current()) setAlbums(page)
      },
      (reason: unknown) => {
        if (request.current() && !isAbort(reason)) setError(reason)
      },
    )
  }

  useEffect(load, [requests, personal, personal ? generation : 0])
  useEffect(() => () => requests.supersede(), [requests])

  return (
    <section class="app-section app-shelf-section" aria-labelledby="app-recent-title">
      <h2 id="app-recent-title" class="app-section-title app-shelf-title">
        Recently added
      </h2>
      {error ? (
        <div class="pl-notice">
          {errorNote(error, { service: 'music', retry: true })}
          <button type="button" class="pl-text-button" onClick={load}>
            Try again
          </button>
        </div>
      ) : albums === null ? (
        <div class="pl-spinner" aria-label="Loading" />
      ) : albums.length ? (
        <Tiles albums={albums} onOpen={onOpen} />
      ) : personal ? (
        <div class="pl-notice app-library-empty">
          <p>{EMPTY_LIBRARY}</p>
          <p>{EMPTY_LIBRARY_HOW}</p>
        </div>
      ) : (
        <p class="pl-notice">{NO_ALBUMS}</p>
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
 * "New in your library" (2.0.0-player.51, personal libraries): with logins on, the albums added to your
 * library since you last opened them - filed for you (or by an admin's Add for them), starred in Amperfy -
 * that Navidrome has (a starred one); opening one takes it off (App's openAlbum). Add to my library is
 * never new (it is made while looking at the album). None, no shelf.
 */
function NewInYourLibrary({ albums, onOpen }: { albums: readonly Album[]; onOpen: (album: Album) => void }) {
  return (
    <section class="app-section app-shelf-section" aria-labelledby="app-new-title">
      <h2 id="app-new-title" class="app-section-title app-shelf-title">
        New in your library
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
  personal,
  shown,
  onOpen,
  onOpenArtist,
  newAlbums,
}: {
  personal: boolean
  shown: boolean
  onOpen: (album: Album) => void
  onOpenArtist: (artist: PinnedArtist) => void
  newAlbums: readonly Album[] | null
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
  const recent = useMemo(() => <RecentlyAdded personal={personal} onOpen={onOpen} />, [personal, onOpen])
  const notPlayed = useMemo(() => <NotPlayedInAWhile onOpen={onOpen} />, [onOpen])
  //? (2.0.0-player.51) waited for as the pins are, so its shelf landing never moves the ones under it
  const ready = (pins !== null || problem !== null || waited) && (newAlbums !== null || waited)

  return (
    <>
      {!ready && <div class="pl-spinner" aria-label="Loading" />}
      <div class="app-home-shelves" hidden={!ready}>
        <Pinned pins={pins} problem={problem} onOpenAlbum={onOpen} onOpenArtist={onOpenArtist} onMove={movePin} onRemove={removePin} />
        {!!newAlbums?.length && <NewInYourLibrary albums={newAlbums} onOpen={onOpen} />}
        {recent}
        {notPlayed}
      </div>
    </>
  )
}

/**
 * Home, the first tab, as Home.dc.html draws it: what's arriving - only while something is
 * (2.0.0-player.12) - then, since 2.0.0-player.18, what you pinned, (2.0.0-player.51, logins on) what is
 * new in your library, what was added recently, and what you haven't played in a while. James: Home is the PLAYER's, not the librarian's; none of it is
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
  newAlbums = NONE_NEW,
  personal = false,
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
  /** (2.0.0-player.51) what is new in your library, as Navidrome albums - null while deadwax hasn't said
   *  (logins on); none with logins off */
  newAlbums?: readonly Album[] | null
  /** (2.0.5) a library of your own (logins on, signed in through Navidrome): Recently added is yours */
  personal?: boolean
}) {
  const shelves = useMemo(
    () => (
      <NeedsNavidrome status={status} onRetry={onRetry}>
        <Shelves personal={personal} shown={shown} onOpen={onOpen} onOpenArtist={onOpenArtist} newAlbums={newAlbums} />
      </NeedsNavidrome>
    ),
    [status, onRetry, onOpen, onOpenArtist, shown, newAlbums, personal],
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
