import { useEffect, useLayoutEffect, useMemo, useRef, useState } from 'preact/hooks'

import { MusicBrainzUnavailable } from '../api/http'
import { fullySearch, getReleaseGroup, searchSongs } from '../api/musicbrainz'
import { navidromeAlbumFor } from '../api/store'
import type { Recording, ReleaseGroup, ReleaseGroupResponse } from '../api/types'
import { heldReleases } from '../lib/idBridge'
import { isAbort, latestOnly } from '../lib/latest'
import { coverAddresses } from '../lib/pressings'
import { creditName } from '../lib/release'
import {
  LIBRARY_SETTLE_MS, MUSICBRAINZ_SETTLE_MS, SEARCH_MAX_CHARS, artistNames, asksMusicBrainzBySettling, musicBrainzOnTyping, searchQuery,
  songSearchQuery, songTitleQuery, type SearchPlan,
} from '../lib/searchQuery'
import {
  albumsToPrefetch, appendPage, artistLine, groupHeld, groupLine, groupPlace, morePageWords, morePages, notInLibrary, searchWords,
  songIndex, topArtist,
} from '../lib/searchResults'
import {
  SONG_ROWS_SHOWN, SONG_SEARCH_LIMIT, appendSongs, foldLabel, groupSongs, moreSongsWords, namedAlbum, songAlbumBands, songAlbumHeldReleases,
  songAlbumHolding, songAlbumLine, songLine, type Song as FoundSong, type SongAlbum, type SongEvidence,
} from '../lib/songs'
import { navidromePlace, navidromeYours } from '../lib/whose'
import {
  dropPrefetch, prefetchAlbum, rememberPlayed, searchLibrary, toQueueTrack,
  type Album, type AlbumWithSongs, type Artist, type LibraryResults, type NavidromeStatus, type Song,
} from '../player/api'
import { Cover } from '../player/Cover'
import { ChevronDownIcon, PlayIcon, SearchIcon } from '../player/icons'
import { ArchiveCover } from './ArchiveCover'
import { usePlayerActions } from './context'
import { NeedsNavidrome } from './NeedsNavidrome'
import { keep, kept, usualGet } from './pressingLists'
import { onSearchSubmitted, onSearchTyped, shareSearchText } from './searchBox'
import type { GetRequest } from './Sources'
import { useGetSettings } from './useGetSettings'
import { hasLibrary } from './useMyLibrary'
import { ownedNow, refreshOwned, useOwned } from './useOwned'
import { takeOpener } from './useSheet'

/** How many albums MusicBrainz is asked for: a screenful, with room for the ones you hold. */
export const MUSICBRAINZ_LIMIT = 12

/**
 * How long MusicBrainz's answer waits for the library's (asked beside it) before it is drawn
 * anyway: what is held is left out BEFORE the list is drawn, never taken out from under a finger.
 */
export const OWNED_WAIT_MS = 1500

const message = (error: unknown) => (error instanceof Error ? error.message : String(error))
const wait = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms))

/** "More from MusicBrainz" (2.0.0-player.50): the next page asked for, its failure, or what the last one brought. */
type MorePage =
  | { state: 'idle' }
  | { state: 'asking' }
  | { state: 'failed'; message: string; unavailable: boolean }
  //? the rows the last page added, and how many of its new albums the library holds (lib/searchResults.ts)
  | { state: 'added'; added: number; held: number }

type Musicbrainz =
  | { state: 'idle' }
  | { state: 'searching'; text: string }
  //? `shown`: the groups less the held ones, worked out once as the list was drawn (notInLibrary).
  //? `query` is what MusicBrainz was asked (the free text, when a fielded read found nothing), and the
  //? next page is asked by it from `nextOffset`; `count` is MusicBrainz's total, `last` the last page's size
  | {
    state: 'done'; text: string; plan: SearchPlan; groups: ReleaseGroup[]; shown: ReleaseGroup[]
    query: string; nextOffset: number; count: number | null; last: number; more: MorePage
  }
  | { state: 'failed'; text: string; message: string; unavailable: boolean }

/** More songs (2.0.0-player.53): the next page asked, its failure, what it brought - or the songs already in
 *  hand shown (`shown`) */
type MoreSongs =
  | { state: 'idle' }
  | { state: 'asking' }
  | { state: 'failed'; message: string; unavailable: boolean }
  | { state: 'added'; added: number; grown: number }
  | { state: 'shown'; added: number }

/** The songs half's answer (2.0.0-player.53). `idle` draws nothing - nothing asked yet, or the box read as an
 *  artist alone. `recordings` are every page's so far (lib/songs.ts merges them into `songs`); `visible` how
 *  many songs show; `query` what MusicBrainz was asked (the words typed as one title, when a fielded read fell
 *  back). `late`: it landed after the albums were drawn under it - folded into the line that was asking, one
 *  height whatever it holds, so nothing drawn below moves (review) - until a tap opens it */
type Songs =
  | { state: 'idle' }
  | { state: 'searching'; text: string }
  | {
    state: 'done'; text: string; query: string; recordings: Recording[]; songs: FoundSong[]; visible: number
    nextOffset: number; count: number | null; last: number; more: MoreSongs; late: boolean
  }
  | { state: 'failed'; text: string; message: string; unavailable: boolean; late: boolean }

