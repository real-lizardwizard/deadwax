import { useEffect, useLayoutEffect, useMemo, useRef, useState } from 'preact/hooks'

import { MusicBrainzUnavailable } from '../api/http'
import { fetchArtist } from '../api/library'
import { getArtistFacts, getDiscography, getReleaseGroup } from '../api/musicbrainz'
import { navidromeAlbumFor } from '../api/store'
import type { ArtistFacts, ArtistSummary, ReleaseGroup, ReleaseGroupResponse } from '../api/types'
import {
  LINKS_SHOWN, MEMBERS_SHOWN, aboutRows, folded, imagesFolder, libraryFacts, libraryNames, listed, memberRoles, memberYears, namesToMove,
  type LibraryFacts,
} from '../lib/artistManage'
import {
  MB_PREFIX, artistMbid, artistRef, artistRows, factsLine, inTurns, libraryArtistFor, playOrder, playsLine, rowLine, type ArtistRow,
} from '../lib/artistPage'
import { artistArtUrl } from '../lib/format'
import { isAbort, latestOnly } from '../lib/latest'
import { foldName } from '../lib/owned'
import { GET_OFF, artistManaging, gets } from '../lib/permissions'
import { pinOf, type ArtistPinTarget } from '../lib/pins'
import { coverAddresses } from '../lib/pressings'
import {
  artistAlbums, artistIndexAge, libraryArtists, prefetchAlbum, rememberQueue, toQueueTrack,
  type Album, type AlbumWithSongs, type ArtistWithAlbums,
} from '../player/api'
import { queued, warmAlbum } from '../player/levelling'
import { Cover } from '../player/Cover'
import { CheckIcon, ChevronLeftIcon, ChevronRightIcon, PlayIcon, ShuffleIcon } from '../player/icons'
import { ArchiveCover } from './ArchiveCover'
import type { ArtistManageMode, ArtistManageRequest } from './ArtistPanel'
import { accessNow, seesDetail, useAccess } from './access'
import { usePlayerActions } from './context'
import { pinsUnsaved, PinToggle } from './PinToggle'
import { keep, kept as keptPressings, usualGet } from './pressingLists'
import type { GetRequest } from './Sources'
import { hasLibrary } from './useMyLibrary'
import { ownedNow, useOwned, whenOwned } from './useOwned'
import { sayPins, setPinned, usePins } from './usePins'
import { takeOpener } from './useSheet'
import { errorNote } from './ErrorNote'
import { errorKind } from '../lib/errorWords'

/** What an artist page shows before anything has answered: what the row that opened it knew. */
export interface ArtistPreview {
  name?: string
  coverArt?: string | null
}

type Library =
  | { state: 'asking' }
  | { state: 'done'; artist: ArtistWithAlbums | null }
  //? (2.0.4) the error itself, said by errorNote (app/ErrorNote.tsx) in a listener's words
  | { state: 'failed'; error: unknown }

/** MusicBrainz's albums for the artist: the last answer stays on screen while another is asked for
 *  (`of` says which question it answered - "<mbid>|<studio only>"), so nothing under a finger moves
 *  until the new one lands. */
interface Discography {
  state: 'idle' | 'asking' | 'done' | 'failed'
  groups: ReleaseGroup[] | null
  truncated: boolean
  of: string | null
  message?: string
  /** (2.0.4) the error itself, when one was thrown - said by errorNote (app/ErrorNote.tsx) */
  error?: unknown
  unavailable?: boolean
}


/** What a link to an artist that isn't one says, with nothing to try again. */
export const NOT_AN_ARTIST_LINK = "That isn't a link to an artist."
/** (2.0.4, review) an artist the music server no longer has (an old pin or link): said for a listener, never as
 *  "Navidrome has nothing by that id" - and with no Try again, which can't find them */
export const ARTIST_GONE = "This artist isn't here any more - their albums may have been moved or deleted."

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

/** How long the page's About, Line-up and In your library wait for MusicBrainz and the library to
 *  answer, once the albums are drawn, before they are drawn with what has (2.0.0-player.45) - drawn
 *  under the albums, and in one go, so nothing above them moves and they don't build up in pieces. */
export const ABOUT_WAIT_MS = 3000

/** The library's word on each name it files the artist's albums under (2.0.0-player.45): an answer
 *  of /library/artist, or null for one that couldn't be had - `key` the names it answers, in order. */
interface Summaries {
  key: string
  map: ReadonlyMap<string, ArtistSummary | null>
}

/** Who a page's artist is, chosen with "Which artist is this?" (2.0.0-player.45) - for the visit. */
export interface ChosenArtist {
  mbid: string
  name: string
  disambiguation: string
}

