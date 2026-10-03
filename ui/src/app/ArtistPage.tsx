import { useEffect, useMemo, useRef, useState } from 'preact/hooks'

import { MusicBrainzUnavailable } from '../api/http'
import { getArtistFacts, getDiscography, getReleaseGroup } from '../api/musicbrainz'
import { navidromeAlbumFor } from '../api/store'
import type { ArtistFactsLight, ReleaseGroup, ReleaseGroupResponse } from '../api/types'
import {
  artistMbid, artistRef, artistRows, factsLine, inTurns, libraryArtistFor, playOrder, playsLine, rowLine, type ArtistRow,
} from '../lib/artistPage'
import { isAbort, latestOnly } from '../lib/latest'
import { pinOf, type ArtistPinTarget } from '../lib/pins'
import { coverAddresses } from '../lib/pressings'
import {
  artistAlbums, artistIndexAge, libraryArtists, prefetchAlbum, rememberQueue, toQueueTrack,
  type Album, type AlbumWithSongs, type ArtistWithAlbums,
} from '../player/api'
import { Cover } from '../player/Cover'
import { CheckIcon, ChevronLeftIcon, PlayIcon, ShuffleIcon } from '../player/icons'
import { ArchiveCover } from './ArchiveCover'
import { usePlayerActions } from './context'
import { PINS_UNSAVED, PinToggle } from './PinToggle'
import { keep, kept as keptPressings, usualGet } from './pressingLists'
import type { GetRequest } from './Sources'
import { ownedNow, useOwned, whenOwned } from './useOwned'
import { sayPins, setPinned, usePins } from './usePins'
import { takeOpener } from './useSheet'

/** What an artist page shows before anything has answered: what the row that opened it knew. */
export interface ArtistPreview {
  name?: string
  coverArt?: string | null
}

type Library =
  | { state: 'asking' }
  | { state: 'done'; artist: ArtistWithAlbums | null }
  | { state: 'failed'; message: string }

/** MusicBrainz's albums for the artist: the last answer stays on screen while another is asked for
 *  (`of` says which question it answered - "<mbid>|<studio only>"), so nothing under a finger moves
 *  until the new one lands. */
interface Discography {
  state: 'idle' | 'asking' | 'done' | 'failed'
  groups: ReleaseGroup[] | null
  truncated: boolean
  of: string | null
  message?: string
  unavailable?: boolean
}

const message = (error: unknown) => (error instanceof Error ? error.message : String(error))

/** What a link to an artist that isn't one says, with nothing to try again. */
export const NOT_AN_ARTIST_LINK = "That isn't a link to an artist."

/** How long the albums wait for the library and MusicBrainz to answer before they are drawn with
 *  what has - as Search waits for the library (OWNED_WAIT_MS), so a row isn't drawn and moved. */
export const ROWS_WAIT_MS = 1500

/** How many of the albums Play plays have their songs asked for at once. */
export const PREFETCH_AT_ONCE = 4

/** How old a kept list of the library's artists may be before a page not finding its artist in it
 *  asks again - an artist whose first album was just filed isn't in one from before. */
export const ARTIST_INDEX_STALE_MS = 15_000

/** How many artists' answers the session keeps, so a page come back to draws at once. */
export const ARTISTS_KEPT = 20

/** What the session keeps of an artist's page, by its id: each answer as it last landed. */
interface KeptArtist {
  foundId: string | null
  /** Navidrome's artist and their albums; undefined until Navidrome has answered */
  library: ArtistWithAlbums | null | undefined
  facts: { mbid: string; facts: ArtistFactsLight } | null
  studioOnly: boolean
  /** complete answers only, by "<mbid>|<studio only>" */
  discography: Map<string, { groups: ReleaseGroup[]; truncated: boolean }>
}

const keptArtists = new Map<string, KeptArtist>()