/**
 * The Search tab (2.0.0-player.13): one box, the library first, then MusicBrainz.
 *
 * James: "One search box: library first, then MusicBrainz; an album you don't have opens like one
 * you do". The boards are Search.dc.html (this) and Request.dc.html (the album you don't have).
 *
 *  - THE LIBRARY HALF is Navidrome's search3 (deadwax's /navidrome/search), LIBRARY_SETTLE_MS after
 *    typing stops. An artist whose name is what was typed is the Top result; then the other artists
 *    found, albums, which open their page (asking for its songs as the finger lands, as a tile
 *    does), and songs. An artist - the top result or a row - opens their page (2.0.0-player.17).
 *  - A SONG PLAYS WITHIN ITS ALBUM once that album is in hand: the first SONG_ALBUMS_PREFETCHED
 *    distinct albums of the songs found are asked for as the answer lands (the album page's own
 *    prefetch), and a song's tap then plays its album from that song - playTracks straight from
 *    the tap, nothing awaited, the queue already built (the gesture rule; app-rules.sim.cjs). Before
 *    its album is in hand the tap opens the album instead, where Play is one tap away. The play icon
 *    on a row says which it will do.
 *  - THE MUSICBRAINZ HALF, "Not in your library yet": the box read by lib/searchQuery.ts (an artist
 *    you have at either end is the album by them, an artist alone is their albums, anything else is
 *    free text), on Enter or MUSICBRAINZ_SETTLE_MS after typing stops with MUSICBRAINZ_MIN_CHARS or
 *    more, without the releases (`releases=false`: a group's pressings are the album page's
 *    business). A read that finds nothing is asked again as free text, as the metadata editor does.
 *    Albums the library holds - by release-group id (lib/owned.ts over /library/owned) - are left
 *    out: they're in the half above. That is worked out once, as the list is drawn - the answer
 *    waits up to OWNED_WAIT_MS for the library's, asked beside it - and a later answer marks a row
 *    held rather than taking it away from under a finger. A box cut back below
 *    MUSICBRAINZ_MIN_CHARS drops what the longer text found (musicBrainzOnTyping). A tap opens the
 *    album you don't have - or, on a row found held after it was drawn, the album you have
 *    (2.0.0-player.17's id bridge: Navidrome's album for a release you hold, through its own
 *    latestOnly), the album you don't have when Navidrome hasn't found it.
 *  - A GET CHIP on each of those rows (2.0.0-player.15): the usual pressing of the album - the one
 *    its page opens on, and a main-page card's Find downloads (representativeRelease over every
 *    pressing, from /search_musicbrainz/release_group or the session's lists, through its own
 *    latestOnly so only the newest tap opens anything) - in the Sources sheet, as the page's "Get the
 *    album" would. MusicBrainz unable to list the pressings: the album as a whole, as the main page's
 *    card falls back to, and the sheet says so. Not on a row the library turned out to hold. That
 *    lookup can take seconds (every pressing with its tracklist, at MusicBrainz's pace), so it is
 *    called off - and the chip says Get again - the moment you move on: the box changing, or the
 *    tab's root no longer what shows (App's `active`: another tab, a page opened over it, Now
 *    Playing, the sheet). A late answer then opens nothing over what you went to (review).
 *  - MORE FROM MUSICBRAINZ (2.0.0-player.50): MUSICBRAINZ_LIMIT is a screenful, and under the rows a
 *    button asks for the next one - the same search by offset (the route's own paging), appended below,
 *    so nothing drawn moves, with held albums left out as the first page leaves them. It shows while
 *    MusicBrainz's count says more match, up to the route's bound (MUSICBRAINZ_OFFSET_MAX), then says
 *    to narrow the search. A page whose albums are all held says so; a failure says why, and the
 *    button tries again. Through the half's own latestOnly - a new search calls it off.
 *
 * The albums of the songs found are asked for KEPT (prefetchAlbum's `keep`): a tile or an album
 * row pressed and scrolled shares the ask, and must not call off the one a song's tap waits for.
 *
 * Each half's answers go through its own latestOnly(): a superseded search never draws, and its
 * fetch is called off. The Navidrome gate covers the library half alone - MusicBrainz works with
 * Navidrome unset or down. A page: it reads the player's actions from context.
 *
 * SONGS ON MUSICBRAINZ (2.0.0-player.53, step 7 of the multi-user plan): people often know a song, not the
 * album it is on. Beside each album search, MusicBrainz's recordings for the box read the same way (a title
 * beside an artist you have is that song by them - falling back to the words typed as one title - else the
 * words typed; an artist alone asks nothing), one request a page (/search_musicbrainz/songs) whose answer
 * already holds the albums each song is on. The recordings of one title by one credit are one SONG
 * (lib/songs.ts says why, from real answers), drawn ABOVE the albums - a phone shows them first - but only
 * SONG_ROWS_SHOWN of them, so an album's words still show the albums on the first screen; More shows the
 * rest, then asks for the next page. A search that finds no song draws no section: the albums answer for the
 * words. The album half is as it was - its request first, drawn when it always was, never waiting for the
 * songs (review) - so songs landing after the albums are drawn come FOLDED into the line that was asking,
 * one height whatever it holds ("Show songs", or why there are none), and nothing drawn below moves. A song's
 * tap EXPANDS it (aria-expanded): Albums and EPs, then Singles, then the compilations, live albums,
 * soundtracks and broadcasts under one fold that opens; an album opens the album you don't have on a pressing
 * with the song, the song marked (App's openSongAlbum) - or, holding a pressing with the song, the album you
 * have (openSongAlbum: the id bridge, as a held row opens, or the library half's own album for it). What you
 * hold of it is told by the releases the song was found on, then by the library half's songs and the album's
 * pressings when the session has them (lib/songs.ts SongEvidence, second review); a pressing none of them
 * vouches for reads "a pressing in your library", and its tap looks at the album's pressings before opening
 * either page. Through its own latestOnly; a new search, or the box cut back below three characters, calls it
 * off and empties it, as the album half's rules do.
 *
 * WITH LOGINS ON (2.0.0-player.52, step 6 of the multi-user plan) - for somebody with a library of their own -
 * the library half is the STORE: Navidrome's search3, asked as you, finds everything deadwax holds, so it is
 * titled "In the store" and each album row says whether it is in your library or only in the store
 * (lib/whose.ts navidromeYours: starred by you, or held by your library), an artist's count of albums is
 * the store's; the MusicBrainz half, "Not in the store yet", is "not here? find it" - what deadwax doesn't
 * have - and a row the store turns out to hold says whose it is. With logins off every word is as it was.
 */