/** What the session keeps of an artist's page, by its id: each answer as it last landed. */
interface KeptArtist {
  foundId: string | null
  /** Navidrome's artist and their albums; undefined until Navidrome has answered */
  library: ArtistWithAlbums | null | undefined
  facts: { mbid: string; facts: ArtistFacts } | null
  studioOnly: boolean
  /** complete answers only, by "<mbid>|<studio only>" */
  discography: Map<string, { groups: ReleaseGroup[]; truncated: boolean }>
  /** the library's word on each of their names (2.0.0-player.45) */
  summaries: Summaries | null
  /** who they are, chosen here this visit (2.0.0-player.45) */
  chosen: ChosenArtist | null
  /** what their pictures on disk are asked with - a new number after each save this visit */
  version: number
}

const keptArtists = new Map<string, KeptArtist>()

/** Forget what the session kept of an artist's page - their albums moved under another name
 *  (2.0.0-player.45), so every answer it holds is of folders that have gone. */
export function forgetKeptArtist(id: string): void {
  keptArtists.delete(id)
}

/** The session's copy of an artist's page, as the newest - made empty the first time. */
function keptArtist(id: string): KeptArtist {
  const entry = keptArtists.get(id) ?? { foundId: null, library: undefined, facts: null, studioOnly: true, discography: new Map(), summaries: null, chosen: null, version: 0 }
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
 * AS THE MAIN PAGE HAD IT (2.0.0-player.45; lib/artistManage.ts): under the albums, once they are
 * drawn and MusicBrainz and the library have answered (or ABOUT_WAIT_MS), in one go - "In your
 * library" (albums, tracks, size, years, the folder, or why there isn't one, from /library/artist for
 * each name the library files them under), "About" (MusicBrainz's facts in full: what tells them
 * apart, "Now: <name>" when the library files them under a name that isn't theirs now, type, where
 * from, Born/Died or Founded/Dissolved with dates, other names, genres, links opening beside the app)
 * and "Line-up", long lists folded. The hero shows their background (fanart.*) and logo (logo.*)
 * where those are on disk. For an admin (App's /deadwax/me): Artist images…, Move albums to <name>,
 * and - where the page says MusicBrainz doesn't know who this is - Which artist is this?, each opening
 * the artist page's panel (ArtistPanel.tsx, App's: a side panel on a desktop, a sheet on a phone).
 * Albums moved (App's onMoved): a page of a name every album of which moved follows them - it
 * becomes the artist's by their MusicBrainz id, App putting its scroll back once it has drawn
 * (onDrawn); any other page (of their name now, or of a name an album stayed under) stays, and is
 * asked again once Navidrome has had time to scan. Pictures saved, it asks for its folder again; an
 * artist chosen, the page is theirs for the visit. Should In your library still be out when the
 * sections are drawn (ABOUT_WAIT_MS), it is drawn last, saying it is looking, so it lands under what
 * is on screen rather than above it; once drawn it stays, and a library that couldn't be read for any
 * of their names says so, with Try again, over what it said before - Artist images… stepped back,
 * saying why (review).
 *
 * Every fetch that draws goes through its own latestOnly(): the library's answer, the facts, the
 * discography, the prefetches, a row's bridge and a chip's pressings - and the library's summaries.
 * A row's or a chip's lookup still out is called off when the page stops being what shows (`shown`),
 * so its late answer opens nothing on whatever tab you went to (review). A page: it reads the
 * player's actions from context.
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
  onManage,
  managing = null,
  refresh = 0,
  onMoved,
  onDrawn,
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
  /** open the artist page's panel (2.0.0-player.45); `opener` the control it gives focus back to */
  onManage?: (request: Omit<ArtistManageRequest, 'key'>, opener: HTMLElement | null) => void
  /** what the panel is open for on this page, null while it isn't */
  managing?: ArtistManageMode | null
  /** a new number: ask Navidrome and the library again (App, once Navidrome has had time to scan a move) */
  refresh?: number
  /** their albums moved under their current name (App): `follow`, this page's name has none left - the
   *  page becomes theirs by their MusicBrainz id; otherwise it stays */
  onMoved?: (from: string, to: { mbid: string; name: string }, follow: boolean) => void
  /** the albums drawn (`all`: and the sections under them) - App puts back a scroll it couldn't yet */
  onDrawn?: (all: boolean) => void
}) {
  const actions = usePlayerActions()
  //? (2.0.0-player.61) what this person may do: Get by Get albums, the managing by theirs
  const access = useAccess()
  const getsAlbums = gets(access.permissions)
  const { pins, known: pinsKnown, canSave } = usePins(true)
  const ref = useMemo(() => artistRef(id), [id])
  const kept = useMemo(() => keptArtist(id), [id])
  const owned = useOwned(true)
  //? (2.0.0-player.52) a library of your own: the page lists the STORE's albums of theirs - Navidrome's, asked as
  //? you - each row saying whether it is yours (lib/artistPage.ts rowLine), and its library facts are the store's
  const personal = hasLibrary()
  //? (2.0.5) the collection - James's word - never "the store"
  const where = personal ? 'the collection' : 'your library'
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
  //? who they are, chosen with "Which artist is this?" - used only when nothing else says (2.0.0-player.45)
  const [chosen, setChosen] = useState<ChosenArtist | null>(kept.chosen)

  const artist = library.state === 'done' ? library.artist : null
  const held: Album[] = artist?.album ?? []
  const said = ref.mbid ?? artistMbid(artist, held, owned?.index ?? null)
  const mbid = said ?? chosen?.mbid ?? null
  const discKey = mbid ? `${mbid}|${studioOnly}` : null

  //? who they are, as MusicBrainz last answered - with the id it answered for: another artist chosen,
  //? the last one's facts are never shown as theirs (review, 2.0.0-player.45)
  const [factsOf, setFactsOf] = useState<{ mbid: string; facts: ArtistFacts } | null>(() => kept.facts)
  const facts = factsOf && factsOf.mbid === mbid ? factsOf.facts : null
  //? MusicBrainz didn't answer for who they are (the id it didn't answer for): said in About, with Try again
  const [factsFailedFor, setFactsFailedFor] = useState<string | null>(null)
  const factsFailed = !!mbid && factsFailedFor === mbid
  const [factsAsks, setFactsAsks] = useState(0)
  //? the library's word on each name it files them under, and a count that asks it again
  const [summaries, setSummaries] = useState<Summaries | null>(kept.summaries)
  const [summaryAsks, setSummaryAsks] = useState(0)
  //? the names the library couldn't say a word about, not one of them (their key): said, with Try again -
  //? what it said before staying (review, 2.0.0-player.45) - and a request for its word out, which Try
  //? again shows
  const [summaryFailedFor, setSummaryFailedFor] = useState<string | null>(null)
  const [summaryAsking, setSummaryAsking] = useState(false)
  //? what their pictures on disk are asked with: a new number after a save, past the browser's cache
  const [version, setVersion] = useState(kept.version)
  //? the long lists, opened
  const [allMembers, setAllMembers] = useState(false)
  const [allLinks, setAllLinks] = useState(false)
  //? About and the rest have waited ABOUT_WAIT_MS: drawn with whatever has answered
  const [aboutWaited, setAboutWaited] = useState(false)
  //? the pictures on disk that wouldn't load: the hero falls back past them
  const [brokenArt, setBrokenArt] = useState<ReadonlySet<string>>(() => new Set())
  //? Navidrome asked afresh by the next find - App's refresh, once a move has been scanned
  const freshFind = useRef(false)
  //? an artist just chosen: focus goes to its Change once drawn (the panel that chose has closed)
  const focusChange = useRef(false)
  const changeButton = useRef<HTMLButtonElement>(null)
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
  const summaryRequests = useMemo(latestOnly, [])

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

  useEffect(() => {
    const timer = setTimeout(() => setAboutWaited(true), ABOUT_WAIT_MS)
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
    //? asked afresh once, after a move Navidrome has since scanned (App's refresh)
    const fresh = freshFind.current
    freshFind.current = false
    libraryArtists(fresh)
      .then((artists) => {
        if (!request.current()) return
        const found = look(artists)
        //? not in a list kept from a while ago: an artist new to the library since isn't in it
        if (found || artistIndexAge() < ARTIST_INDEX_STALE_MS) return settle(found)
        return libraryArtists(true).then((again) => settle(look(again)))
      })
      .catch((reason: unknown) => {
        if (request.current() && !isAbort(reason)) setLibrary({ state: 'failed', error: reason })
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
        if (request.current() && !isAbort(reason) && !quiet) setLibrary({ state: 'failed', error: reason })
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
      setFactsOf(kept.facts)
      setFactsFailedFor(null)
      return
    }
    const request = factsRequests.begin()
    setFactsFailedFor(null)
    getArtistFacts(mbid, request.signal).then(
      (found) => {
        if (!request.current()) return
        kept.facts = { mbid, facts: found }
        setFactsOf(kept.facts)
      },
      (reason: unknown) => {
        //? the line under the name is left out; About says MusicBrainz didn't answer, with Try again
        if (request.current() && !isAbort(reason)) setFactsFailedFor(mbid)
      },
    )
    return () => factsRequests.supersede()
  }, [mbid, factsAsks])

  //? (2.0.0-player.45) every name the library files their albums under, and its word on each - asked
  //? again as the names change (the library's folders, who they are), after a save, and on App's refresh
  const releases = useMemo(() => held.map((album) => album.musicBrainzId ?? '').filter(Boolean), [artist])
  const whoName = artist?.name ?? facts?.name ?? preview?.name ?? null
  const names = useMemo(() => libraryNames(owned?.index ?? null, { mbid, name: whoName, releases }), [owned, mbid, whoName, releases])
  const namesKey = names.join('\n')
  useEffect(() => {
    if (!names.length) {
      summaryRequests.supersede()
      setSummaryAsking(false)
      setSummaryFailedFor(null)
      const none: Summaries = { key: namesKey, map: new Map() }
      kept.summaries = none
      setSummaries(none)
      return
    }
    const request = summaryRequests.begin()
    setSummaryAsking(true)
    Promise.all(names.map((name) => fetchArtist(name, request.signal).then(
      (summary) => [name, summary] as const,
      (reason: unknown) => {
        if (isAbort(reason)) throw reason
        return [name, null] as const
      },
    ))).then(
      (answers) => {
        if (!request.current()) return
        setSummaryAsking(false)
        //? not one name answered (review): no word on them at all - said, with Try again, what it said
        //? before staying; and never kept, so a visit to come asks rather than drawing a failure
        if (answers.every(([, summary]) => summary === null)) {
          setSummaryFailedFor(namesKey)
          return
        }
        const answered: Summaries = { key: namesKey, map: new Map(answers) }
        kept.summaries = answered
        setSummaryFailedFor(null)
        setSummaries(answered)
      },
      () => {},
    )
    return () => summaryRequests.supersede()
  }, [namesKey, summaryAsks])

  //? App's refresh (a move Navidrome has since scanned): Navidrome's artist found afresh and asked
  //? again, and the library's word on their names
  const refreshed = useRef(refresh)
  useEffect(() => {
    if (refreshed.current === refresh) return
    refreshed.current = refresh
    freshFind.current = !ref.navidrome
    if (libraryId) loadLibrary()
    if (!ref.navidrome) setFinds((count) => count + 1)
    setSummaryAsks((count) => count + 1)
  }, [refresh])

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
    const failed = (problem: string, unavailable: boolean, error?: unknown) =>
      setDiscography((before) => ({
        state: 'failed', groups: before.of === key ? before.groups : null, truncated: before.of === key && before.truncated,
        of: before.of === key ? key : null, message: problem, unavailable, ...(error === undefined ? {} : { error }),
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
        //? (2.0.4) the error itself, said by errorNote - never its words as the line
        failed('', reason instanceof MusicBrainzUnavailable, reason)
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
    for (const requests of [findRequests, libraryRequests, factsRequests, discRequests, prefetches, openRequests, getRequests, summaryRequests]) requests.supersede()
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
    //? (2.0.0-player.62) Play is their albums in order, each an album played as one; Shuffle mixes songs
    actions.playTracks(queued(tracks, shuffle ? 'songs' : 'album'), shuffle ? null : 0, shuffle)
    //? (2.0.0-player.65) Play's first album measured for Normalization, after the play (deadwax measures one album
    //? at a time; the next is asked for as it comes up). Shuffle levels song by song, so warms nothing
    if (!shuffle && albums[0]) warmAlbum(albums[0])
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

  /* ===== as the main page had it (2.0.0-player.45): what the library holds, who they are, managing ===== */

  //? the library's word on the names as they are now - a summary of names since changed isn't theirs.
  //? Not one of them read (review): what it last said of these names, else a word on none of them
  const summariesFailed = names.length > 0 && summaryFailedFor === namesKey
  const summaryMap: ReadonlyMap<string, ArtistSummary | null> = summaries && summaries.key === namesKey ? summaries.map
    : summariesFailed ? new Map(names.map((one) => [one, null])) : new Map()
  const summariesKnown = summaries?.key === namesKey || summariesFailed
  const inLibrary = libraryFacts(names.map((name) => summaryMap.get(name)).filter((one): one is ArtistSummary => !!one))
  const folder = imagesFolder(names, facts?.name, summaryMap)
  const folderSummary = folder.name ? summaryMap.get(folder.name) ?? null : null
  const imagesReady = !folder.reason && !!folderSummary?.path
  const moveNames = namesToMove(names, facts?.name)
  //? "Now: <name>": a name the library files them under isn't MusicBrainz's for them now
  const renamed = !!facts?.name && moveNames.length > 0

  //? the hero: their background where it is on disk, else Navidrome's picture - or, once pictures were
  //? saved here, the square on disk (Navidrome's own copy of it is cached); their logo for their name
  const onDisk = (kind: string): string | null => {
    const path = folderSummary?.path
    if (!path || !folderSummary?.art?.[kind]) return null
    const address = artistArtUrl(path, kind, version || undefined)
    return brokenArt.has(address) ? null : address
  }
  const fanart = onDisk('fanart')
  const square = version > 0 || !picture ? onDisk('thumb') : null
  const logo = onDisk('logo')
  const broken = (address: string) => () => setBrokenArt((was) => new Set(was).add(address))

  //? About, Line-up and In your library: drawn under the albums once they are, when MusicBrainz and the
  //? library have answered (or ABOUT_WAIT_MS) - in one go, and they stay drawn
  const libraryHalfKnown = ownedKnown && libraryKnown && (!names.length || summariesKnown)
  const factsKnown = !mbid || facts !== null || factsFailed
  const aboutShown = useRef(false)
  if (drawRows && ((libraryHalfKnown && factsKnown) || aboutWaited)) aboutShown.current = true
  const drawAbout = aboutShown.current
  //? ...In your library still out when they are drawn (ABOUT_WAIT_MS - /library/owned walking a
  //? spun-down array after a restart): drawn LAST, saying it is looking, so it lands under what is on
  //? screen rather than above it (review). And once it has said something, that stays while the
  //? library is asked again (the names changed), as the albums do - and when the library couldn't be
  //? read (review: a failed re-ask took In your library away, About jumping up under the finger)
  const libraryLast = useRef<boolean | null>(null)
  if (drawAbout && libraryLast.current === null) libraryLast.current = !libraryHalfKnown
  const lastInLibrary = useRef<LibraryFacts | null>(null)
  const libraryAnswered = libraryHalfKnown && (!!inLibrary || !summariesFailed)
  if (libraryAnswered) lastInLibrary.current = inLibrary
  const shownLibrary = libraryAnswered ? inLibrary : lastInLibrary.current
  //? ...and once drawn, In your library stays drawn - saying it is looking, or that there is nothing,
  //? rather than going
  const libraryOnScreen = useRef(false)
  if (drawAbout && (shownLibrary || libraryLast.current || summariesFailed)) libraryOnScreen.current = true
  //? Try again on a library that couldn't be read: its word asked for again - once at a time
  const retrySummaries = () => {
    if (!summaryAsking) setSummaryAsks((count) => count + 1)
  }

  //? the albums drawn, and then the sections under them: App puts back a scroll it couldn't as the page
  //? came - a page a move made of another draws nothing on its first frame (review)
  useLayoutEffect(() => {
    if (drawRows) onDrawn?.(drawAbout)
  }, [drawRows, drawAbout])

  const members = folded(facts?.members ?? [], MEMBERS_SHOWN, allMembers)
  const links = folded(facts?.links ?? [], LINKS_SHOWN, allLinks)
  const factRows = aboutRows(facts)
  //? chosen here, and nothing else says who they are: the page says so, with Change - whatever
  //? MusicBrainz has said of them yet, so a choice whose facts won't come can still be changed
  const byChoice = !said && !!chosen && chosen.mbid === mbid
  //? "Now: Ye" on a page of another name; on their page by the name they have now, the other names
  //? the library still files them under (review: "Now: Ye" on Ye's own page said nothing)
  const ownName = !!facts?.name && name === facts.name

  //? an artist just chosen: its Change takes focus once drawn - the panel that chose has closed, and the
  //? "Which artist is this?" it gives focus back to went with the words around it
  useLayoutEffect(() => {
    if (!focusChange.current || !changeButton.current) return
    focusChange.current = false
    changeButton.current.focus({ preventScroll: true })
  })

  /** The artist page's panel, for one of its three jobs - or, open for that already, closed (App). */
  const manage = (mode: ArtistManageMode, event: MouseEvent) => {
    if (!onManage) return
    onManage({
      mode,
      page: id,
      name,
      mbid,
      currentName: facts?.name ?? null,
      moveNames,
      imagesName: folder.name,
      version,
      onMoved: ({ mbid: to, name: now, emptied }) => {
        //? what the session kept of this page and of theirs by id is of folders that have moved
        forgetKeptArtist(id)
        forgetKeptArtist(`${MB_PREFIX}${to}`)
        //? followed only from a page of a name every album of which moved - Navidrome's artist of that
        //? name goes with them; a page of their name now, or of a name an album stayed under, is still
        //? Navidrome's artist, and stays (review: it followed from Ye's own page, and after a move that
        //? left an album behind, onto a page that couldn't find them until Navidrome had scanned)
        const own = artist?.name ?? null
        const follow = ref.navidrome === null || (own !== null && emptied.some((one) => foldName(one) === foldName(own)))
        onMoved?.(id, { mbid: to, name: now }, follow)
      },
      onSaved: () => {
        kept.version += 1
        setVersion(kept.version)
        setSummaryAsks((count) => count + 1)
      },
      onChosen: (match) => {
        kept.chosen = match
        focusChange.current = true
        setChosen(match)
      },
    }, takeOpener(event))
  }
  //? (2.0.0-player.61) each managing control by its permission (lib/permissions.ts artistManaging): Artist images…
  //? and Which artist is this? Edit albums', Move albums to … Look after the library's - with logins off, all
  const may = artistManaging(access.permissions)
  const managesImages = may.images && !!onManage
  const managesWho = may.whichArtist && !!onManage
  const managesMove = may.move && !!onManage

  /** In your library: what the library last said of them - or, drawn last while it is still out, that
   *  it is looking, and once it has answered with nothing, so; couldn't be read, that (with Try again),
   *  over what it said before - with an admin's Artist images… under it. Drawn first, it is drawn only
   *  once it has something to say; once drawn, it stays. */
  const librarySection = !libraryOnScreen.current ? null : (
    <section class="app-artist-section" aria-labelledby="app-artist-library-title" aria-busy={!libraryHalfKnown}>
      <h2 id="app-artist-library-title" class="app-section-title">{personal ? 'In the collection' : 'In your library'}</h2>
      {shownLibrary && summariesFailed && (
        <p class="app-footnote app-artist-stale">
          deadwax couldn't read {where} just now - this is what it said before.{' '}
          <button type="button" class="app-text-button app-artist-retry is-inline" aria-busy={summaryAsking} onClick={retrySummaries}>
            Try again
          </button>
        </p>
      )}
      {shownLibrary ? (
        <dl class="app-group app-artist-list">
          <div class="app-row app-artist-fact">
            <dt class="app-row-label">Albums</dt>
            <dd class="app-row-value">{shownLibrary.albums}</dd>
          </div>
          <div class="app-row app-artist-fact">
            <dt class="app-row-label">Songs</dt>
            <dd class="app-row-value">{shownLibrary.tracks}</dd>
          </div>
          {shownLibrary.size && (
            <div class="app-row app-artist-fact">
              <dt class="app-row-label">Size</dt>
              <dd class="app-row-value">{shownLibrary.size}</dd>
            </div>
          )}
          {shownLibrary.years && (
            <div class="app-row app-artist-fact">
              <dt class="app-row-label">Years</dt>
              <dd class="app-row-value">{shownLibrary.years}</dd>
            </div>
          )}
          <div class="app-row app-artist-fact is-folder">
            <dt class="app-row-label">{shownLibrary.folders.length > 1 ? 'Folders' : 'Folder'}</dt>
            <dd class="app-row-value app-artist-folder">{shownLibrary.folders.length ? shownLibrary.folders.join('\n') : '-'}</dd>
            {shownLibrary.problem && <p class="app-row-detail">{shownLibrary.problem}</p>}
          </div>
        </dl>
      ) : !libraryHalfKnown ? (
        <div class="app-asking" role="status">
          <span class="app-sweep" aria-hidden="true" />
          <span class="app-asking-text">Looking in {where}…</span>
        </div>
      ) : summariesFailed ? (
        <div class="app-search-problem">
          <p class="app-search-empty">deadwax couldn't read {where} just now.</p>
          <button type="button" class="app-button app-artist-retry" aria-busy={summaryAsking} onClick={retrySummaries}>
            Try again
          </button>
        </div>
      ) : (
        <p class="app-search-empty">Nothing of theirs in {where}.</p>
      )}
      {/* couldn't be read: still drawn, stepped back, saying why (review) */}
      {managesImages && (shownLibrary || summariesFailed) && (
        <div class="app-artist-manage">
          {/* aria-disabled, so it keeps focus and says why; a tap while it can't do anything is refused */}
          <button
            type="button"
            class="app-button app-artist-manage-button"
            aria-disabled={imagesReady ? undefined : 'true'}
            aria-pressed={managing === 'images'}
            {...(folder.reason ? { 'aria-describedby': 'app-artist-images-why' } : {})}
            onClick={(event) => {
              if (imagesReady) manage('images', event)
            }}
          >
            Artist images…
          </button>
          {folder.reason && <p id="app-artist-images-why" class="app-footnote app-artist-why">{folder.reason}</p>}
        </div>
      )}
    </section>
  )

  return (
    <section class="app-artist">
      <div class="app-artist-hero">
        {fanart ? (
          <img class="app-artist-picture is-fanart" src={fanart} alt="" decoding="async" onError={broken(fanart)} />
        ) : square ? (
          <img class="app-artist-picture" src={square} alt="" decoding="async" onError={broken(square)} />
        ) : (
          picture && <Cover id={picture} size={800} class="app-artist-picture" />
        )}
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
              onRefused={() => sayPins(pinsUnsaved(seesDetail(accessNow())))}
            />
          )}
        </div>
        <div class="app-artist-names">
          <h1 class="app-artist-name" dir="auto">
            {logo ? <img class="app-artist-logo" src={logo} alt={name} decoding="async" onError={broken(logo)} /> : name}
          </h1>
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
              <p class="app-artist-plays" aria-live="polite">{playsLine(playing.length, inHand.length, settled, library.state, personal)}</p>
              {settled && inHand.length < playing.length && (
                <button type="button" class="app-text-button app-artist-again" onClick={askAgain}>
                  Try again
                </button>
              )}
            </div>
          )}

          {library.state === 'failed' && (
            <div class="pl-notice">
              {errorNote(library.error, { gone: ARTIST_GONE, retry: true })}
              {errorKind(library.error) !== 'not-found' && (
                <button type="button" class="pl-text-button" onClick={tryLibraryAgain}>
                  Try again
                </button>
              )}
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

            {/* (2.0.0-player.61) without Get albums: no Get on a row, and why, once */}
            {drawRows && !getsAlbums && rows.some((row) => row.held === false && row.group) && (
              <p class="app-footnote app-get-off">{GET_OFF}</p>
            )}
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
                        <span class="app-result-title" dir="auto">{row.title}</span>
                        <span class="app-result-line app-artist-line">
                          {row.held === true && (!personal || row.yours !== false) && <CheckIcon class="app-artist-held" />}
                          <span class="app-artist-line-text">{rowLine(row, personal)}</span>
                        </span>
                      </span>
                    </button>
                    {row.held === false && row.group && getsAlbums && (
                      <button
                        type="button"
                        class={`app-result-get${resolving === row.group.id ? ' is-busy' : ''}`}
                        aria-label={`Get ${row.title || 'this album'}`}
                        aria-busy={resolving === row.group.id}
                        onClick={(event) => void getAlbum(row.group!, event)}
                      >
                        {resolving === row.group.id ? 'Getting…' : 'Get'}
                      </button>
                    )}
                  </li>
                ))}
              </ul>
            )}

            {asking ? (
              <div class="app-asking" role="status">
                <span class="app-sweep" aria-hidden="true" />
                <span class="app-asking-text">{discography.state === 'asking' ? 'Loading their albums…' : `Looking in ${where}…`}</span>
              </div>
            ) : discography.state === 'failed' ? (
              <div class="app-search-problem">
                {discography.unavailable ? (
                  <p class="app-search-empty">
                    Their other albums can't be shown right now - try again in a few minutes.
                  </p>
                ) : (
                  //? (2.0.4) anything else in a listener's words (errorNote), its own for whoever runs deadwax
                  errorNote(discography.error ?? new Error(discography.message ?? ''), { class: 'app-search-empty', retry: true })
                )}
                <button type="button" class="app-button" onClick={() => browse(true)}>
                  Try again
                </button>
              </div>
            ) : discography.state === 'done' && discography.truncated ? (
              <p class="app-search-empty">Showing their first 500 albums.</p>
            ) : !mbid && library.state === 'done' && ownedKnown ? (
              <div class="app-artist-unknown">
                <p class="app-search-empty">
                  {held.length
                    ? `Only the albums ${personal ? 'in the collection' : 'you have'} are shown - their other albums can't be found.`
                    : `Nothing of theirs in ${where}, and their albums can't be found.`}
                </p>
                {/* (2.0.0-player.45) the picker's MusicBrainz search, for a shared name or files that don't say */}
                {managesWho && (
                  <button
                    type="button"
                    class="app-button app-artist-manage-button"
                    aria-pressed={managing === 'who'}
                    onClick={(event) => manage('who', event)}
                  >
                    Which artist is this?
                  </button>
                )}
              </div>
            ) : discography.state === 'done' && !rows.length ? (
              <p class="app-search-empty">{studioOnly ? 'No studio albums found - turn off Studio only to see them all.' : 'No other albums found.'}</p>
            ) : null}
          </section>

          {/* (2.0.0-player.45) what the library holds of them, who they are, their line-up - under the
              albums, drawn in one go once they have answered, so nothing above moves as they land; the
              library's half drawn last when it was still out then (libraryLast) */}
          {drawAbout && (
            <div class="app-artist-more">
              {!libraryLast.current && librarySection}

              {mbid && (
                <section class="app-artist-section" aria-labelledby="app-artist-about-title">
                  <h2 id="app-artist-about-title" class="app-section-title">About</h2>
                  {facts?.disambiguation && <p class="app-artist-disambiguation">{facts.disambiguation}</p>}
                  {byChoice && (
                    <p class="app-footnote app-artist-chosen">
                      You chose who this is, for this visit.{' '}
                      {managesWho && (
                        <button
                          ref={changeButton}
                          type="button"
                          class="app-text-button app-artist-change"
                          aria-pressed={managing === 'who'}
                          onClick={(event) => manage('who', event)}
                        >
                          Change
                        </button>
                      )}
                    </p>
                  )}
                  {facts ? (
                    <>
                      {(renamed || factRows.length > 0) && (
                        <dl class="app-group app-artist-list">
                          {renamed && (
                            <div class="app-row app-artist-fact is-now">
                              <dt class="app-row-label">{ownName ? 'Also known here as' : 'Now known as'}</dt>
                              <dd class="app-row-value">{ownName ? listed(moveNames) : facts.name}</dd>
                              {/* the fix for an artist filed under an old name (v0.9.14) */}
                              {managesMove && (
                                <div class="app-artist-now-move">
                                  <button
                                    type="button"
                                    class="app-button app-artist-manage-button"
                                    aria-pressed={managing === 'refile'}
                                    onClick={(event) => manage('refile', event)}
                                  >
                                    Move albums to {facts.name}
                                  </button>
                                </div>
                              )}
                            </div>
                          )}
                          {factRows.map((row) => (
                            <div key={row.label} class="app-row app-artist-fact">
                              <dt class="app-row-label">{row.label}</dt>
                              <dd class="app-row-value">{row.value}</dd>
                            </div>
                          ))}
                        </dl>
                      )}
                      {facts.genres.length > 0 && (
                        <ul class="app-artist-genres" aria-label="Genres">
                          {facts.genres.map((genre) => <li key={genre} class="app-artist-genre">{genre}</li>)}
                        </ul>
                      )}
                      {links.items.length > 0 && (
                        <>
                          <ul class="app-group app-artist-links" aria-label="Links">
                            {links.items.map((link) => (
                              <li key={link.url}>
                                <a class="app-row app-link-row app-artist-link" href={link.url} title={link.url} target="_blank" rel="noopener">
                                  <span class="app-row-label app-artist-link-label">{link.label}</span>
                                  <ChevronRightIcon class="app-chevron" />
                                </a>
                              </li>
                            ))}
                          </ul>
                          {(links.more > 0 || allLinks) && (
                            <button type="button" class="app-text-button app-artist-fold" aria-expanded={allLinks} onClick={() => setAllLinks((was) => !was)}>
                              {allLinks ? 'Fewer links' : `${links.more} more link${links.more === 1 ? '' : 's'}`}
                            </button>
                          )}
                        </>
                      )}
                    </>
                  ) : factsFailed ? (
                    <div class="app-search-problem">
                      <p class="app-search-empty">Artist details can't be loaded right now.</p>
                      <button type="button" class="app-button" onClick={() => setFactsAsks((count) => count + 1)}>
                        Try again
                      </button>
                    </div>
                  ) : (
                    <div class="app-asking" role="status">
                      <span class="app-sweep" aria-hidden="true" />
                      <span class="app-asking-text">Loading…</span>
                    </div>
                  )}
                </section>
              )}

              {members.items.length > 0 && (
                <section class="app-artist-section" aria-labelledby="app-artist-lineup-title">
                  <h2 id="app-artist-lineup-title" class="app-section-title">Line-up</h2>
                  <ul class="app-group app-artist-members">
                    {members.items.map((member, at) => (
                      //? one person can be in a band twice - left, and back - so the place keeps keys apart
                      <li key={`${member.mbid ?? member.name}:${at}`} class={`app-row app-artist-member${member.current ? '' : ' is-past'}`}>
                        <span class="app-artist-member-text">
                          <span class="app-artist-member-name" dir="auto">{member.name}</span>
                          {member.roles.length > 0 && <span class="app-artist-member-roles">{memberRoles(member)}</span>}
                        </span>
                        <span class="app-row-value app-artist-member-years">{memberYears(member)}</span>
                      </li>
                    ))}
                  </ul>
                  {(members.more > 0 || allMembers) && (
                    <button type="button" class="app-text-button app-artist-fold" aria-expanded={allMembers} onClick={() => setAllMembers((was) => !was)}>
                      {allMembers ? 'Fewer members' : `${members.more} earlier member${members.more === 1 ? '' : 's'}`}
                    </button>
                  )}
                </section>
              )}

              {libraryLast.current && librarySection}
            </div>
          )}
        </div>
      )}
    </section>
  )
}