/** The session's copy of an artist's page, as the newest - made empty the first time. */
function keptArtist(id: string): KeptArtist {
  const entry = keptArtists.get(id) ?? { foundId: null, library: undefined, facts: null, studioOnly: true, discography: new Map() }
  keptArtists.delete(id)
  keptArtists.set(id, entry)
  while (keptArtists.size > ARTISTS_KEPT) {
    const [oldest] = keptArtists.keys()
    if (oldest === undefined) break
    keptArtists.delete(oldest)
  }
  return entry
}

/**
 * An artist (2.0.0-player.17), as Artist.dc.html draws one: a hero with their picture (Navidrome's,
 * through /cover - the `artist.jpg` deadwax writes is what Navidrome serves) and their name at its
 * foot, who they are under it (MusicBrainz's facts), Play and Shuffle over the albums you have, and
 * their albums - MusicBrainz's discography, with what you hold of each marked, and every album you
 * have of theirs that MusicBrainz's list doesn't claim. The hero's top row has the pin at its right
 * (2.0.0-player.18, Artist.dc.html's "Pinned" chip): it pins them to Home by their MusicBrainz id -
 * or, with none to be had, by their name and Navidrome's id for them - so it waits, drawn but
 * inactive, until who they are is settled (their id known, or Navidrome and the library having both
 * answered without one) and the pins have answered, so it never says "Pin" of an artist who is
 * pinned. Whether they are pinned is the app's one store of pins (usePins.ts).
 *
 * The id is Navidrome's artist, or `mb:<mbid>` for one known only by MusicBrainz (the album you
 * don't have links here so); lib/artistPage.ts finds each side from the other and orders the rows.
 * One opened from MusicBrainz looks for Navidrome's artist in the kept list of the library's artists,
 * and - not there, and that list older than ARTIST_INDEX_STALE_MS - in a fresh one (an artist new
 * to the library since). Nothing found because Navidrome didn't answer says so, with Try again.
 *
 * PLAY AND SHUFFLE (the gesture rule): they call playTracks straight from the tap, with the queue
 * already built - so they are disabled until every album they play (one copy of each album you have,
 * lib/artistPage.ts's playOrder) has had its songs asked for and answered, and /library/owned has
 * said which of Navidrome's albums are copies of one album (review: before it, Play queued both of
 * Dummy's, every song twice). They are asked for as the
 * albums are known (the album page's own prefetch, KEPT, so a press on a row turning into a scroll
 * can't call one off), PREFETCH_AT_ONCE at a time in the page's order, and an album Navidrome won't
 * send is left out and said so under the buttons. Every album played is remembered for Info and the
 * turntable (rememberQueue). The buttons and the line under them are drawn from the first frame
 * wherever albums of theirs could be had - an artist Navidrome knows, or any while it answers - so
 * Navidrome's answer arriving moves nothing under a finger (review).
 *
 * THE ALBUMS wait for the library's albums, MusicBrainz's and /library/owned to answer - or
 * ROWS_WAIT_MS, whichever comes first - and are then drawn; a re-browse (Studio only) keeps the last
 * answer on screen until the new one lands. What is held and what isn't is said only once
 * /library/owned has answered (a row only Navidrome claims excepted); and "MusicBrainz doesn't know
 * who this is" only once it has had its say. The session keeps each answer (ARTISTS_KEPT artists),
 * so Back to this page draws its rows on the first frame and the app's scroll comes back with them.
 *
 * Rows: one you have opens the album; one held only by the store's word (Navidrome hasn't found it,
 * or holds it under other ids) asks the id bridge for Navidrome's album and opens that, else the
 * album you don't have; one you don't have opens the album you don't have, and its Get chip opens
 * the Sources sheet for the album's usual pressing, as Search's does. "Studio only" (on, as the
 * board has it) browses again leaving out live albums and compilations - never an album you have,
 * which is shown whatever it is.
 *
 * Every fetch that draws goes through its own latestOnly(): the library's answer, the facts, the
 * discography, the prefetches, a row's bridge and a chip's pressings. A row's or a chip's lookup
 * still out is called off when the page stops being what shows (`shown`), so its late answer opens
 * nothing on whatever tab you went to (review). A page: it reads the player's actions from context.
 */