export function Search({
  shown,
  active,
  status,
  onRetry,
  onOpenAlbum,
  onOpenGroup,
  onOpenSongAlbum,
  onOpenArtist,
  onGet,
}: {
  /** the tab has been shown at least once: what the library holds is asked then */
  shown: boolean
  /** the tab's root is what shows, with nothing over it - a Get chip's lookup is called off when it isn't */
  active: boolean
  status: NavidromeStatus | null
  onRetry: () => void
  onOpenAlbum: (album: Album) => void
  onOpenGroup: (group: ReleaseGroup) => void
  /** an album a song is on (2.0.0-player.53): the album you don't have, on a pressing with the song's
   *  recordings, the song marked */
  onOpenSongAlbum: (album: { id: string; title: string }, song: readonly string[]) => void
  /** an artist's page (2.0.0-player.17) */
  onOpenArtist: (artist: Artist) => void
  /** a row's Get: open the Sources sheet for its usual pressing, focus given back to `opener` */
  onGet: (request: Omit<GetRequest, 'key'>, opener: HTMLElement | null) => void
}) {
  const actions = usePlayerActions()
  //? asked the first time the tab shows - not as the app starts, when it is mounted hidden
  const owned = useOwned(shown)
  //? (2.0.0-player.52) a library of your own: the library half is the store, its rows marked yours or not
  const personal = hasLibrary()
  const words = searchWords(personal)
  //? You > Getting albums, asked as the tab first shows, so a Get knows them by the time it is tapped
  useGetSettings(shown)
  const input = useRef<HTMLInputElement>(null)

  const [text, setText] = useState('')
  const query = text.trim()

  const [library, setLibrary] = useState<{ text: string; results: LibraryResults } | null>(null)
  const [libraryError, setLibraryError] = useState<string | null>(null)
  //? the albums of the songs found, once in hand: what lets a song's tap play
  const [ready, setReady] = useState<ReadonlyMap<string, AlbumWithSongs>>(new Map())
  const [musicbrainz, setMusicbrainz] = useState<Musicbrainz>({ state: 'idle' })
  const [songs, setSongs] = useState<Songs>({ state: 'idle' })
  //? which songs are open, and which songs' folds (by song key) - closed again by a new answer
  const [openSongs, setOpenSongs] = useState<ReadonlySet<string>>(new Set())
  const [openFolds, setOpenFolds] = useState<ReadonlySet<string>>(new Set())

  const libraryRequests = useMemo(latestOnly, [])
  const musicRequests = useMemo(latestOnly, [])
  //? the songs half's own (2.0.0-player.53): a new search calls the old one off, as each half's does
  const songRequests = useMemo(latestOnly, [])
  //? a Get chip's lookup of the album's pressings: only the newest tap opens the sheet
  const getRequests = useMemo(latestOnly, [])
  const [resolving, setResolving] = useState<string | null>(null)
  //? a row found held after it was drawn: the album you have, asked of the id bridge
  const heldRequests = useMemo(latestOnly, [])
  const [opening, setOpening] = useState<string | null>(null)
  //? what each half was last asked, so Enter and the pause after it don't ask twice
  const asked = useRef<string | null>(null)
  const libraryAsked = useRef<string | null>(null)
  //? the text the songs were asked for (with how it read): an album Try again, or Enter after the pause,
  //? doesn't ask them twice
  const songsFor = useRef<string | null>(null)
  //? the text whose album answer is on the screen (drawn, or failing) - set once it has been drawn: songs
  //? landing after it come folded, so nothing drawn under them moves (review)
  const albumsShown = useRef<string | null>(null)
  //? what the asks read when a pause ends: this render's, never the one that started the pause
  const navidromeOk = useRef(false)
  navidromeOk.current = !!status?.ok
  //? More's page landed while its button had focus: the first row it brought, should the button go with
  //? that page (review) - see the layout effect under askMore
  const moreFocus = useRef<number | null>(null)
  const moreSongsFocus = useRef<number | null>(null)
  //? "Show songs" tapped with focus on it: the first song gets focus as the button goes
  const showSongsFocus = useRef(false)
  const musicSection = useRef<HTMLElement>(null)
  const songSection = useRef<HTMLElement>(null)
  const artistsKnown = useRef<string[]>([])
  artistsKnown.current = [...(owned?.artists ?? []), ...(library?.results.artists ?? []).map((artist) => artist.name)]

  function askLibrary(term: string) {
    if (!navidromeOk.current) return
    libraryAsked.current = term
    const request = libraryRequests.begin()
    searchLibrary(term, request.signal).then(
      (results) => {
        if (!request.current()) return
        setLibrary({ text: term, results })
        setLibraryError(null)
        for (const id of albumsToPrefetch(results.songs)) {
          prefetchAlbum(id, true).then(
            (album) => {
              if (request.current()) setReady((before) => new Map(before).set(id, album))
            },
            () => {},
          )
        }
      },
      (reason: unknown) => {
        if (!request.current() || isAbort(reason)) return
        libraryAsked.current = null
        setLibraryError(message(reason))
      },
    )
  }

  async function askMusicBrainz(term: string) {
    const plan = searchQuery(term, artistNames(artistsKnown.current))
    if (!plan) return
    asked.current = term
    const ownedAnswered = refreshOwned()
    const request = musicRequests.begin()
    setMusicbrainz({ state: 'searching', text: term })
    const first = fullySearch(plan.query, MUSICBRAINZ_LIMIT, false, request.signal)
    //? (2.0.0-player.53) the songs, asked beside the albums - after the album half's own request, which goes
    //? first as it always did - and drawn above them; never waited for, so the albums are drawn when they
    //? always were (review), and songs slower than they are come folded (askSongs' `late`)
    askSongs(term, plan, ownedAnswered, true)
    try {
      let query = plan.query
      let found = await first
      //? a read that finds nothing - an artist's name that happens to start a title - is asked
      //? again as the words typed, as the metadata editor falls back to free text
      if (!found['release-groups']?.length && plan.kind !== 'free' && request.current()) {
        query = term.split(/\s+/).join(' ')
        found = await fullySearch(query, MUSICBRAINZ_LIMIT, false, request.signal)
      }
      const groups = found['release-groups'] ?? []
      //? the library's answer to go with it, a moment at most: what it holds is left out before the
      //? list is drawn, and never taken away once it is
      if (request.current()) await Promise.race([ownedAnswered, wait(OWNED_WAIT_MS)])
      if (!request.current()) return
      setMusicbrainz({ state: 'done', text: term, plan, groups, shown: notInLibrary(groups, ownedNow()?.index ?? null),
        query, nextOffset: groups.length, count: typeof found.count === 'number' ? found.count : null, last: groups.length, more: { state: 'idle' } })
    } catch (reason) {
      if (!request.current() || isAbort(reason)) return
      asked.current = null
      setMusicbrainz({ state: 'failed', text: term, message: message(reason), unavailable: reason instanceof MusicBrainzUnavailable })
    }
  }

  /**
   * "More from MusicBrainz" (2.0.0-player.50): the next MUSICBRAINZ_LIMIT of the same search, by
   * offset, appended below the rows already drawn - nothing above them moves - with the albums the
   * library holds left out as the first page leaves them (appendPage). Through the MusicBrainz half's
   * own latestOnly: a new search, or the box cut back, calls it off, and an answer for a search no
   * longer shown draws nothing.
   */
  async function askMore() {
    const was = musicbrainz
    if (was.state !== 'done' || was.more.state === 'asking') return
    const term = was.text
    const request = musicRequests.begin()
    const asking = (now: Musicbrainz): now is Extract<Musicbrainz, { state: 'done' }> => now.state === 'done' && now.text === term
    setMusicbrainz((now) => (asking(now) ? { ...now, more: { state: 'asking' } } : now))
    try {
      const found = await fullySearch(was.query, MUSICBRAINZ_LIMIT, false, request.signal, was.nextOffset)
      if (!request.current()) return
      const page = found['release-groups'] ?? []
      const button = musicSection.current?.querySelector('.app-search-more') ?? null
      moreFocus.current = button && typeof document !== 'undefined' && document.activeElement === button ? was.shown.length : null
      setMusicbrainz((now) => {
        if (!asking(now)) return now
        const appended = appendPage(now.groups, now.shown, page, ownedNow()?.index ?? null)
        return {
          ...now, groups: appended.groups, shown: appended.shown, nextOffset: now.nextOffset + page.length, last: page.length,
          count: typeof found.count === 'number' ? found.count : now.count, more: { state: 'added', added: appended.added, held: appended.held },
        }
      })
    } catch (reason) {
      if (!request.current() || isAbort(reason)) return
      setMusicbrainz((now) => (asking(now)
        ? { ...now, more: { state: 'failed', message: message(reason), unavailable: reason instanceof MusicBrainzUnavailable } }
        : now))
    }
  }

  /**
   * Songs on MusicBrainz (2.0.0-player.53): the recordings for the box as the album half read it
   * (songSearchQuery - an artist's name alone asks nothing), one page of SONG_SEARCH_LIMIT, merged into songs
   * (lib/songs.ts). A title beside an artist that finds no song by them is asked again as the words typed, as
   * ONE title (songTitleQuery) - never the words loose, which match titles alone and brought strangers' songs
   * named after the artist above an album's words (review); free text isn't asked twice. Waits for the library
   * as the albums do, so what you hold is marked as the rows are drawn. `beside`: asked beside the albums -
   * landing after they were drawn under it, it comes folded (`late`), so nothing drawn below moves; asked
   * again by its own Try again it is what was asked for, and opens. The text asked for is kept (with how it
   * read), so the album half's Try again, or Enter after the pause, asks it nothing more - unless it failed.
   */
  function askSongs(term: string, plan: SearchPlan, ownedAnswered: Promise<unknown>, beside: boolean): void {
    const query = songSearchQuery(term, plan)
    //? the words and how they read: Enter after the library has named an artist it didn't know asks afresh
    const key = `${term}\n${query ?? ''}`
    if (songsFor.current === key) return
    songsFor.current = key
    const request = songRequests.begin()
    if (!query) {
      setSongs({ state: 'idle' })
      return
    }
    setSongs({ state: 'searching', text: term })
    void (async () => {
      try {
        let asked = query
        let found = await searchSongs(query, SONG_SEARCH_LIMIT, request.signal)
        const again = plan.kind === 'album-by-artist' ? songTitleQuery(term) : null
        if (!found.recordings?.length && again && request.current()) {
          asked = again
          found = await searchSongs(again, SONG_SEARCH_LIMIT, request.signal)
        }
        if (request.current()) await Promise.race([ownedAnswered, wait(OWNED_WAIT_MS)])
        if (!request.current()) return
        const recordings = found.recordings ?? []
        const late = beside && albumsShown.current === term
        setOpenSongs(new Set())
        setOpenFolds(new Set())
        setSongs({ state: 'done', text: term, query: asked, recordings, songs: groupSongs(recordings), visible: late ? 0 : SONG_ROWS_SHOWN,
          nextOffset: recordings.length, count: typeof found.count === 'number' ? found.count : null, last: recordings.length, more: { state: 'idle' }, late })
      } catch (reason) {
        if (!request.current() || isAbort(reason)) return
        songsFor.current = null
        setSongs({ state: 'failed', text: term, message: message(reason), unavailable: reason instanceof MusicBrainzUnavailable,
          late: beside && albumsShown.current === term })
      }
    })()
  }

  /** The songs half asked again - its own Try again: the box as it reads now, the library beside it. */
  function askSongsAgain(term: string) {
    const plan = searchQuery(term, artistNames(artistsKnown.current))
    if (!plan) return
    songsFor.current = null
    askSongs(term, plan, refreshOwned(), false)
  }

  /** "Show songs": songs folded as they landed after the albums opened - a few of them, More for the rest. */
  function showSongs() {
    const button = songSection.current?.querySelector('.app-song-show') ?? null
    showSongsFocus.current = !!button && typeof document !== 'undefined' && document.activeElement === button
    setSongs((now) => (now.state === 'done' && now.late ? { ...now, late: false, visible: SONG_ROWS_SHOWN } : now))
  }

  /**
   * More songs (2.0.0-player.53): the songs already in hand shown first - the section opens on a few - then
   * the next SONG_SEARCH_LIMIT recordings of the same search, by offset, merged in: a later take of a song
   * shown adds its albums to that song in place, a new song comes after the rest, nothing drawn moves.
   * Through the songs half's own latestOnly: a new search, or the box cut back, calls it off.
   */
  async function askMoreSongs() {
    const was = songs
    if (was.state !== 'done' || was.more.state === 'asking') return
    const term = was.text
    const asking = (now: Songs): now is Extract<Songs, { state: 'done' }> => now.state === 'done' && now.text === term
    const button = songSection.current?.querySelector('.app-search-more') ?? null
    const focused = !!button && typeof document !== 'undefined' && document.activeElement === button
    if (was.visible < was.songs.length) {
      moreSongsFocus.current = focused ? was.visible : null
      setSongs((now) => (asking(now) ? { ...now, visible: now.songs.length, late: false, more: { state: 'shown', added: now.songs.length - now.visible } } : now))
      return
    }
    const request = songRequests.begin()
    setSongs((now) => (asking(now) ? { ...now, more: { state: 'asking' } } : now))
    try {
      const found = await searchSongs(was.query, SONG_SEARCH_LIMIT, request.signal, was.nextOffset)
      if (!request.current()) return
      const page = found.recordings ?? []
      const still = songSection.current?.querySelector('.app-search-more') ?? null
      moreSongsFocus.current = still && typeof document !== 'undefined' && document.activeElement === still ? was.songs.length : null
      setSongs((now) => {
        if (!asking(now)) return now
        //? the songs drawn keep their places, every other song after them (review)
        const merged = appendSongs(now.recordings, page, now.songs)
        return {
          ...now, recordings: merged.recordings, songs: merged.songs, visible: merged.songs.length, nextOffset: now.nextOffset + page.length, late: false,
          last: page.length, count: typeof found.count === 'number' ? found.count : now.count, more: { state: 'added', added: merged.added, grown: merged.grown },
        }
      })
    } catch (reason) {
      if (!request.current() || isAbort(reason)) return
      setSongs((now) => (asking(now)
        ? { ...now, more: { state: 'failed', message: message(reason), unavailable: reason instanceof MusicBrainzUnavailable } }
        : now))
    }
  }

  /** The songs half called off and emptied - the box emptied, or cut back below what asks by itself. */
  function dropSongs() {
    songRequests.supersede()
    songsFor.current = null
    setSongs((was) => (was.state === 'idle' ? was : { state: 'idle' }))
  }

  //? typing: the library after a short pause, MusicBrainz after a longer one - and nothing at all,
  //? both halves called off, for an empty box. Cut back below MUSICBRAINZ_MIN_CHARS, MusicBrainz's
  //? answer for the longer text goes (nothing would ever replace it), its search called off too.
  useEffect(() => {
    //? the box changed: a Get chip's lookup for what it said before opens nothing now
    standDown()
    const musicBrainz = musicBrainzOnTyping(query, asked.current)
    if (musicBrainz === 'clear') {
      libraryRequests.supersede()
      musicRequests.supersede()
      asked.current = null
      libraryAsked.current = null
      setLibrary(null)
      setLibraryError(null)
      setReady(new Map())
      setMusicbrainz({ state: 'idle' })
      dropSongs()
      return
    }
    if (musicBrainz === 'drop') {
      musicRequests.supersede()
      asked.current = null
      setMusicbrainz((was) => (was.state === 'idle' ? was : { state: 'idle' }))
      dropSongs()
    }
    const forLibrary = setTimeout(() => {
      if (libraryAsked.current !== query) askLibrary(query)
    }, LIBRARY_SETTLE_MS)
    const forMusicBrainz = musicBrainz === 'settle'
      ? setTimeout(() => {
        if (asked.current !== query) void askMusicBrainz(query)
      }, MUSICBRAINZ_SETTLE_MS)
      : null
    return () => {
      clearTimeout(forLibrary)
      if (forMusicBrainz !== null) clearTimeout(forMusicBrainz)
    }
  }, [query])

  //? Navidrome coming back while the box holds something: the library half asks then
  useEffect(() => {
    if (status?.ok && query) askLibrary(query)
  }, [status?.ok])

  /** A Get chip's lookup still out is called off, and its chip says Get again - and so is a held
   *  row's look for the album you have, which would otherwise open it wherever you had gone. */
  function standDown() {
    getRequests.supersede()
    setResolving(null)
    heldRequests.supersede()
    setOpening(null)
  }

  //? the tab's root no longer what shows - another tab, a page over it, Now Playing or the sheet:
  //? a chip's lookup still out must not open the sheet over where you went (review)
  useEffect(() => {
    if (!active) standDown()
  }, [active])

  //? the album half's answer once it has been drawn (done, or failing) - what songs landing later fold for
  useEffect(() => {
    albumsShown.current = musicbrainz.state === 'done' || musicbrainz.state === 'failed' ? musicbrainz.text : null
  }, [musicbrainz])

  //? leaving the app calls both halves off
  useEffect(() => () => {
    libraryRequests.supersede()
    musicRequests.supersede()
    songRequests.supersede()
    getRequests.supersede()
    heldRequests.supersede()
  }, [])

  /**
   * A MusicBrainz row the library turned out to hold: Navidrome's album for a release of it you
   * hold - the album you have - else, Navidrome not having found it (or not answering), the album you
   * don't have, which says "in your library".
   */
  function openGroup(group: ReleaseGroup) {
    const releases = heldReleases(owned?.index ?? null, group.id)
    if (!releases.length) {
      onOpenGroup(group)
      return
    }
    const request = heldRequests.begin()
    setOpening(group.id)
    navidromeAlbumFor(releases, request.signal).then(
      (album) => {
        if (!request.current()) return
        setOpening(null)
        //? drawn with its credited artist, so the album page's artist line holds its place as it loads
        const artist = creditName(group['artist-credit'])
        if (album) onOpenAlbum({ id: album, name: group.title ?? '', ...(artist ? { artist } : {}) })
        else onOpenGroup(group)
      },
      (reason: unknown) => {
        if (!request.current() || isAbort(reason)) return
        setOpening(null)
        onOpenGroup(group)
      },
    )
  }

  /** What else says a pressing you hold has a song (lib/songs.ts SongEvidence, second review): the library half's
   *  songs as last answered, and the pressings of any album the session already has (pressingLists). */
  const evidence: SongEvidence = { heard: library?.results.songs ?? null, pressings: (id) => kept(id)?.releases ?? null }

  /**
   * An album a song is on (2.0.0-player.53): the album you don't have, opened on a pressing with the song's
   * recordings, the song marked (App) - or the album you have when you hold the song on it:
   *  - a pressing the song was found on, or whose kept tracklist has it: Navidrome's album for it from the id
   *    bridge, through the held rows' latestOnly, as a held row opens it;
   *  - a pressing the library half's search shows the song on: that album of Navidrome's, at once;
   *  - only a pressing nothing vouches for (second review: Dummy's 1994 CD has Roads as a recording the
   *    search's first page doesn't bring; The Slow Rush's usual CD hasn't Patience at all) - the album's
   *    pressings asked first, the row busy (they are the album page's own, kept, so it then asks nothing):
   *    a held pressing with the song opens the album you have, through the bridge; none, the album you don't
   *    have, on a pressing with it.
   * Navidrome not having found it, the bridge failing or MusicBrainz failing: the album you don't have. The
   * box changing, or the tab no longer showing, calls any of it off (standDown).
   */
  function openSongAlbum(song: FoundSong, album: SongAlbum) {
    const index = owned?.index ?? null
    const key = `${song.key}\n${album.id}`
    const open = () => onOpenSongAlbum({ id: album.id, title: album.title }, album.recordings)
    const yours = (releases: readonly string[], request = heldRequests.begin()) => {
      setOpening(key)
      navidromeAlbumFor(releases, request.signal).then(
        (found) => {
          if (!request.current()) return
          setOpening(null)
          if (found) onOpenAlbum({ id: found, name: album.title, ...(album.credit ? { artist: album.credit } : {}) })
          else open()
        },
        (reason: unknown) => {
          if (!request.current() || isAbort(reason)) return
          setOpening(null)
          open()
        },
      )
    }
    const releases = songAlbumHeldReleases(index, album, song, evidence)
    if (releases.length) {
      yours(releases)
      return
    }
    const holding = songAlbumHolding(index, album, song, evidence)
    if (holding.albums.length) {
      //? superseding any look still out, so a late one opens nothing over this
      heldRequests.supersede()
      setOpening(null)
      onOpenAlbum({ id: holding.albums[0]!, name: album.title, ...(album.credit ? { artist: album.credit } : {}) })
      return
    }
    //? nothing held - or the pressings already kept, and none you hold has the song: the album you don't have
    if (!holding.other.length || kept(album.id)) {
      open()
      return
    }
    const request = heldRequests.begin()
    setOpening(key)
    getReleaseGroup(album.id, request.signal).then(
      (found) => {
        if (!request.current()) return
        //? only a complete list is kept (pressingLists' rule) - a broken-off one still says what it says
        if (!found.problem) keep(album.id, found)
        const held = songAlbumHeldReleases(ownedNow()?.index ?? index, album, song, { ...evidence, pressings: () => found.releases })
        if (held.length) {
          yours(held, request)
          return
        }
        setOpening(null)
        open()
      },
      (reason: unknown) => {
        if (!request.current() || isAbort(reason)) return
        setOpening(null)
        open()
      },
    )
  }

  const toggle = (set: (change: (was: ReadonlySet<string>) => ReadonlySet<string>) => void, key: string) =>
    set((was) => {
      const next = new Set(was)
      if (next.has(key)) next.delete(key)
      else next.add(key)
      return next
    })

  /**
   * A row's Get: the album's usual pressing - from the session's lists, else asked of MusicBrainz -
   * in the Sources sheet. The chip takes focus in the tap (the WebKit rule), so the sheet has it to
   * give back as it closes; MusicBrainz failing, or breaking the list off, is the album as a whole.
   */
  async function getAlbum(group: ReleaseGroup, event: MouseEvent) {
    const opener = takeOpener(event)
    const request = getRequests.begin()
    let pressings: ReleaseGroupResponse | null = kept(group.id)
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
    onGet(usualGet(group, pressings), opener)
  }

  const submit = (event: Event) => {
    event.preventDefault()
    if (!query) return
    askLibrary(query)
    void askMusicBrainz(query)
    //? the keyboard goes, so the answers have the screen
    input.current?.blur()
  }

  //? The desktop's search field is the sidebar's (2.0.0-player.19, app/searchBox.ts), and this box
  //? isn't drawn there: what this box says is shared with it, its typing is this box's, and its
  //? Enter is this form's submit - so the search, its pacing and its guards stay this tab's alone.
  useEffect(() => shareSearchText(text), [text])
  useEffect(() => onSearchTyped(setText), [])
  const submitNow = useRef(() => {})
  submitNow.current = () => {
    if (!query) return
    askLibrary(query)
    void askMusicBrainz(query)
  }
  useEffect(() => onSearchSubmitted(() => submitNow.current()), [])

  /** A song's tap: its album from that song when the album is in hand; otherwise open the album. */
  const playSong = (song: Song) => {
    const album = song.albumId ? ready.get(song.albumId) : undefined
    const at = album ? songIndex(album.song, song.id) : -1
    if (album && at >= 0) {
      rememberPlayed(album)
      actions.playTracks(album.song!.map((each) => toQueueTrack(each, album)), at)
      return
    }
    if (song.albumId) {
      onOpenAlbum({
        id: song.albumId,
        name: song.album ?? '',
        ...(song.artist ? { artist: song.artist } : {}),
        ...(song.coverArt ? { coverArt: song.coverArt } : {}),
      })
    }
  }

  const results = library?.results
  const top = results ? topArtist(results.artists, library!.text) : null
  const artists = (results?.artists ?? []).filter((artist) => artist !== top)
  const found = musicbrainz.state === 'done' ? musicbrainz.shown : []
  //? whether "More from MusicBrainz" has another page to ask for (lib/searchResults.ts morePages)
  const pages = musicbrainz.state === 'done' ? morePages(musicbrainz.nextOffset, musicbrainz.count, musicbrainz.last, MUSICBRAINZ_LIMIT) : 'end'
  const more = musicbrainz.state === 'done' ? musicbrainz.more : null
  const moreWords = more?.state === 'added' ? morePageWords(more.added, more.held, personal) : null
  //? the songs half (2.0.0-player.53): the songs showing, whether More has any to show or ask for, and its words
  const songsShown = songs.state === 'done' ? songs.songs.slice(0, songs.visible) : []
  const songPages = songs.state === 'done' ? morePages(songs.nextOffset, songs.count, songs.last, SONG_SEARCH_LIMIT) : 'end'
  const songsMore = songs.state === 'done' ? songs.more : null
  const songsMoreButton = songs.state === 'done' && (songs.visible < songs.songs.length || songPages === 'more')
  const songsWords = songsMore?.state === 'added' ? moreSongsWords(songsMore.added, songsMore.grown)
    : songsMore?.state === 'shown' ? { note: null, said: `${songsMore.added} more ${songsMore.added === 1 ? 'song' : 'songs'}` }
      //? songs folded as they landed: said, as the rows they'd have been would be seen
      : songs.state === 'done' && songs.late && songs.songs.length
        ? { note: null, said: `${songs.songs.length} ${songs.songs.length === 1 ? 'song' : 'songs'} on MusicBrainz - Show songs to see them` } : null
  //? a search that found no song at all draws no section - the albums answer for the words (review: "No songs"
  //? over an album's words) - unless it landed after the albums were drawn, when it says so in its place
  const songsDrawn = songs.state !== 'idle' && !(songs.state === 'done' && !songs.late && !songs.recordings.length)
  const songsFound = songs.state === 'done' ? `“${songs.text}”` : ''
  //? recordings found, none of them on a release MusicBrainz lists (review: it read "No songs", untrue)
  const onNoRelease = `MusicBrainz has songs for ${songsFound}, but on no release yet - nothing to get.`

  //? More's last page landed with focus on it (review): the button goes with that page, and the page's
  //? focus would fall to the page itself - so it goes to the first row the page brought, or to the note
  //? said in the button's place. Only when the button had focus (a tap on WebKit gives it none, so a
  //? finger's page is never scrolled), and never over focus that has gone somewhere since.
  useLayoutEffect(() => {
    const from = moreFocus.current
    moreFocus.current = null
    if (from === null || pages === 'more' || typeof document === 'undefined') return
    const active = document.activeElement
    if (active && active !== document.body) return
    const box = musicSection.current
    const target = box?.querySelectorAll<HTMLElement>('.app-result')[from] ?? box?.querySelector<HTMLElement>('.app-search-more-note')
    target?.focus()
  }, [musicbrainz])

  //? More songs going with the last of them while it had focus: focus to the first song it brought, or the note
  //? said in its place - as More from MusicBrainz hands it on (only when the button had it, never over focus
  //? gone elsewhere since)
  useLayoutEffect(() => {
    const from = moreSongsFocus.current
    moreSongsFocus.current = null
    if (from === null || songsMoreButton || typeof document === 'undefined') return
    const active = document.activeElement
    if (active && active !== document.body) return
    const box = songSection.current
    const target = box?.querySelectorAll<HTMLElement>('.app-song-row')[from] ?? box?.querySelector<HTMLElement>('.app-search-more-note')
    target?.focus()
  }, [songs])

  //? "Show songs" going as the songs open, while it had focus: focus to the first song (as More hands it on)
  useLayoutEffect(() => {
    const had = showSongsFocus.current
    showSongsFocus.current = false
    if (!had || typeof document === 'undefined') return
    const active = document.activeElement
    if (active && active !== document.body) return
    songSection.current?.querySelector<HTMLElement>('.app-song-row')?.focus()
  }, [songs])

  /** A song's row and, open, the albums it is on: Albums, EPs and Singles listed, the rest under one fold
   *  that opens - listed at once when there is nothing else to list. */
  const songRow = (song: FoundSong, index: number) => {
    const index_ = owned?.index ?? null
    const open = openSongs.has(song.key)
    const { listed, folded } = songAlbumBands(song)
    const foldOpen = !listed.length || openFolds.has(song.key)
    const id = `app-song-albums-${index}`
    const albumRow = (album: SongAlbum) => {
      const key = `${song.key}\n${album.id}`
      return (
        <li key={album.id}>
          <button type="button" class={`app-result app-song-album${opening === key ? ' is-busy' : ''}`} aria-busy={opening === key} onClick={() => openSongAlbum(song, album)}>
            <ArchiveCover addresses={coverAddresses(null, album.id, 250)} class="app-result-cover" />
            <span class="app-result-text">
              <span class="app-result-title">{album.title}</span>
              <span class="app-result-line">{songAlbumLine(album, song, index_, personal, evidence)}</span>
            </span>
          </button>
        </li>
      )
    }
    return (
      <li key={song.key} class="app-song">
        <button type="button" class="app-result app-song-row" aria-expanded={open} aria-controls={id} onClick={() => toggle(setOpenSongs, song.key)}>
          <ArchiveCover addresses={coverAddresses(null, namedAlbum(song, index_, evidence).album.id, 250)} class="app-result-cover" />
          <span class="app-result-text">
            <span class="app-result-title">{song.title}</span>
            <span class="app-result-line">{songLine(song, index_, personal, evidence)}</span>
          </span>
          <ChevronDownIcon class="app-song-chevron" />
        </button>
        <div id={id} class="app-song-albums" hidden={!open}>
          {open && (
            <>
              {listed.length > 0 && <ul class="app-song-list">{listed.map(albumRow)}</ul>}
              {folded.length > 0 && (listed.length > 0 ? (
                <button type="button" class="app-text-button app-song-fold" aria-expanded={foldOpen} aria-controls={`${id}-fold`} onClick={() => toggle(setOpenFolds, song.key)}>
                  {foldLabel(folded)}
                </button>
              ) : (
                //? nothing else to list: the fold's words as its caption, its albums listed at once
                <p class="app-song-caption">{foldLabel(folded)}</p>
              ))}
              {folded.length > 0 && (
                <ul id={`${id}-fold`} class="app-song-list" hidden={!foldOpen}>
                  {foldOpen && folded.map(albumRow)}
                </ul>
              )}
            </>
          )}
        </div>
      </li>
    )
  }

  return (
    <section class="app-search">
      <header class="pl-large-header">
        <h1 class="pl-large-title">Search</h1>
      </header>

      <form class="app-search-form" role="search" onSubmit={submit}>
        <label class="app-search-field">
          <SearchIcon class="app-search-icon" />
          <input
            ref={input}
            class="app-search-input"
            type="search"
            value={text}
            onInput={(event) => setText((event.currentTarget as HTMLInputElement).value)}
            maxLength={SEARCH_MAX_CHARS}
            placeholder="Artists, albums and songs"
            aria-label={words.label}
            enterKeyHint="search"
            autoComplete="off"
            autoCapitalize="none"
            spellcheck={false}
          />
        </label>
      </form>

      {!query ? (
        <p class="app-search-hint">{words.hint}</p>
      ) : (
        <>
          <NeedsNavidrome status={status} onRetry={onRetry}>
            {libraryError ? (
              //? the MusicBrainz half's problem, drawn alike: one look, and a 44px Try again
              <div class="app-search-problem">
                <p class="app-search-empty">{libraryError}</p>
                <button type="button" class="app-button" onClick={() => askLibrary(query)}>
                  Try again
                </button>
              </div>
            ) : !results ? (
              <div class="pl-spinner" aria-label={words.searching} />
            ) : (
              <>
                {top && (
                  <section class="app-section app-search-section" aria-labelledby="app-search-top">
                    <h2 id="app-search-top" class="app-section-title app-search-title">Top result</h2>
                    <button type="button" class="app-result is-artist" onClick={() => onOpenArtist(top)}>
                      <Cover id={top.coverArt} size={112} class="app-result-cover is-round" />
                      <span class="app-result-text">
                        <span class="app-result-title is-large">{top.name}</span>
                        <span class="app-result-line">{artistLine(top.albumCount, personal)}</span>
                      </span>
                    </button>
                  </section>
                )}
                <section class="app-section app-search-section" aria-labelledby="app-search-library">
                  <h2 id="app-search-library" class="app-section-title app-search-title">{words.libraryTitle}</h2>
                  {artists.length || results.albums.length || results.songs.length ? (
                    <ul class="app-results">
                      {artists.map((artist) => (
                        <li key={`artist:${artist.id}`}>
                          <button type="button" class="app-result" onClick={() => onOpenArtist(artist)}>
                            <Cover id={artist.coverArt} size={96} class="app-result-cover is-round is-small" />
                            <span class="app-result-text">
                              <span class="app-result-title">{artist.name}</span>
                              <span class="app-result-line">{artistLine(artist.albumCount, personal)}</span>
                            </span>
                          </button>
                        </li>
                      ))}
                      {results.albums.map((album) => (
                        <li key={`album:${album.id}`}>
                          <button
                            type="button"
                            class="app-result"
                            onPointerDown={() => void prefetchAlbum(album.id)}
                            onPointerCancel={() => dropPrefetch(album.id)}
                            onClick={() => onOpenAlbum(album)}
                          >
                            <Cover id={album.coverArt} size={96} class="app-result-cover" />
                            <span class="app-result-text">
                              <span class="app-result-title">{album.name}</span>
                              <span class="app-result-line">
                                {['Album', album.artist, album.year, navidromePlace(personal, navidromeYours(album, owned?.index ?? null))].filter(Boolean).join(' · ')}
                              </span>
                            </span>
                          </button>
                        </li>
                      ))}
                      {results.songs.map((song) => {
                        const plays = !!song.albumId && songIndex(ready.get(song.albumId)?.song, song.id) >= 0
                        return (
                          <li key={`song:${song.id}`}>
                            <button type="button" class="app-result" onClick={() => playSong(song)}>
                              <Cover id={song.coverArt} size={96} class="app-result-cover" />
                              <span class="app-result-text">
                                <span class="app-result-title">{song.title}</span>
                                <span class="app-result-line">{['Song', song.artist, song.album].filter(Boolean).join(' · ')}</span>
                              </span>
                              {plays ? <PlayIcon class="app-result-play" /> : null}
                              <span class="app-visually-hidden">{plays ? ', plays it from its album' : ', opens its album'}</span>
                            </button>
                          </li>
                        )
                      })}
                    </ul>
                  ) : (
                    <p class="app-search-empty">{top ? 'No albums or songs of theirs match.' : words.nothing(library!.text)}</p>
                  )}
                </section>
              </>
            )}
          </NeedsNavidrome>

          {/* Songs on MusicBrainz (2.0.0-player.53): first in the MusicBrainz half - a phone shows them
              first - and a few of them, so the albums below still show when the words are an album's */}
          {songsDrawn && (
            <section ref={songSection} class="app-section app-search-section app-search-songs" aria-labelledby="app-search-songs" aria-busy={songs.state === 'searching'}>
              <h2 id="app-search-songs" class="app-section-title app-search-title">Songs on MusicBrainz</h2>
              {songs.state === 'searching' ? (
                //? the slot: the asking line at the height of anything folded into it later (review)
                <div class="app-song-slot">
                  <div class="app-asking" role="status">
                    <span class="app-sweep" aria-hidden="true" />
                    <span class="app-asking-text">Asking MusicBrainz…</span>
                  </div>
                </div>
              ) : songs.state === 'failed' ? (
                songs.late ? (
                  <div class="app-song-slot is-row">
                    <p class="app-search-empty">{songs.unavailable ? "MusicBrainz isn't answering." : songs.message}</p>
                    <button type="button" class="app-text-button" onClick={() => askSongsAgain(query)}>
                      Try again
                    </button>
                  </div>
                ) : (
                  <div class="app-search-problem">
                    <p class="app-search-empty">
                      {songs.unavailable ? "MusicBrainz isn't answering just now - it often goes away for a few minutes." : songs.message}
                    </p>
                    <button type="button" class="app-button" onClick={() => askSongsAgain(query)}>
                      Try again
                    </button>
                  </div>
                )
              ) : songs.state === 'done' && songs.late ? (
                //? landed after the albums were drawn under it: folded into the slot, one height whatever it holds,
                //? so nothing drawn below moves - shown at a tap (review)
                <div class="app-song-slot">
                  {songs.songs.length ? (
                    <button type="button" class="app-button app-song-show" onClick={showSongs}>Show songs</button>
                  ) : songsMoreButton ? (
                    <button
                      type="button"
                      class={`app-button app-song-show${songsMore?.state === 'asking' ? ' is-busy' : ''}`}
                      aria-busy={songsMore?.state === 'asking'}
                      aria-disabled={songsMore?.state === 'asking'}
                      onClick={() => void askMoreSongs()}
                    >
                      {songsMore?.state === 'asking' ? 'Asking MusicBrainz…' : 'More songs'}
                    </button>
                  ) : (
                    <p class="app-search-empty">
                      {songs.recordings.length ? onNoRelease : `No songs on MusicBrainz for ${songsFound}.`}
                    </p>
                  )}
                </div>
              ) : songs.state === 'done' ? (
                <>
                  {songs.songs.length ? (
                    <ul class="app-results">{songsShown.map(songRow)}</ul>
                  ) : (
                    //? recordings found, none on a release MusicBrainz lists (review: said as "No songs", untrue)
                    <p class="app-search-empty">{onNoRelease}</p>
                  )}
                  {songsWords?.note && <p class="app-search-empty app-search-more-note" tabIndex={-1}>{songsWords.note}</p>}
                  {songsMore?.state === 'failed' && (
                    <p class="app-search-empty app-search-more-note">
                      {songsMore.unavailable ? "MusicBrainz isn't answering just now - it often goes away for a few minutes." : songsMore.message}
                    </p>
                  )}
                  {/* More songs and the bound's note, rows or none - as the albums' More is (review) */}
                  {songsMoreButton ? (
                    <button
                      type="button"
                      class={`app-button app-search-more${songsMore?.state === 'asking' ? ' is-busy' : ''}`}
                      aria-busy={songsMore?.state === 'asking'}
                      aria-disabled={songsMore?.state === 'asking'}
                      onClick={() => void askMoreSongs()}
                    >
                      {songsMore?.state === 'asking' ? 'Asking MusicBrainz…' : songsMore?.state === 'failed' ? 'Try again' : 'More songs'}
                    </button>
                  ) : songPages === 'far' ? (
                    <p class="app-search-empty app-search-more-note" tabIndex={-1}>That's as far into one search as deadwax goes - add a word to narrow it.</p>
                  ) : null}
                </>
              ) : null}
              {/* what More brought, said to VoiceOver - a region always there, which iOS reads */}
              <p class="app-visually-hidden" role="status" aria-live="polite">
                {songsWords?.said ?? ''}
              </p>
            </section>
          )}

          <section ref={musicSection} class="app-section app-search-section" aria-labelledby="app-search-musicbrainz" aria-busy={musicbrainz.state === 'searching'}>
            <h2 id="app-search-musicbrainz" class="app-section-title app-search-title app-search-title-tight">{words.musicbrainzTitle}</h2>
            <p class="app-search-from">From MusicBrainz</p>
            {musicbrainz.state === 'idle' ? (
              //? three characters or more ask by themselves in a moment; fewer wait for Search
              asksMusicBrainzBySettling(query) ? null : <p class="app-search-empty">Type a little more, or press Search, to ask MusicBrainz.</p>
            ) : musicbrainz.state === 'searching' ? (
              <div class="app-asking" role="status">
                <span class="app-sweep" aria-hidden="true" />
                <span class="app-asking-text">Asking MusicBrainz…</span>
              </div>
            ) : musicbrainz.state === 'failed' ? (
              <div class="app-search-problem">
                <p class="app-search-empty">
                  {musicbrainz.unavailable ? "MusicBrainz isn't answering just now - it often goes away for a few minutes." : musicbrainz.message}
                </p>
                <button type="button" class="app-button" onClick={() => void askMusicBrainz(query)}>
                  Try again
                </button>
              </div>
            ) : (
              <>
              {found.length ? (
                <ul class="app-results">
                  {found.map((group) => {
                    const held = groupHeld(owned?.index ?? null, group.id)
                    const asking = resolving === group.id
                    return (
                      <li key={group.id} class="app-result-row">
                        <button type="button" class={`app-result${opening === group.id ? ' is-busy' : ''}`} aria-busy={opening === group.id} onClick={() => (held ? openGroup(group) : onOpenGroup(group))}>
                          <ArchiveCover addresses={coverAddresses(null, group.id, 250)} class="app-result-cover" />
                          <span class="app-result-text">
                            <span class="app-result-title">{group.title ?? ''}</span>
                            <span class="app-result-line">{groupLine(group, held, groupPlace(owned?.index ?? null, group.id, personal))}</span>
                          </span>
                        </button>
                        {!held && (
                          <button
                            type="button"
                            class={`app-result-get${asking ? ' is-busy' : ''}`}
                            aria-label={`Get ${group.title ?? 'this album'}`}
                            aria-busy={asking}
                            onClick={(event) => void getAlbum(group, event)}
                          >
                            {asking ? 'Get…' : 'Get'}
                          </button>
                        )}
                      </li>
                    )
                  })}
                </ul>
              ) : (
                <p class="app-search-empty">
                  {musicbrainz.groups.length
                    ? words.allHeld
                    : `Nothing on MusicBrainz for “${musicbrainz.text}”.`}
                </p>
              )}
              {/* More from MusicBrainz (2.0.0-player.50): under the rows, so the page it brings lands
                  below them and nothing above moves */}
              {moreWords?.note && <p class="app-search-empty app-search-more-note" tabIndex={-1}>{moreWords.note}</p>}
              {more?.state === 'failed' && (
                <p class="app-search-empty app-search-more-note">
                  {more.unavailable ? "MusicBrainz isn't answering just now - it often goes away for a few minutes." : more.message}
                </p>
              )}
              {pages === 'more' ? (
                <button
                  type="button"
                  class={`app-button app-search-more${more?.state === 'asking' ? ' is-busy' : ''}`}
                  aria-busy={more?.state === 'asking'}
                  aria-disabled={more?.state === 'asking'}
                  onClick={() => void askMore()}
                >
                  {more?.state === 'asking' ? 'Asking MusicBrainz…' : more?.state === 'failed' ? 'Try again' : 'More from MusicBrainz'}
                </button>
              ) : pages === 'far' ? (
                <p class="app-search-empty app-search-more-note" tabIndex={-1}>That's as far into one search as deadwax goes - add a word to narrow it.</p>
              ) : null}
              {/* what a page brought, said to VoiceOver - a region always there, which iOS reads */}
              <p class="app-visually-hidden" role="status" aria-live="polite">
                {moreWords?.said ?? ''}
              </p>
              </>
            )}
          </section>
        </>
      )}
    </section>
  )
}