export function ArtistPage({
  id,
  preview,
  navidromeOk,
  shown,
  onBack,
  backLabel,
  onOpenAlbum,
  onOpenGroup,
  onGet,
}: {
  id: string
  preview: ArtistPreview | null
  /** Navidrome answers: the albums you have can be asked for */
  navidromeOk: boolean
  /** the page is what shows - its tab current, no sheet over it, the app in front (App) */
  shown: boolean
  onBack: () => void
  backLabel: string
  onOpenAlbum: (album: Album) => void
  onOpenGroup: (group: ReleaseGroup) => void
  /** a row's Get: open the Sources sheet for its usual pressing, focus given back to `opener` */
  onGet: (request: Omit<GetRequest, 'key'>, opener: HTMLElement | null) => void
}) {
  const actions = usePlayerActions()
  const { pins, known: pinsKnown, canSave } = usePins(true)
  const ref = useMemo(() => artistRef(id), [id])
  const kept = useMemo(() => keptArtist(id), [id])
  const owned = useOwned(true)
  //? /library/owned has answered once, or failed to: what isn't held can be said only after
  const [ownedKnown, setOwnedKnown] = useState(() => ownedNow() !== null)
  //? the page shows, read when an answer lands
  const showing = useRef(shown)
  showing.current = shown

  //? an artist known only by MusicBrainz: Navidrome's artist for them, once found
  const [foundId, setFoundId] = useState<string | null>(() => (ref.navidrome ? null : kept.foundId))
  const libraryId = ref.navidrome ?? foundId
  //? an artist known only by MusicBrainz, with no Navidrome to ask: nothing of theirs can be had
  const [library, setLibrary] = useState<Library>(() =>
    kept.library !== undefined ? { state: 'done', artist: kept.library }
      : ref.navidrome || (ref.mbid && navidromeOk) ? { state: 'asking' } : { state: 'done', artist: null })
  //? Try again on an artist opened from MusicBrainz whose look in the library failed
  const [finds, setFinds] = useState(0)
  const [studioOnly, setStudioOnly] = useState(kept.studioOnly)

  const artist = library.state === 'done' ? library.artist : null
  const held: Album[] = artist?.album ?? []
  const mbid = ref.mbid ?? artistMbid(artist, held, owned?.index ?? null)
  const discKey = mbid ? `${mbid}|${studioOnly}` : null

  const [facts, setFacts] = useState<ArtistFactsLight | null>(() => (kept.facts && kept.facts.mbid === mbid ? kept.facts.facts : null))
  const [discography, setDiscography] = useState<Discography>(() => {
    const found = discKey ? kept.discography.get(discKey) : undefined
    return found ? { state: 'done', groups: found.groups, truncated: found.truncated, of: discKey } : { state: 'idle', groups: null, truncated: false, of: null }
  })
  const [ready, setReady] = useState<ReadonlyMap<string, AlbumWithSongs>>(new Map())
  const [unsent, setUnsent] = useState<ReadonlySet<string>>(new Set())
  //? Try again after Navidrome didn't send an album's songs: asks for those again
  const [asks, setAsks] = useState(0)
  const [resolving, setResolving] = useState<string | null>(null)
  const [opening, setOpening] = useState<string | null>(null)
  //? the albums have waited ROWS_WAIT_MS: drawn with whatever has answered
  const [waited, setWaited] = useState(false)

  const findRequests = useMemo(latestOnly, [])
  const libraryRequests = useMemo(latestOnly, [])
  const factsRequests = useMemo(latestOnly, [])
  const discRequests = useMemo(latestOnly, [])
  const prefetches = useMemo(latestOnly, [])
  const openRequests = useMemo(latestOnly, [])
  const getRequests = useMemo(latestOnly, [])

  useEffect(() => {
    if (ownedKnown) return
    let live = true
    void whenOwned().then(() => {
      if (live) setOwnedKnown(true)
    })
    return () => {
      live = false
    }
  }, [])

  useEffect(() => {
    const timer = setTimeout(() => setWaited(true), ROWS_WAIT_MS)
    return () => clearTimeout(timer)
  }, [])

  //? Navidrome's artist for one opened from MusicBrainz: asked again as the library's folders and
  //? MusicBrainz's name for them come in, either of which can be what finds them
  const factsName = facts?.name ?? null
  useEffect(() => {
    if (ref.navidrome) return
    if (!ref.mbid || !navidromeOk) {
      findRequests.supersede()
      setLibrary({ state: 'done', artist: null })
      return
    }
    const request = findRequests.begin()
    const look = (artists: Awaited<ReturnType<typeof libraryArtists>>) =>
      libraryArtistFor(artists, ref.mbid, owned?.index ?? null, factsName ?? preview?.name)
    const settle = (found: ReturnType<typeof look>) => {
      if (!request.current()) return
      if (found) {
        kept.foundId = found.id
        setFoundId(found.id)
      } else if (!foundId) {
        kept.library = null
        setLibrary({ state: 'done', artist: null })
      }
    }
    libraryArtists()
      .then((artists) => {
        if (!request.current()) return
        const found = look(artists)
        //? not in a list kept from a while ago: an artist new to the library since isn't in it
        if (found || artistIndexAge() < ARTIST_INDEX_STALE_MS) return settle(found)
        return libraryArtists(true).then((again) => settle(look(again)))
      })
      .catch((reason: unknown) => {
        if (request.current() && !isAbort(reason)) setLibrary({ state: 'failed', message: message(reason) })
      })
    return () => findRequests.supersede()
  }, [ref.mbid, navidromeOk, owned, factsName, finds])

  function loadLibrary() {
    if (!libraryId) return
    const request = libraryRequests.begin()
    //? a kept answer for this artist stays drawn while it is asked again
    const quiet = library.state === 'done' && !!library.artist && library.artist.id === libraryId
    if (!quiet) setLibrary({ state: 'asking' })
    artistAlbums(libraryId, request.signal).then(
      (answer) => {
        if (!request.current()) return
        kept.library = answer
        setLibrary({ state: 'done', artist: answer })
      },
      (reason: unknown) => {
        if (request.current() && !isAbort(reason) && !quiet) setLibrary({ state: 'failed', message: message(reason) })
      },
    )
  }

  const tryLibraryAgain = () => {
    if (libraryId) {
      loadLibrary()
      return
    }
    setLibrary({ state: 'asking' })
    setFinds((count) => count + 1)
  }

  useEffect(() => {
    if (!libraryId || !navidromeOk) return
    loadLibrary()
    return () => libraryRequests.supersede()
  }, [libraryId, navidromeOk])

  //? who they are, and their albums: asked of MusicBrainz once their id is known - once a session
  useEffect(() => {
    if (!mbid) return
    if (kept.facts?.mbid === mbid) {
      setFacts(kept.facts.facts)
      return
    }
    const request = factsRequests.begin()
    getArtistFacts(mbid, request.signal).then(
      (found) => {
        if (!request.current()) return
        kept.facts = { mbid, facts: found }
        setFacts(found)
      },
      () => {
        //? the facts are a line under the name: without them, the line is left out
      },
    )
    return () => factsRequests.supersede()
  }, [mbid])

  /** MusicBrainz's albums for the artist - the session's when it has them, else asked, the last
   *  answer staying on screen meanwhile (Studio only toggled, Try again). */
  function browse(again = false) {
    if (!mbid || !discKey) return
    const key = discKey
    const found = again ? undefined : kept.discography.get(key)
    if (found) {
      discRequests.supersede()
      setDiscography({ state: 'done', groups: found.groups, truncated: found.truncated, of: key })
      return
    }
    const request = discRequests.begin()
    setDiscography((before) => ({ ...before, state: 'asking' }))
    //? a failure keeps what was on screen only when it answered this same question
    const failed = (problem: string, unavailable: boolean) =>
      setDiscography((before) => ({
        state: 'failed', groups: before.of === key ? before.groups : null, truncated: before.of === key && before.truncated,
        of: before.of === key ? key : null, message: problem, unavailable,
      }))
    getDiscography(mbid, studioOnly, request.signal).then(
      (answer) => {
        if (!request.current()) return
        //? a list MusicBrainz broke off is not the artist's albums: "not in your library" on half of
        //? them would be a claim made of half an answer
        if (answer.problem) {
          failed(answer.problem, true)
          return
        }
        const groups = answer['release-groups'] ?? []
        kept.discography.set(key, { groups, truncated: !!answer.truncated })
        setDiscography({ state: 'done', groups, truncated: !!answer.truncated, of: key })
      },
      (reason: unknown) => {
        if (!request.current() || isAbort(reason)) return
        failed(message(reason), reason instanceof MusicBrainzUnavailable)
      },
    )
  }

  useEffect(() => {
    browse()
    return () => discRequests.supersede()
  }, [mbid, studioOnly])

  const toggleStudio = () => {
    const on = !studioOnly
    kept.studioOnly = on
    setStudioOnly(on)
  }

  const groups = discography.groups
  const index = owned?.index ?? null
  const rows = useMemo(() => artistRows(held, groups, index), [artist, groups, owned])
  const playing = playOrder(rows)
  const playKey = [...playing].sort().join('\n')

  //? every album Play plays, asked for as it is known, a few at a time in the page's order - kept, so
  //? a press on a row turning into a scroll can't call one off - so Play has every song in hand. Not
  //? before the library has said which of Navidrome's albums are copies of one: until then both of
  //? Dummy's would be asked for, and Play waits for it anyway
  useEffect(() => {
    const wanted = ownedKnown ? playing.filter((album) => !ready.has(album)) : []
    if (!wanted.length) return
    const request = prefetches.begin()
    inTurns(wanted, PREFETCH_AT_ONCE, (album) => prefetchAlbum(album, true).then(
      (answer) => {
        if (request.current()) setReady((before) => new Map(before).set(album, answer))
      },
      () => {
        if (request.current()) setUnsent((before) => new Set(before).add(album))
      },
    ), () => request.current())
  }, [playKey, asks, ownedKnown])

  const askAgain = () => {
    setUnsent(new Set())
    setAsks((count) => count + 1)
  }

  //? a row's or a chip's lookup still out when the page stops being what shows opens nothing
  useEffect(() => {
    if (!shown) {
      getRequests.supersede()
      setResolving(null)
      openRequests.supersede()
      setOpening(null)
    }
  }, [shown])

  useEffect(() => () => {
    for (const requests of [findRequests, libraryRequests, factsRequests, discRequests, prefetches, openRequests, getRequests]) requests.supersede()
  }, [])

  //? every album answered - asked for only once the library has said which of Navidrome's albums
  //? are copies of one, so Play never plays both of Dummy's
  const inHand = playing.filter((album) => ready.has(album))
  const settled = playing.every((album) => ready.has(album) || unsent.has(album))
  const playable = settled && inHand.length > 0

  /** Play or Shuffle: every album you have of theirs, in the page's order - all in hand, nothing awaited. */
  const play = (shuffle: boolean) => {
    if (!playable) return
    const albums = inHand.map((album) => ready.get(album)!)
    const tracks = albums.flatMap((album) => (album.song ?? []).map((song) => toQueueTrack(song, album)))
    if (!tracks.length) return
    rememberQueue(albums)
    actions.playTracks(tracks, shuffle ? null : 0, shuffle)
  }

  const name = artist?.name ?? facts?.name ?? preview?.name ?? ''
  const picture = artist?.coverArt ?? preview?.coverArt ?? null

  //? the pin: by their MusicBrainz id, else by name and Navidrome's id - ready once that is settled,
  //? and the pins have answered
  const pinTarget: ArtistPinTarget = { kind: 'artist', mbid, navidrome_id: libraryId, name, cover: picture }
  const pinned = pinOf(pins, pinTarget) !== null
  const pinReady = pinsKnown && !!name && (mbid !== null || (library.state !== 'asking' && ownedKnown && libraryId !== null))

  /** A row: the album you have, or - held only by the store's word - Navidrome's album for it, or
   *  the album you don't have. A tap calls off any row's lookup still out. */
  const openRow = (row: ArtistRow) => {
    if (row.albumId || !row.held || !row.releases.length) {
      openRequests.supersede()
      setOpening(null)
      if (row.albumId) onOpenAlbum({ id: row.albumId, name: row.title, ...(name ? { artist: name } : {}), ...(row.coverArt ? { coverArt: row.coverArt } : {}) })
      else if (row.group) onOpenGroup(row.group)
      return
    }
    const request = openRequests.begin()
    setOpening(row.key)
    navidromeAlbumFor(row.releases, request.signal).then(
      (album) => {
        if (!request.current()) return
        setOpening(null)
        if (!showing.current) return
        if (album) onOpenAlbum({ id: album, name: row.title, ...(name ? { artist: name } : {}) })
        else if (row.group) onOpenGroup(row.group)
      },
      (reason: unknown) => {
        if (!request.current() || isAbort(reason)) return
        setOpening(null)
        if (showing.current && row.group) onOpenGroup(row.group)
      },
    )
  }

  /** A row's Get: the album's usual pressing - from the session's lists, else asked of MusicBrainz. */
  async function getAlbum(group: ReleaseGroup, event: MouseEvent) {
    const opener = takeOpener(event)
    const request = getRequests.begin()
    let pressings: ReleaseGroupResponse | null = keptPressings(group.id)
    if (!pressings) {
      setResolving(group.id)
      try {
        const found = await getReleaseGroup(group.id, request.signal)
        if (!found.problem) {
          keep(group.id, found)
          pressings = found
        }
      } catch (reason) {
        if (!request.current() || isAbort(reason)) return
      }
    }
    if (!request.current()) return
    setResolving(null)
    if (!showing.current) return
    onGet(usualGet(group, pressings), opener)
  }

  const known = ref.navidrome !== null || ref.mbid !== null
  const about = factsLine(facts)
  //? Play and Shuffle are drawn, from the first frame, wherever albums of theirs could be had: an
  //? artist Navidrome knows, or one MusicBrainz knows while Navidrome answers
  const showPlay = ref.navidrome !== null || (ref.mbid !== null && navidromeOk)
  //? the albums wait for every answer, or ROWS_WAIT_MS: drawn, they don't move as one lands
  const libraryKnown = library.state !== 'asking'
  const discKnown = groups !== null || discography.state === 'failed' || (!mbid && libraryKnown)
  //? ...and once drawn, they stay drawn: Navidrome asked again (an artist found later) never takes
  //? them away while it answers
  const rowsDrawn = useRef(false)
  if (waited || (libraryKnown && discKnown && ownedKnown)) rowsDrawn.current = true
  const drawRows = rowsDrawn.current
  const asking = discography.state === 'asking' || !drawRows

  return (
    <section class="app-artist">
      <div class="app-artist-hero">
        {picture && <Cover id={picture} size={800} class="app-artist-picture" />}
        <div class="app-artist-top">
          <button type="button" class="app-artist-back" onClick={onBack}>
            <ChevronLeftIcon class="pl-back-icon" />
            <span class="pl-back-label">{backLabel}</span>
          </button>
          {(ref.navidrome !== null || ref.mbid !== null) && (
            <PinToggle
              look="chip"
              pinned={pinned}
              ready={pinReady}
              unsaved={!canSave}
              onToggle={() => void setPinned(pinTarget, !pinned)}
              onRefused={() => sayPins(PINS_UNSAVED)}
            />
          )}
        </div>
        <div class="app-artist-names">
          <h1 class="app-artist-name">{name}</h1>
          {about && <p class="app-artist-facts">{about}</p>}
        </div>
      </div>

      {!known ? (
        <p class="pl-notice">{NOT_AN_ARTIST_LINK}</p>
      ) : (
        <div class="app-artist-body">
          {showPlay && (
            <div class="app-artist-play">
              <div class="app-artist-actions">
                <button type="button" class="pl-pill is-primary" disabled={!playable} onClick={() => play(false)}>
                  <PlayIcon class="pl-pill-icon" />
                  Play
                </button>
                <button type="button" class="pl-pill" disabled={!playable} onClick={() => play(true)}>
                  <ShuffleIcon class="pl-pill-icon" />
                  Shuffle
                </button>
              </div>
              <p class="app-artist-plays" aria-live="polite">{playsLine(playing.length, inHand.length, settled, library.state)}</p>
              {settled && inHand.length < playing.length && (
                <button type="button" class="app-text-button app-artist-again" onClick={askAgain}>
                  Try again
                </button>
              )}
            </div>
          )}

          {library.state === 'failed' && (
            <div class="pl-notice">
              <p>{library.message}</p>
              <button type="button" class="pl-text-button" onClick={tryLibraryAgain}>
                Try again
              </button>
            </div>
          )}

          <section class="app-artist-albums" aria-labelledby="app-artist-albums-title" aria-busy={asking}>
            <div class="app-artist-albums-head">
              <h2 id="app-artist-albums-title" class="app-section-title app-artist-albums-title">Albums</h2>
              {mbid && (
                <button type="button" class={`app-chip${studioOnly ? ' is-on' : ''}`} aria-pressed={studioOnly} onClick={toggleStudio}>
                  Studio only
                </button>
              )}
            </div>

            {drawRows && rows.length > 0 && (
              <ul class="app-artist-rows">
                {rows.map((row) => (
                  <li key={row.key} class="app-artist-row">
                    <button
                      type="button"
                      class={`app-artist-album${opening === row.key ? ' is-busy' : ''}`}
                      aria-busy={opening === row.key}
                      onClick={() => openRow(row)}
                    >
                      {row.albumId || !row.group ? (
                        <Cover id={row.coverArt} size={112} class="app-artist-cover" />
                      ) : (
                        <ArchiveCover addresses={coverAddresses(null, row.group.id, 250)} class="app-artist-cover" />
                      )}
                      <span class="app-result-text">
                        <span class="app-result-title">{row.title}</span>
                        <span class="app-result-line app-artist-line">
                          {row.held === true && <CheckIcon class="app-artist-held" />}
                          <span class="app-artist-line-text">{rowLine(row)}</span>
                        </span>
                      </span>
                    </button>
                    {row.held === false && row.group && (
                      <button
                        type="button"
                        class={`app-result-get${resolving === row.group.id ? ' is-busy' : ''}`}
                        aria-label={`Get ${row.title || 'this album'}`}
                        aria-busy={resolving === row.group.id}
                        onClick={(event) => void getAlbum(row.group!, event)}
                      >
                        {resolving === row.group.id ? 'Get…' : 'Get'}
                      </button>
                    )}
                  </li>
                ))}
              </ul>
            )}

            {asking ? (
              <div class="app-asking" role="status">
                <span class="app-sweep" aria-hidden="true" />
                <span class="app-asking-text">{discography.state === 'asking' ? 'Asking MusicBrainz…' : 'Looking in your library…'}</span>
              </div>
            ) : discography.state === 'failed' ? (
              <div class="app-search-problem">
                <p class="app-search-empty">
                  {discography.unavailable
                    ? "MusicBrainz isn't answering just now, so the albums you don't have aren't here - it often goes away for a few minutes."
                    : discography.message}
                </p>
                <button type="button" class="app-button" onClick={() => browse(true)}>
                  Try again
                </button>
              </div>
            ) : discography.state === 'done' && discography.truncated ? (
              <p class="app-search-empty">MusicBrainz lists more albums than the first 500 shown here.</p>
            ) : !mbid && library.state === 'done' && ownedKnown ? (
              <p class="app-search-empty">
                {held.length
                  ? "MusicBrainz doesn't know who this is from your files, so only the albums you have are here."
                  : "Nothing of theirs in your library, and MusicBrainz doesn't know who this is."}
              </p>
            ) : discography.state === 'done' && !rows.length ? (
              <p class="app-search-empty">{studioOnly ? 'No studio albums on MusicBrainz.' : 'No albums on MusicBrainz.'}</p>
            ) : null}
          </section>
        </div>
      )}
    </section>
  )
}
