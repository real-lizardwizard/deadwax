import { useEffect, useLayoutEffect, useMemo, useRef, useState } from 'preact/hooks'

import { ApiError, MusicBrainzUnavailable } from '../api/http'
import {
  fullySearch, fullySearchPath, getReleaseGroup, searchArtists, searchArtistsPath, searchSaved, searchSongs, searchSongsPath,
} from '../api/musicbrainz'
import { navidromeAlbumFor } from '../api/store'
import type { ArtistMatch, FullySearchResponse, Recording, ReleaseGroup, ReleaseGroupResponse, SongSearchResponse, ArtistSearchResponse } from '../api/types'
import { heldReleases } from '../lib/idBridge'
import { isAbort, latestOnly } from '../lib/latest'
import { creditName } from '../lib/release'
import {
  LIBRARY_SETTLE_MS, MUSICBRAINZ_SETTLE_MS, SEARCH_MAX_CHARS, artistNames, asksMusicBrainzBySettling, musicBrainzOnTyping, searchQuery,
  songSearchQuery, songTitleQuery, type SearchPlan,
} from '../lib/searchQuery'
import {
  ARTIST_SEARCH_LIMIT, CHIP_LIBRARY_COUNTS, KINDS, LIBRARY_LATE_MS, PREVIEW, RESULTS_WAIT_MS, SAVED_WAIT_MS, STUDIO_NOTE, SONGS_NEED_A_TITLE, TOP_RESULTS,
  TYPE_MORE, allAlbumsQuery, artistRow, albumRow, candidatesOf, drawnCounts, knownArtists, decidedTop, drawInOrFold, emptyWords, failureWords, foldWords,
  groupRow, heldUnlisted, kindArea, lateKinds, lateRows, libraryLateWords, librarySkippedWords, libraryWords, mbArtistRow, mbSongRow, musicBrainzWords, namedArtist,
  newArtists, newSongs, nextBehind, nothingMoreWords, nothingWords, phantom, pool, preferredSongs, savedAwayWords, savedFor, savedRow, savedWords,
  sectionRows, sectionsReady, songRow as librarySongRow, studioOrder, topResults, viewWords,
  type Candidate, type Frame, type Kind, type KindPool, type Marks, type Outcome, type KindArea, type Row, type SavedAnswer, type SavedFound, type View,
} from '../lib/searchList'
import { albumsToPrefetch, appendPage, groupHeld, morePageWords, morePages, notInLibrary, searchWords, songIndex } from '../lib/searchResults'
import type { QueuePick } from '../lib/upNext'
import {
  SONG_SEARCH_LIMIT, appendSongs, groupSongs, moreSongsWords, songAlbumHeldReleases, songAlbumHolding, type Song as FoundSong, type SongAlbum,
  type SongEvidence,
} from '../lib/songs'
import {
  libraryArtists, prefetchAlbum, rememberPlayed, searchLibrary, toQueueTrack,
  type Album, type AlbumWithSongs, type Artist, type LibraryResults, type NavidromeStatus, type Song,
} from '../player/api'
import { SearchIcon } from '../player/icons'
import { usePlayerActions } from './context'
import { NeedsNavidrome } from './NeedsNavidrome'
import { keep, kept, songGet, usualGet } from './pressingLists'
import { keptAnswer, keptOr } from './searchAnswers'
import { onSearchSubmitted, onSearchTyped, shareSearchText } from './searchBox'
import { head, sectionId, sectionRow, slot, topPlace, topRow, type RowContext, type SlotState } from './SearchRows'
import type { GetRequest } from './Sources'
import { useFrame } from './useFrame'
import { useGetSettings } from './useGetSettings'
import { hasLibrary } from './useMyLibrary'
import { ownedNow, refreshOwned, useOwned } from './useOwned'
import { takeOpener } from './useSheet'
import { useYourAlbumsGeneration, yourAlbums } from './useYourAlbums'

/** How many albums MusicBrainz is asked for: a screenful, with room for the ones you hold. */
export const MUSICBRAINZ_LIMIT = 12

/**
 * How long MusicBrainz's answer waits for the library's (asked beside it) before it is drawn
 * anyway: what is held is left out BEFORE the list is drawn, never taken out from under a finger.
 */
export const OWNED_WAIT_MS = 1500

const message = (error: unknown) => (error instanceof Error ? error.message : String(error))
const wait = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms))
/** A search MusicBrainz refused as malformed: a 422 with words (src/routes/search_musicbrainz.py) - the words
 *  again would be refused again, so it offers no Try again, turns no Behind on, and is never "isn't answering". */
const refusal = (error: unknown) => error instanceof ApiError && error.status === 422 && !!error.detail

/** What a MusicBrainz failure says, kept with the kind's answer. */
interface Failure {
  message: string
  unavailable: boolean
  busy: boolean
  refused: boolean
}

const failureOf = (reason: unknown): Failure => ({
  message: message(reason),
  unavailable: reason instanceof MusicBrainzUnavailable,
  busy: reason instanceof MusicBrainzUnavailable && reason.busy,
  refused: refusal(reason),
})

/** "More from MusicBrainz" (2.0.0-player.50): the next page asked for, its failure, or what the last one brought. */
type MorePage =
  | { state: 'idle' }
  | { state: 'asking' }
  | { state: 'failed'; failure: Failure }
  //? the rows the last page added, and how many of its new albums the library holds (lib/searchResults.ts)
  | { state: 'added'; added: number; held: number }

/** The albums' answer. `shown`: the groups less the held ones, worked out once as it landed (notInLibrary).
 *  `key`: the text and the query asked - what a view asks for; `query` what MusicBrainz was asked (the words typed,
 *  when a fielded read found nothing), the next page asked by it from `nextOffset`; `studio` the studio clause on. */
type Musicbrainz =
  | { state: 'idle' }
  | { state: 'searching'; text: string; key: string }
  | {
    state: 'done'; text: string; key: string; plan: SearchPlan; groups: ReleaseGroup[]; shown: ReleaseGroup[]
    query: string; studio: boolean; nextOffset: number; count: number | null; last: number; more: MorePage
  }
  | ({ state: 'failed'; text: string; key: string } & Failure)

/** MusicBrainz's artists for the box (2.0.0-player.55). */
type Artists =
  | { state: 'idle' }
  | { state: 'searching'; text: string; key: string }
  | { state: 'done'; text: string; key: string; name: string; matches: ArtistMatch[]; nextOffset: number; count: number | null; last: number; more: MorePage }
  | ({ state: 'failed'; text: string; key: string } & Failure)

/** More songs (2.0.0-player.53): the next page asked, its failure, what it brought. */
type MoreSongs =
  | { state: 'idle' }
  | { state: 'asking' }
  | { state: 'failed'; failure: Failure }
  | { state: 'added'; added: number; grown: number }

/** MusicBrainz's songs (2.0.0-player.53): `recordings` are every page's so far (lib/songs.ts merges them into `songs`);
 *  `query` what MusicBrainz was asked (the words typed as one title, when a fielded read fell back). */
type Songs =
  | { state: 'idle' }
  | { state: 'searching'; text: string; key: string }
  | {
    state: 'done'; text: string; key: string; query: string; recordings: Recording[]; songs: FoundSong[]
    nextOffset: number; count: number | null; last: number; more: MoreSongs
  }
  | ({ state: 'failed'; text: string; key: string } & Failure)

/** What's saved for a text (2.0.0-player.56): asked as the words settle, beside the library; `none` when there was
 *  nothing to search, it failed, or it missed SAVED_WAIT_MS - given up for the words: MusicBrainz's answer alone. */
type Saved =
  | { state: 'idle' }
  | { state: 'asking'; text: string }
  | ({ state: 'done'; text: string } & SavedFound)
  | { state: 'none'; text: string }

/** All's search3 for a text: `waiting` for Navidrome's status (not known yet - not "not OK"), `skipped` with it not OK
 *  (the library counts as empty). */
type Library =
  | { text: string; state: 'waiting' | 'asking' | 'skipped' }
  | { text: string; state: 'answered'; results: LibraryResults }
  | { text: string; state: 'failed'; message: string }

/** A kind chip's own search3 (CHIP_LIBRARY_COUNTS), kept for its text; More from your library by offset. `waiting`
 *  for Navidrome's status (not known yet - not "not OK", review), `skipped` with it not OK (counts as empty). */
interface KindLibrary {
  text: string
  kind: Kind
  state: 'waiting' | 'asking' | 'answered' | 'failed' | 'skipped'
  rows: (Artist | Album | Song)[]
  full: boolean
  more: 'idle' | 'asking' | 'failed'
  message: string
}

/**
 * One run of a text's moments (§9 of the slice): a new text, Enter on words MusicBrainz hadn't been asked for, any Try
 * again, the library's Show them, Back to All. `phantoms`: this text's own moments - Top results may decide early; a
 * redraw (Back to All, Show them) puts everything down at once instead. `askedAt` set once MusicBrainz is asked for
 * it - the cap counts from then; `behind` whether Behind held as it began.
 */
interface Run {
  id: number
  text: string
  phantoms: boolean
  asked: boolean
  capPassed: boolean
  behind: boolean
  outcome: Outcome | null
}

/** A drawn section: its rows, kept in their order, and its slot when its kind was late. `saved`: rows from what's
 *  saved are among them (2.0.0-player.56) - its failure then says so. */
interface DrawnSection {
  kind: Kind
  rows: Row[]
  slot: null | { state: 'asking' } | { state: 'show'; rows: Row[] } | { state: 'said'; words: string } | { state: 'failed' }
  saved?: boolean
}

/** What the All view has drawn for a text - frozen: Top results' picks and each section's rows and their order, the
 *  frame (and so n and the preview) it was drawn in. Afterwards only marks change in place. */
interface Drawn {
  text: string
  run: number
  frame: Frame
  top: Row[]
  /** a place kept at Top results' foot for the picks still to come */
  topPlace: boolean
  /** null at moment 1: the asking line stands where they'll go */
  sections: DrawnSection[] | null
  /** drawn as if the library found nothing, a place kept at the top for it */
  libraryLate: boolean
  libraryProblem: string | null
  /** MusicBrainz is asked (or to be) for it: else the foot says how to ask it */
  musicBrainz: boolean
  studio: boolean
  /** every kind asked failed by moment 2, none late, none refused: one block at the foot */
  allFailed: Failure | null
}

/** Whether a drawn row is from what's saved. */
const fromSaved = (row: Row) => 'saved' in row && row.saved === true

const SEND_ORDER: readonly Kind[] = ['albums', 'artists', 'songs']
const words1 = (text: string) => text.trim().split(/\s+/).filter(Boolean).join(' ')

/** A drawn row by its key, found by comparing - never put into a selector: a MusicBrainz song's key holds a newline,
 *  which no CSS string may, and querySelector threw on it (review). */
function rowNamed(box: Element | null | undefined, key: string): HTMLElement | null {
  if (!box) return null
  for (const each of Array.from(box.querySelectorAll<HTMLElement>('[data-row]'))) if (each.getAttribute('data-row') === key) return each
  return null
}

/**
 * The Search tab (2.0.0-player.13; one list in Apple Music's sections since 2.0.0-player.55): one box; then Top
 * results, Artists, Albums and Songs - yours first in every section, then the store's (logins on), then
 * MusicBrainz's; chips narrowing it to one kind.
 *
 * James (2026-10-15): "can we add something to the search so that it also searches songs and artists like apple
 * music?" - "Top results first (the best artist, album or song, yours or not, yours marked), then Artists, Albums,
 * Songs - each with yours first, then MusicBrainz's. Chips narrow it to one kind. Keeps 'library first' inside every
 * section." What each part is made of, and why, is lib/searchList.ts; this wires it.
 *
 *  - THE LIBRARY is Navidrome's search3, LIBRARY_SETTLE_MS after typing stops - All's (SEARCH_COUNTS) asked for every
 *    text whatever the view, since the box's reading takes its artists; a kind chip's own beside it
 *    (CHIP_LIBRARY_COUNTS). A SONG PLAYS WITHIN ITS ALBUM once that album is in hand: the albums of the library songs
 *    in Top results' decided picks, then of the first songs, are asked for as the answer lands (KEPT - a scroll must
 *    not call one off), and a song's tap plays its album from that song - playTracks straight from the tap, nothing
 *    awaited (the gesture rule; app-rules.sim.cjs). Before its album is in hand the tap opens the album.
 *  - MUSICBRAINZ is asked nothing while typing: on Enter, or MUSICBRAINZ_SETTLE_MS after typing stops with three
 *    characters or more - albums, then artists, then songs, each through its own latestOnly, what is asked by the
 *    box's reading (lib/searchQuery.ts) and the view. Every answer waits for /library/owned a moment
 *    (OWNED_WAIT_MS), so holding is worked out before its rows draw; an answer kept from earlier in the page's life
 *    (app/searchAnswers.ts) is used with no request at all.
 *  - NOTHING DRAWN MOVES UNDER A FINGER: the library answers in about 0.2 s, MusicBrainz 1-3 s later and often not
 *    at all, so the list is drawn in moments that never move each other - Top results' decided picks as the library
 *    settles (moment 1, an asking line where the sections go), then the sections in its place (moment 2: every kind
 *    asked in, or RESULTS_WAIT_MS after MusicBrainz was asked); a kind still out gets a slot one fixed height, and
 *    lands in it - drawn in when nothing tappable is below, folded ("Show 3 albums from MusicBrainz") when something
 *    is. After a search MusicBrainz missed (Behind), the next draw at the library's moment, MusicBrainz's in slots.
 *  - TAPS: an artist opens their page (a MusicBrainz artist `mb:<mbid>`, outside the Navidrome gate); an album you
 *    have its page, one MusicBrainz offers the album you don't have (or, held, the album you have through the id
 *    bridge); a song plays (yours) or opens onto the albums it is on (MusicBrainz's - in Top results, its named album
 *    with the song marked). GET on a MusicBrainz album gets its usual pressing; on a song, the album it names on a
 *    pressing that has it - each through getRequests, so only the newest tap opens the Sources sheet, and called off
 *    the moment you move on (`active`, the box changing).
 *  - WITH LOGINS ON (2.0.0-player.52), for somebody with a library of their own, the library's rows are the STORE's:
 *    each says "in your library" or "in the store" (lib/whose.ts) - and since 2.0.0-player.55 they say "in your
 *    library" with logins off too, the half titles that said it being gone.
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
  onOpenMusicBrainzArtist,
  onGet,
  onQueueMenu,
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
  /** (2.0.0-player.55) an artist only MusicBrainz knows: their page by `mb:<mbid>` - App's openCreditedArtist */
  onOpenMusicBrainzArtist: (artist: { mbid: string; name: string }) => void
  /** a row's Get: open the Sources sheet for its usual pressing, focus given back to `opener` */
  onGet: (request: Omit<GetRequest, 'key'>, opener: HTMLElement | null) => void
  /** (2.0.0-player.57) a library song's •••: App's song menu, with the song - and its album, when in hand */
  onQueueMenu?: ((event: MouseEvent, pick: QueuePick<AlbumWithSongs>) => void) | undefined
}) {
  const actions = usePlayerActions()
  //? asked the first time the tab shows - not as the app starts, when it is mounted hidden
  const owned = useOwned(shown)
  //? (2.0.0-player.52) a library of your own: the library's rows are the store's, each marked yours or not
  const personal = hasLibrary()
  const words = searchWords(personal)
  //? You > Getting albums, asked as the tab first shows, so a Get knows them by the time it is tapped
  useGetSettings(shown)
  //? (2.0.0-player.55) which frame - read when a text's list is drawn, and kept with it
  const frame: Frame = useFrame().frame === 'desktop' ? 'desktop' : 'phone'
  //? an Add or a Remove on an album page moves it: your albums asked again, rows re-marked in place
  const yoursGeneration = useYourAlbumsGeneration()
  const input = useRef<HTMLInputElement>(null)
  const root = useRef<HTMLElement>(null)
  const chips = useRef<HTMLDivElement>(null)

  const [text, setText] = useState('')
  const query = text.trim()
  const [view, setView] = useState<View>('all')
  const viewNow = useRef<View>('all')
  viewNow.current = view

  const [library, setLibrary] = useState<Library | null>(null)
  const libraryNow = useRef<Library | null>(null)
  libraryNow.current = library
  const putLibrary = (next: Library | null) => {
    libraryNow.current = next
    setLibrary(next)
  }
  //? the text LIBRARY_LATE_MS passed for, its library not settled: drawn as if it found nothing
  const [lateFor, setLateFor] = useState<string | null>(null)
  const [kindLibrary, setKindLibrary] = useState<KindLibrary | null>(null)
  const kindNow = useRef<KindLibrary | null>(null)
  kindNow.current = kindLibrary
  const [kindLateFor, setKindLateFor] = useState<string | null>(null)
  //? a kind view whose late library rows were asked to show (its Show them)
  const [kindShown, setKindShown] = useState<string | null>(null)
  //? the albums of the songs found, once in hand: what lets a song's tap play
  const [ready, setReady] = useState<ReadonlyMap<string, AlbumWithSongs>>(new Map())
  const [musicbrainz, setMusicbrainz] = useState<Musicbrainz>({ state: 'idle' })
  const [artists, setArtists] = useState<Artists>({ state: 'idle' })
  const [songs, setSongs] = useState<Songs>({ state: 'idle' })
  //? (2.0.0-player.56) what's saved for the words
  const [saved, setSaved] = useState<Saved>({ state: 'idle' })
  const savedNow = useRef(saved)
  savedNow.current = saved
  const putSaved = (next: Saved) => {
    savedNow.current = next
    setSaved(next)
  }
  //? each kind's answer as last SET - what an ask in the same tap as another reads (a render's copy can be a step behind)
  const musicNow = useRef(musicbrainz)
  musicNow.current = musicbrainz
  const artistsNow = useRef(artists)
  artistsNow.current = artists
  const songsNow = useRef(songs)
  songsNow.current = songs
  const putAlbums = (next: Musicbrainz) => {
    musicNow.current = next
    setMusicbrainz(next)
  }
  const putArtists = (next: Artists) => {
    artistsNow.current = next
    setArtists(next)
  }
  const putSongs = (next: Songs) => {
    songsNow.current = next
    setSongs(next)
  }
  //? (2.0.0-player.55) the full getArtists list, kept once it lands; your albums with a library of your own
  const [artistList, setArtistList] = useState<Artist[] | null>(null)
  const [yourAlbumList, setYourAlbumList] = useState<Album[] | null>(null)
  //? which songs are open, and which songs' folds (by song key) - closed again by a new answer
  const [openSongs, setOpenSongs] = useState<ReadonlySet<string>>(new Set())
  const [openFolds, setOpenFolds] = useState<ReadonlySet<string>>(new Set())
  const [run, setRun] = useState<Run>({ id: 0, text: '', phantoms: true, asked: false, capPassed: false, behind: false, outcome: null })
  const runNow = useRef(run)
  runNow.current = run
  const [drawn, setDrawn] = useState<Drawn | null>(null)
  //? the list's one live region: what it says, at a text's moments
  const [said, setSaid] = useState('')

  const libraryRequests = useMemo(latestOnly, [])
  const kindRequests = useMemo(latestOnly, [])
  const musicRequests = useMemo(latestOnly, [])
  //? (2.0.0-player.55) MusicBrainz's artists: their own, as each kind's is
  const artistRequests = useMemo(latestOnly, [])
  //? the songs' own (2.0.0-player.53): a new search calls the old one off, as each kind's does
  const songRequests = useMemo(latestOnly, [])
  //? (2.0.0-player.56) what's saved: its own, as each kind's is
  const savedRequests = useMemo(latestOnly, [])
  const listRequests = useMemo(latestOnly, [])
  const yoursRequests = useMemo(latestOnly, [])
  //? a Get chip's lookup of the album's pressings: only the newest tap opens the sheet
  const getRequests = useMemo(latestOnly, [])
  const [resolving, setResolving] = useState<string | null>(null)
  //? a row found held after it was drawn: the album you have, asked of the id bridge
  const heldRequests = useMemo(latestOnly, [])
  const [opening, setOpening] = useState<string | null>(null)
  //? what MusicBrainz was last asked for, so Enter and the pause after it don't ask twice
  const asked = useRef<string | null>(null)
  //? ...and how the box was read as it was asked (review): kept for those words, so an artist the library names
  //? afterwards (search3's, or /library/owned's first answer) can't re-read the box under answers already asked -
  //? every kind's key, and so what is in hand, stays the one it was asked by. Enter reads the box afresh.
  const askedPlan = useRef<{ text: string; plan: SearchPlan } | null>(null)
  const libraryAsked = useRef<string | null>(null)
  //? what the asks read when a pause ends: this render's, never the one that started the pause
  const navidromeOk = useRef(false)
  navidromeOk.current = !!status?.ok
  const statusKnown = useRef(false)
  statusKnown.current = status !== null
  //? Behind (lib/searchList.ts nextBehind): kept for the page's life
  const behind = useRef(false)
  const capTimer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const lateTimer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const kindLateTimer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const savedTimer = useRef<ReturnType<typeof setTimeout> | null>(null)
  //? a control its own tap takes away, which had focus: where focus goes once the render has drawn what it brought
  //? `control`: the control itself, while its tap's redraw is still to come - the hand waits until it has gone
  const handFocus = useRef<{ key: string | null; kind: Kind | null; note?: boolean; control?: Element } | null>(null)
  const chipFocus = useRef(false)
  //? the run Back to All began (its "Showing everything." said with that run's first words, late review)
  const showingAll = useRef<number | null>(null)
  //? what the region has said of a kind view's words: its library's rows, then MusicBrainz's - each once (review)
  const kindSaid = useRef<{ key: string; library: boolean; musicBrainz: boolean }>({ key: '', library: false, musicBrainz: false })
  //? (2.0.0-player.56, after review) what each kind view drew below its library's rows, for its words: kept in place
  //? as later answers land (lib/searchList.ts kindArea)
  const kindAreas = useRef(new Map<string, KindArea>())
  const results = library?.state === 'answered' ? library.results : null
  const artistsKnown = useRef<string[]>([])
  artistsKnown.current = [...(owned?.artists ?? []), ...(results?.artists ?? []).map((artist) => artist.name)]

  /** A new run of a text's moments - `behind`: whether Behind applies (any Try again follows its own moments). */
  const nextRun = (text: string, phantoms: boolean, applyBehind: boolean): Run => ({
    id: runNow.current.id + 1, text, phantoms, asked: false, capPassed: false, behind: applyBehind && behind.current, outcome: null,
  })
  const startRun = (text: string, phantoms: boolean, applyBehind = true) => {
    if (capTimer.current !== null) clearTimeout(capTimer.current)
    capTimer.current = null
    const fresh = nextRun(text, phantoms, applyBehind)
    runNow.current = fresh
    setRun(fresh)
  }

  /** How a run's MusicBrainz asks came to an end - for Behind (a superseded run counts for nothing). */
  function noteOutcome(id: number, outcome: Outcome) {
    if (runNow.current.id !== id || runNow.current.outcome) return
    behind.current = nextBehind(behind.current, outcome)
    const ended = { ...runNow.current, outcome }
    runNow.current = ended
    setRun(ended)
  }

  /** The box as MusicBrainz should be asked: as it was read when MusicBrainz was asked for these words (kept, so the
   *  answers asked stay in hand), else read now with the artists the library knows. */
  const readBox = (term: string) => searchQuery(term, artistNames(artistsKnown.current))
  const planFor = (term: string) => (asked.current === term && askedPlan.current?.text === term ? askedPlan.current.plan : readBox(term))

  /** What a kind is asked for these words, read this way, in this view - null for not asked. */
  function keyFor(kind: Kind, term: string, plan: SearchPlan | null, inView: View): string | null {
    if (!plan) return null
    if (kind === 'artists') return plan.kind === 'album-by-artist' ? null : `${term}\nartists:${words1(term)}`
    if (kind === 'albums') return `${term}\nalbums:${inView === 'albums' ? plan.query : allAlbumsQuery(plan).query}`
    const asking = songSearchQuery(term, plan)
    return asking ? `${term}\nsongs:${asking}` : null
  }

  /** The kinds a view asks MusicBrainz for, by the reading. */
  const wantedKinds = (term: string, plan: SearchPlan | null, inView: View): Kind[] =>
    KINDS.filter((kind) => (inView === 'all' || inView === kind) && keyFor(kind, term, plan, inView) !== null)

  const answerOf = (kind: Kind): Musicbrainz | Artists | Songs => (kind === 'albums' ? musicbrainz : kind === 'artists' ? artists : songs)
  const answerNow = (kind: Kind): Musicbrainz | Artists | Songs => (kind === 'albums' ? musicNow : kind === 'artists' ? artistsNow : songsNow).current

  /**
   * What's saved for these words (2.0.0-player.56): asked as the words settle, beside the library - only for words
   * MusicBrainz is to be asked for - and kept for them. It answers in milliseconds; the library's moment waits for it
   * at most SAVED_WAIT_MS from now, and past that it is given up for the words (called off, `none`) - so a slow or
   * broken index only means MusicBrainz's answer alone. Asked ONCE for the words, whatever it answered: given up or
   * failed, it stays so until the words change (the review's catch: asked again by a chip's tap, Enter or Try again,
   * a saved answer landing late went above MusicBrainz's rows already drawn in a kind view).
   */
  function askSaved(term: string) {
    const was = savedNow.current
    if (was.state !== 'idle' && was.text === term) return
    const request = savedRequests.begin()
    putSaved({ state: 'asking', text: term })
    if (savedTimer.current !== null) clearTimeout(savedTimer.current)
    savedTimer.current = setTimeout(() => {
      savedTimer.current = null
      const now = savedNow.current
      if (now.state === 'asking' && now.text === term) {
        savedRequests.supersede()
        putSaved({ state: 'none', text: term })
      }
    }, SAVED_WAIT_MS)
    searchSaved(term, request.signal).then(
      (answer) => {
        if (!request.current()) return
        if (!answer.available) {
          putSaved({ state: 'none', text: term })
          return
        }
        //? what is held is left out as it is DRAWN (savedFor, from the library's index then): never worked out here, as
        //? it lands, which drew an album you have twice when /library/owned hadn't answered yet (review)
        putSaved({
          state: 'done', text: term, matches: answer.artists?.matches ?? [], groups: answer.albums?.['release-groups'] ?? [],
          credited: answer.credited?.['release-groups'] ?? [], songs: groupSongs(answer.songs?.recordings ?? []),
        })
      },
      (reason: unknown) => {
        if (!request.current() || isAbort(reason)) return
        putSaved({ state: 'none', text: term })
      },
    )
  }

  /** The library's moment waits for what's saved while it is being asked for these words - never longer than
   *  SAVED_WAIT_MS, which gives it up. */
  const savedSettled = (term: string) => !(saved.state === 'asking' && saved.text === term)

  /** What's saved for these words, as a view reading them this way draws it (lib/searchList.ts savedFor). */
  function savedOf(term: string, plan: SearchPlan, inView: View): SavedAnswer | null {
    if (saved.state !== 'done' || saved.text !== term || !drawnMusicBrainz(term)) return null
    const studio = inView === 'all' && allAlbumsQuery(plan).studio
    return savedFor(plan, saved, wantedKinds(term, plan, inView), studio, ownedNow()?.index ?? null)
  }

  function askLibrary(term: string) {
    libraryAsked.current = term
    if (!navidromeOk.current) {
      //? Navidrome's status not known yet is not "not OK": the list waits for it, as for a slow library
      putLibrary({ text: term, state: statusKnown.current ? 'skipped' : 'waiting' })
      if (statusKnown.current) takeKept(term, viewNow.current)
      return
    }
    const request = libraryRequests.begin()
    putLibrary(libraryNow.current?.text === term && libraryNow.current.state === 'answered' ? libraryNow.current : { text: term, state: 'asking' })
    searchLibrary(term, request.signal).then(
      (results) => {
        if (!request.current()) return
        putLibrary({ text: term, state: 'answered', results })
        takeKept(term, viewNow.current)
        //? the library songs in Top results' decided picks first - so a song at the top plays from its first tap -
        //? then the first songs': worked out from this very answer, never from a render
        const top = preferredSongs(decidedPrefix(term, results))
        for (const id of albumsToPrefetch(results.songs, top)) {
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
        putLibrary({ text: term, state: 'failed', message: message(reason) })
        takeKept(term, viewNow.current)
      },
    )
  }

  /** The library settles by LIBRARY_LATE_MS from now, or the list is drawn as if it found nothing, a place kept at
   *  its top for it - only if it hasn't settled by then. */
  function armLibraryLate(term: string) {
    if (lateTimer.current !== null) clearTimeout(lateTimer.current)
    setLateFor((was) => (was === term ? null : was))
    lateTimer.current = setTimeout(() => {
      lateTimer.current = null
      const now = libraryNow.current
      const settled = !!now && now.text === term && (now.state === 'answered' || now.state === 'failed' || now.state === 'skipped')
      if (!settled) setLateFor(term)
    }, LIBRARY_LATE_MS)
  }

  /** Top results' decided picks for a library answer just landed - for the prefetch, as decidedTop will draw them. */
  function decidedPrefix(term: string, results: LibraryResults): Row[] {
    const plan = planFor(term)
    if (!plan) return []
    const rows = pool({
      reading: plan, library: results, artistList, index: ownedNow()?.index ?? null, marks: marksNow(), artists: null, albums: null, songs: null,
      saved: savedOf(term, plan, 'all'),
    })
    const will = asked.current === term || asksMusicBrainzBySettling(term)
    const phantoms = will ? wantedKinds(term, plan, 'all').map((kind) => phantom(kind, plan)).filter((each): each is Candidate => !!each) : []
    return decidedTop(candidatesOf(rows, term, plan), phantoms, TOP_RESULTS[frame], {
      library: results, artistList, index: ownedNow()?.index ?? null, groups: [...(savedOf(term, plan, 'all')?.groups ?? [])],
    }).prefix
  }

  /** A kind chip's own search3 (CHIP_LIBRARY_COUNTS) for these words, beside All's; the Songs view's albums asked ahead. */
  function askKindLibrary(term: string, kind: Kind) {
    const was = kindNow.current
    const same = !!was && was.text === term && was.kind === kind
    //? asked for these words and this kind, or answered: kept. Failed, skipped (Navidrome away) or waiting for its
    //? status, it is asked again - by Enter, a chip, its Try again, or Navidrome coming back (review: a view skipped
    //? while Navidrome was away never asked again once it was back)
    if (same && (was.state === 'asking' || was.state === 'answered')) return
    const putKind = (next: KindLibrary) => {
      kindNow.current = next
      setKindLibrary(next)
    }
    const lateKey = `${term}\n${kind}`
    if (!same) {
      //? a view's own words: no place kept for an older one
      setKindLateFor(null)
      setKindShown(null)
    }
    //? the view's library settles by LIBRARY_LATE_MS, or MusicBrainz's rows draw under a place kept at its top - armed
    //? once per view and words (an ask again after a status or a failure keeps the place it has)
    const armLate = () => {
      if (same && (kindLateFor === lateKey || kindLateTimer.current !== null)) return
      if (kindLateTimer.current !== null) clearTimeout(kindLateTimer.current)
      kindLateTimer.current = setTimeout(() => {
        kindLateTimer.current = null
        const now = kindNow.current
        if (now && now.text === term && now.kind === kind && (now.state === 'asking' || now.state === 'waiting')) setKindLateFor(lateKey)
      }, LIBRARY_LATE_MS)
    }
    if (!navidromeOk.current) {
      kindRequests.supersede()
      //? Navidrome's status not known yet is not "not OK": the view's library waits for it, as for a slow one
      const waiting = !statusKnown.current
      putKind({ text: term, kind, state: waiting ? 'waiting' : 'skipped', rows: [], full: false, more: 'idle', message: '' })
      if (waiting) armLate()
      return
    }
    const request = kindRequests.begin()
    putKind({ text: term, kind, state: 'asking', rows: [], full: false, more: 'idle', message: '' })
    armLate()
    const counts = CHIP_LIBRARY_COUNTS[kind]
    searchLibrary(term, request.signal, { counts }).then(
      (found) => {
        if (!request.current()) return
        const rows = kind === 'artists' ? found.artists : kind === 'albums' ? found.albums : found.songs
        const wanted = kind === 'artists' ? counts.artistCount : kind === 'albums' ? counts.albumCount : counts.songCount
        putKind({ text: term, kind, state: 'answered', rows: rows ?? [], full: (rows ?? []).length >= wanted, more: 'idle', message: '' })
        if (kind === 'songs') {
          for (const id of albumsToPrefetch(found.songs ?? [])) {
            prefetchAlbum(id, true).then(
              (album) => {
                if (request.current()) setReady((before) => new Map(before).set(id, album))
              },
              () => {},
            )
          }
        }
      },
      (reason: unknown) => {
        if (!request.current() || isAbort(reason)) return
        putKind({ text: term, kind, state: 'failed', rows: [], full: false, more: 'idle', message: message(reason) })
      },
    )
  }

  /** More from your library: that kind's next page by offset, the other counts 0, appended. */
  function askMoreLibrary() {
    const was = kindLibrary
    if (!was || was.state !== 'answered' || was.more === 'asking') return
    const { text: term, kind } = was
    const request = kindRequests.begin()
    const offsets = kind === 'artists' ? { artistOffset: was.rows.length } : kind === 'albums' ? { albumOffset: was.rows.length } : { songOffset: was.rows.length }
    const counts = CHIP_LIBRARY_COUNTS[kind]
    const focused = focusedOn('.app-search-more-library')
    setKindLibrary((now) => (now && now.text === term && now.kind === kind ? { ...now, more: 'asking' } : now))
    searchLibrary(term, request.signal, { counts, offsets }).then(
      (found) => {
        if (!request.current()) return
        const page = (kind === 'artists' ? found.artists : kind === 'albums' ? found.albums : found.songs) ?? []
        const wanted = kind === 'artists' ? counts.artistCount : kind === 'albums' ? counts.albumCount : counts.songCount
        setKindLibrary((now) => {
          if (!now || now.text !== term || now.kind !== kind) return now
          const known = new Set(now.rows.map((row) => row.id))
          const fresh = page.filter((row) => !known.has(row.id))
          if (focused && page.length < wanted) handFocus.current = { key: fresh[0] ? `${kind === 'artists' ? 'artist' : kind === 'albums' ? 'album' : 'song'}:${fresh[0].id}` : null, kind }
          return { ...now, rows: [...now.rows, ...fresh], full: page.length >= wanted && fresh.length > 0, more: 'idle' }
        })
        setSaid(`${page.length} more ${page.length === 1 ? kind.slice(0, -1) : kind} ${personal ? 'from the store' : 'from your library'}`)
      },
      (reason: unknown) => {
        if (!request.current() || isAbort(reason)) return
        setKindLibrary((now) => (now && now.text === term && now.kind === kind ? { ...now, more: 'failed', message: message(reason) } : now))
      },
    )
  }

  /** Whether the control a selector names in the list had focus as it was tapped. */
  function focusedOn(selector: string): boolean {
    if (typeof document === 'undefined') return false
    const control = root.current?.querySelector(selector) ?? null
    return !!control && document.activeElement === control
  }

  /* ----- the kept answers: what is in hand with no request (app/searchAnswers.ts) ----- */

  function keptAlbums(term: string, plan: SearchPlan, inView: View): Extract<Musicbrainz, { state: 'done' }> | null {
    const { query: first, studio } = inView === 'albums' ? { query: plan.query, studio: false } : allAlbumsQuery(plan)
    let query = first
    let found = keptAnswer<FullySearchResponse>(fullySearchPath(first, MUSICBRAINZ_LIMIT, false, 0, true))
    if (!found) return null
    if (!found['release-groups']?.length && plan.kind !== 'free') {
      query = words1(term)
      found = keptAnswer<FullySearchResponse>(fullySearchPath(query, MUSICBRAINZ_LIMIT, false, 0, true))
      if (!found) return null
    }
    return albumsDone(term, plan, inView, found, query, studio && query === first)
  }

  function albumsDone(term: string, plan: SearchPlan, inView: View, found: FullySearchResponse, query: string, studio: boolean): Extract<Musicbrainz, { state: 'done' }> {
    const raw = found['release-groups'] ?? []
    //? the studio clause's answer read as an artist's albums are: Album before EP, plain first, earliest first
    const groups = studio ? studioOrder(raw) : raw
    return {
      state: 'done', text: term, key: keyFor('albums', term, plan, inView)!, plan, groups, shown: notInLibrary(groups, ownedNow()?.index ?? null),
      query, studio, nextOffset: raw.length, count: typeof found.count === 'number' ? found.count : null, last: raw.length, more: { state: 'idle' },
    }
  }

  function keptArtists(term: string, plan: SearchPlan): Extract<Artists, { state: 'done' }> | null {
    const found = keptAnswer<ArtistSearchResponse>(searchArtistsPath(words1(term), ARTIST_SEARCH_LIMIT))
    return found ? artistsDone(term, plan, found) : null
  }

  const artistsDone = (term: string, plan: SearchPlan, found: ArtistSearchResponse): Extract<Artists, { state: 'done' }> => ({
    state: 'done', text: term, key: keyFor('artists', term, plan, 'all')!, name: words1(term), matches: found.matches ?? [],
    nextOffset: (found.matches ?? []).length, count: typeof found.count === 'number' ? found.count : null, last: (found.matches ?? []).length, more: { state: 'idle' },
  })

  function keptSongs(term: string, plan: SearchPlan): Extract<Songs, { state: 'done' }> | null {
    const first = songSearchQuery(term, plan)
    if (!first) return null
    let query = first
    let found = keptAnswer<SongSearchResponse>(searchSongsPath(first, SONG_SEARCH_LIMIT))
    if (!found) return null
    const again = plan.kind === 'album-by-artist' ? songTitleQuery(term) : null
    if (!found.recordings?.length && again) {
      query = again
      found = keptAnswer<SongSearchResponse>(searchSongsPath(again, SONG_SEARCH_LIMIT))
      if (!found) return null
    }
    return songsDone(term, plan, found, query)
  }

  const songsDone = (term: string, plan: SearchPlan, found: SongSearchResponse, query: string): Extract<Songs, { state: 'done' }> => {
    const recordings = found.recordings ?? []
    return {
      state: 'done', text: term, key: keyFor('songs', term, plan, 'all')!, query, recordings, songs: groupSongs(recordings),
      nextOffset: recordings.length, count: typeof found.count === 'number' ? found.count : null, last: recordings.length, more: { state: 'idle' },
    }
  }

  /**
   * Every kind a view would ask MusicBrainz that an earlier answer of the page's life holds (app/searchAnswers.ts):
   * taken now, with no request, so the list is drawn whole at the library's moment - holding worked out from
   * ownedNow(), refreshOwned() still asked beside it to mark rows in place. Only when MusicBrainz is to be asked.
   */
  function takeKept(term: string, inView: View) {
    if (asked.current !== term && !asksMusicBrainzBySettling(term)) return
    const plan = planFor(term)
    if (!plan) return
    let took = false
    for (const kind of wantedKinds(term, plan, inView)) {
      const key = keyFor(kind, term, plan, inView)
      const now = answerNow(kind)
      if (now.state !== 'idle' && now.key === key && now.state !== 'failed') continue
      if (kind === 'albums') {
        const done = keptAlbums(term, plan, inView)
        if (done) {
          musicRequests.supersede()
          putAlbums(done)
          took = true
        }
      } else if (kind === 'artists') {
        const done = keptArtists(term, plan)
        if (done) {
          artistRequests.supersede()
          putArtists(done)
          took = true
        }
      } else {
        const done = keptSongs(term, plan)
        if (done) {
          songRequests.supersede()
          putSongs(done)
          setOpenSongs(new Set())
          setOpenFolds(new Set())
          took = true
        }
      }
    }
    if (took) void refreshOwned()
  }

  /* ----- MusicBrainz: albums, then artists, then songs ----- */

  /**
   * MusicBrainz asked for what the view needs and nobody has asked for these words: albums first, then artists (the
   * smallest), then songs (the largest) - at most four requests a settle (a fielded read's fallbacks), three at
   * once. Each through its own latestOnly; each waits a moment for /library/owned before it draws.
   */
  function askMusicBrainz(term: string, inView: View = viewNow.current, reread = false) {
    //? the box as read when these words were asked, kept - unless Enter reads it afresh (`reread`)
    const plan = reread ? readBox(term) : planFor(term)
    if (!plan) return
    asked.current = term
    askedPlan.current = { text: term, plan }
    //? what's saved beside it, if these words haven't had it (Enter on fewer than three characters)
    askSaved(term)
    const ownedAnswered = refreshOwned()
    const wanted = wantedKinds(term, plan, inView)
    for (const kind of SEND_ORDER) {
      if (!wanted.includes(kind)) continue
      if (kind === 'albums') void askAlbums(term, plan, inView, ownedAnswered)
      else if (kind === 'artists') void askArtists(term, plan, ownedAnswered)
      else askSongs(term, plan, ownedAnswered)
    }
    if (inView === 'all') armCap(term)
  }

  /** The cap counts from now for the All view's run of these words, MusicBrainz asked for them - from the ask, or from
   *  a run begun for words already asked (a letter typed and taken back, the library's Try again), whose sections
   *  would otherwise wait for the slowest kind (review). */
  function armCap(term: string) {
    const current = runNow.current
    if (current.text !== term || current.asked) return
    const id = current.id
    const marked = { ...current, asked: true }
    runNow.current = marked
    setRun(marked)
    if (capTimer.current !== null) clearTimeout(capTimer.current)
    capTimer.current = setTimeout(() => {
      capTimer.current = null
      if (runNow.current.id !== id) return
      const passed = { ...runNow.current, capPassed: true }
      runNow.current = passed
      setRun(passed)
    }, RESULTS_WAIT_MS)
  }

  /** Whether a kind's answer for this key is in hand, or on its way - then it isn't asked again. */
  const askedFor = (now: { state: string; key?: string }, key: string) => now.state !== 'idle' && now.key === key && now.state !== 'failed'

  async function askAlbums(term: string, plan: SearchPlan, inView: View, ownedAnswered: Promise<unknown>) {
    const key = keyFor('albums', term, plan, inView)!
    if (askedFor(musicNow.current, key)) return
    const { query: first, studio } = inView === 'albums' ? { query: plan.query, studio: false } : allAlbumsQuery(plan)
    const request = musicRequests.begin()
    putAlbums({ state: 'searching', text: term, key })
    try {
      let query = first
      let found = await keptOr(fullySearchPath(first, MUSICBRAINZ_LIMIT, false, 0, true), () => fullySearch(first, MUSICBRAINZ_LIMIT, false, request.signal, 0, true))
      //? a read that finds nothing - an artist's name that happens to start a title - is asked
      //? again as the words typed, as the metadata editor falls back to free text
      if (!found.answer['release-groups']?.length && plan.kind !== 'free' && request.current()) {
        query = words1(term)
        found = await keptOr(fullySearchPath(query, MUSICBRAINZ_LIMIT, false, 0, true), () => fullySearch(query, MUSICBRAINZ_LIMIT, false, request.signal, 0, true))
      }
      const raw = found.answer['release-groups'] ?? []
      //? the studio clause's answer read as an artist's albums are: Album before EP, plain first, earliest first
      const groups = studio && query === first ? studioOrder(raw) : raw
      //? the library's answer to go with it, a moment at most: what it holds is left out before the
      //? list is drawn, and never taken away once it is (an answer kept from before draws at once)
      if (request.current() && !found.kept) await Promise.race([ownedAnswered, wait(OWNED_WAIT_MS)])
      if (!request.current()) return
      putAlbums({ state: 'done', text: term, key, plan, groups, shown: notInLibrary(groups, ownedNow()?.index ?? null),
        query, studio: studio && query === first, nextOffset: raw.length, count: typeof found.answer.count === 'number' ? found.answer.count : null,
        last: raw.length, more: { state: 'idle' } })
    } catch (reason) {
      if (!request.current() || isAbort(reason)) return
      //? `asked` is left as it is (review): a failed kind is asked again by Enter or Try again anyway (askedFor), and
      //? whether MusicBrainz is drawn for these words - and how they were read - is read from it
      putAlbums({ state: 'failed', text: term, key, ...failureOf(reason) })
    }
  }

  async function askArtists(term: string, plan: SearchPlan, ownedAnswered: Promise<unknown>) {
    const key = keyFor('artists', term, plan, 'all')!
    if (askedFor(artistsNow.current, key)) return
    const name = words1(term)
    const request = artistRequests.begin()
    putArtists({ state: 'searching', text: term, key })
    try {
      const found = await keptOr(searchArtistsPath(name, ARTIST_SEARCH_LIMIT), () => searchArtists(name, ARTIST_SEARCH_LIMIT, request.signal))
      if (request.current() && !found.kept) await Promise.race([ownedAnswered, wait(OWNED_WAIT_MS)])
      if (!request.current()) return
      putArtists(artistsDone(term, plan, found.answer))
    } catch (reason) {
      if (!request.current() || isAbort(reason)) return
      putArtists({ state: 'failed', text: term, key, ...failureOf(reason) })
    }
  }

  /**
   * Songs on MusicBrainz (2.0.0-player.53): the recordings for the box as read (songSearchQuery - an artist's name
   * alone asks nothing), one page of SONG_SEARCH_LIMIT, merged into songs (lib/songs.ts). A title beside an artist
   * that finds no song by them is asked again as the words typed, as ONE title (songTitleQuery) - never the words
   * loose, which match titles alone and brought strangers' songs named after the artist (review); free text isn't
   * asked twice. Waits for the library as the albums do, so what you hold is marked as the rows are drawn.
   */
  function askSongs(term: string, plan: SearchPlan, ownedAnswered: Promise<unknown>): void {
    const query = songSearchQuery(term, plan)
    if (!query) return
    const key = keyFor('songs', term, plan, 'all')!
    if (askedFor(songsNow.current, key)) return
    const request = songRequests.begin()
    putSongs({ state: 'searching', text: term, key })
    void (async () => {
      try {
        let asking = query
        let found = await keptOr(searchSongsPath(query, SONG_SEARCH_LIMIT), () => searchSongs(query, SONG_SEARCH_LIMIT, request.signal))
        const again = plan.kind === 'album-by-artist' ? songTitleQuery(term) : null
        if (!found.answer.recordings?.length && again && request.current()) {
          asking = again
          found = await keptOr(searchSongsPath(again, SONG_SEARCH_LIMIT), () => searchSongs(again, SONG_SEARCH_LIMIT, request.signal))
        }
        if (request.current() && !found.kept) await Promise.race([ownedAnswered, wait(OWNED_WAIT_MS)])
        if (!request.current()) return
        setOpenSongs(new Set())
        setOpenFolds(new Set())
        putSongs(songsDone(term, plan, found.answer, asking))
      } catch (reason) {
        if (!request.current() || isAbort(reason)) return
        putSongs({ state: 'failed', text: term, key, ...failureOf(reason) })
      }
    })()
  }

  /**
   * "More from MusicBrainz" (2.0.0-player.50; the Albums view's since 2.0.0-player.55): the next MUSICBRAINZ_LIMIT of
   * the same search, by offset, appended below the rows already drawn - nothing above them moves - with the albums
   * the library holds left out as the first page leaves them (appendPage). Through the albums' own latestOnly.
   */
  async function askMore() {
    const was = musicbrainz
    if (was.state !== 'done' || was.more.state === 'asking') return
    const request = musicRequests.begin()
    const asking = (now: Musicbrainz): now is Extract<Musicbrainz, { state: 'done' }> => now.state === 'done' && now.key === was.key
    const focused = focusedOn('.app-search-more-musicbrainz')
    setMusicbrainz((now) => (asking(now) ? { ...now, more: { state: 'asking' } } : now))
    try {
      const found = await fullySearch(was.query, MUSICBRAINZ_LIMIT, false, request.signal, was.nextOffset, true)
      if (!request.current()) return
      const page = found['release-groups'] ?? []
      const brought = appendPage(was.groups, was.shown, page, ownedNow()?.index ?? null)
      setMusicbrainz((now) => {
        if (!asking(now)) return now
        const appended = appendPage(now.groups, now.shown, page, ownedNow()?.index ?? null)
        const next = { ...now, groups: appended.groups, shown: appended.shown, nextOffset: now.nextOffset + page.length, last: page.length,
          count: typeof found.count === 'number' ? found.count : now.count, more: { state: 'added' as const, added: appended.added, held: appended.held } }
        //? its last page landed with focus on More (review): the first album it brought, or the note in its place
        if (focused && morePages(next.nextOffset, next.count, next.last, MUSICBRAINZ_LIMIT) !== 'more') {
          const first = appended.shown.slice(now.shown.length)[0]
          handFocus.current = { key: first ? `group:${first.id}` : null, kind: 'albums', note: true }
        }
        return next
      })
      setSaid(morePageWords(brought.added, brought.held, personal).said)
    } catch (reason) {
      if (!request.current() || isAbort(reason)) return
      setMusicbrainz((now) => (asking(now) ? { ...now, more: { state: 'failed', failure: failureOf(reason) } } : now))
    }
  }

  /** More from MusicBrainz for artists (the Artists view): the next page of the same name, by offset, appended. */
  async function askMoreArtists() {
    const was = artists
    if (was.state !== 'done' || was.more.state === 'asking') return
    const request = artistRequests.begin()
    const asking = (now: Artists): now is Extract<Artists, { state: 'done' }> => now.state === 'done' && now.key === was.key
    const focused = focusedOn('.app-search-more-musicbrainz')
    setArtists((now) => (asking(now) ? { ...now, more: { state: 'asking' } } : now))
    try {
      const found = await searchArtists(was.name, ARTIST_SEARCH_LIMIT, request.signal, was.nextOffset)
      if (!request.current()) return
      const page = found.matches ?? []
      setArtists((now) => {
        if (!asking(now)) return now
        const known = new Set(now.matches.map((match) => match.mbid))
        const fresh = page.filter((match) => !known.has(match.mbid))
        const next = { ...now, matches: [...now.matches, ...fresh], nextOffset: now.nextOffset + page.length, last: page.length,
          count: typeof found.count === 'number' ? found.count : now.count, more: { state: 'added' as const, added: fresh.length, held: 0 } }
        if (focused && morePages(next.nextOffset, next.count, next.last, ARTIST_SEARCH_LIMIT) !== 'more') {
          handFocus.current = { key: fresh[0] ? `mb-artist:${fresh[0].mbid}` : null, kind: 'artists', note: true }
        }
        return next
      })
      setSaid(`${page.length} more ${page.length === 1 ? 'artist' : 'artists'} from MusicBrainz`)
    } catch (reason) {
      if (!request.current() || isAbort(reason)) return
      setArtists((now) => (asking(now) ? { ...now, more: { state: 'failed', failure: failureOf(reason) } } : now))
    }
  }

  /**
   * More songs (2.0.0-player.53; the Songs view's since 2.0.0-player.55): the next SONG_SEARCH_LIMIT recordings of the
   * same search, by offset, merged in - a later take of a song shown adds its albums to it in place, a new song comes
   * after the rest, nothing drawn moves. Through the songs' own latestOnly.
   */
  async function askMoreSongs() {
    const was = songs
    if (was.state !== 'done' || was.more.state === 'asking') return
    const asking = (now: Songs): now is Extract<Songs, { state: 'done' }> => now.state === 'done' && now.key === was.key
    const focused = focusedOn('.app-search-more-musicbrainz')
    const request = songRequests.begin()
    setSongs((now) => (asking(now) ? { ...now, more: { state: 'asking' } } : now))
    try {
      const found = await searchSongs(was.query, SONG_SEARCH_LIMIT, request.signal, was.nextOffset)
      if (!request.current()) return
      const page = found.recordings ?? []
      setSongs((now) => {
        if (!asking(now)) return now
        //? the songs drawn keep their places, every other song after them (review)
        const merged = appendSongs(now.recordings, page, now.songs)
        const next = {
          ...now, recordings: merged.recordings, songs: merged.songs, nextOffset: now.nextOffset + page.length,
          last: page.length, count: typeof found.count === 'number' ? found.count : now.count, more: { state: 'added' as const, added: merged.added, grown: merged.grown },
        }
        if (focused && morePages(next.nextOffset, next.count, next.last, SONG_SEARCH_LIMIT) !== 'more') {
          const first = merged.songs.slice(now.songs.length)[0]
          handFocus.current = { key: first ? `mb-song:${first.key}` : null, kind: 'songs', note: true }
        }
        return next
      })
      const brought = appendSongs(was.recordings, page, was.songs)
      setSaid(moreSongsWords(brought.added, brought.grown).said)
    } catch (reason) {
      if (!request.current() || isAbort(reason)) return
      setSongs((now) => (asking(now) ? { ...now, more: { state: 'failed', failure: failureOf(reason) } } : now))
    }
  }

  /** Every MusicBrainz kind called off and emptied - the box emptied, or cut back below what asks by itself. */
  function dropMusicBrainz() {
    musicRequests.supersede()
    artistRequests.supersede()
    songRequests.supersede()
    asked.current = null
    askedPlan.current = null
    if (musicNow.current.state !== 'idle') putAlbums({ state: 'idle' })
    if (artistsNow.current.state !== 'idle') putArtists({ state: 'idle' })
    if (songsNow.current.state !== 'idle') putSongs({ state: 'idle' })
  }

  //? typing: the library after a short pause, MusicBrainz after a longer one - and nothing at all,
  //? everything called off, for an empty box. Cut back below MUSICBRAINZ_MIN_CHARS, MusicBrainz's
  //? answers for the longer text go (nothing would ever replace them), its searches called off too.
  useEffect(() => {
    //? the box changed: a Get chip's lookup for what it said before opens nothing now
    standDown()
    for (const key of [...kindAreas.current.keys()]) if (!key.endsWith(`\n${query}`)) kindAreas.current.delete(key)
    const musicBrainz = musicBrainzOnTyping(query, asked.current)
    if (lateTimer.current !== null) clearTimeout(lateTimer.current)
    lateTimer.current = null
    //? a text the library was once late for is late again only by its own clock, never by an old one (review)
    setLateFor(null)
    if (musicBrainz === 'clear') {
      libraryRequests.supersede()
      kindRequests.supersede()
      libraryAsked.current = null
      putLibrary(null)
      kindNow.current = null
      setKindLibrary(null)
      setReady(new Map())
      dropMusicBrainz()
      savedRequests.supersede()
      putSaved({ state: 'idle' })
      setDrawn(null)
      setView('all')
      setSaid('')
      startRun('', true)
      return
    }
    if (musicBrainz === 'drop') dropMusicBrainz()
    startRun(query, true)
    //? back to exactly the words MusicBrainz was asked for (a letter typed and taken back): nothing asked again, but
    //? the run's cap counts from here, so its sections never wait on the slowest kind (review)
    if (musicBrainz === 'keep') armCap(query)
    const forLibrary = setTimeout(() => {
      //? what's saved first, beside the library: the library's moment waits for it (savedSettled)
      if (asksMusicBrainzBySettling(query) || asked.current === query) askSaved(query)
      if (libraryAsked.current !== query) askLibrary(query)
      if (viewNow.current !== 'all') askKindLibrary(query, viewNow.current)
      armLibraryLate(query)
    }, LIBRARY_SETTLE_MS)
    const forMusicBrainz = musicBrainz === 'settle'
      ? setTimeout(() => {
        if (asked.current !== query) askMusicBrainz(query)
      }, MUSICBRAINZ_SETTLE_MS)
      : null
    return () => {
      clearTimeout(forLibrary)
      if (forMusicBrainz !== null) clearTimeout(forMusicBrainz)
    }
  }, [query])

  //? Navidrome's status: known OK while the box holds something - the library asks then (a status not known yet
  //? kept the list waiting); known not OK - the library counts as empty. The full artist list once, while OK.
  useEffect(() => {
    if (status?.ok && query) {
      //? a list already drawn without the library (Navidrome was away): drawn afresh for these words as the library
      //? lands - the gate's notice leaving moves everything anyway. One drawn with the library's place kept fills it.
      //? One drawn with the library's failure in it the same (late review: asked again, its answer was drawn nowhere).
      if (drawn && drawn.text === query && drawn.run === runNow.current.id && !drawn.libraryLate && (library?.state === 'skipped' || library?.state === 'failed')) {
        askLibrary(query)
        armLibraryLate(query)
        startRun(query, false)
      } else askLibrary(query)
      if (viewNow.current !== 'all') askKindLibrary(query, viewNow.current)
    } else if (status && !status.ok) {
      if (library?.state === 'waiting' && library.text === query) {
        putLibrary({ text: query, state: 'skipped' })
        takeKept(query, viewNow.current)
      }
      //? a kind view waiting for the status: known not OK, its library counts as empty (review)
      const mine = kindNow.current
      if (mine?.state === 'waiting' && mine.text === query) {
        const skipped: KindLibrary = { ...mine, state: 'skipped' }
        kindNow.current = skipped
        setKindLibrary(skipped)
      }
    }
  }, [status?.ok, status === null])

  //? (2.0.0-player.55) the library's whole list of artists - one getArtists, kept for the page's life and shared with
  //? the artist page - asked when Search first shows with Navidrome OK, and again when Navidrome comes back after a
  //? failed ask (api.ts keeps no failure). Used from the next draw.
  useEffect(() => {
    if (!shown || !status?.ok || artistList) return
    const request = listRequests.begin()
    libraryArtists().then(
      (list) => {
        if (request.current()) setArtistList(list)
      },
      () => {},
    )
  }, [shown, status?.ok])

  //? your albums, with a library of your own - asked when Search first shows, and again when an Add or a Remove
  //? moves their generation: rows re-marked in place, never moved
  useEffect(() => {
    if (!shown || !personal) return
    const request = yoursRequests.begin()
    yourAlbums().then(
      (albums) => {
        if (request.current()) setYourAlbumList(albums)
      },
      () => {},
    )
  }, [shown, personal, yoursGeneration])

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

  //? leaving the app calls everything off - and no timer sets state after it
  useEffect(() => () => {
    libraryRequests.supersede()
    kindRequests.supersede()
    musicRequests.supersede()
    artistRequests.supersede()
    songRequests.supersede()
    savedRequests.supersede()
    getRequests.supersede()
    heldRequests.supersede()
    listRequests.supersede()
    yoursRequests.supersede()
    for (const timer of [capTimer, lateTimer, kindLateTimer, savedTimer]) if (timer.current !== null) clearTimeout(timer.current)
  }, [])

  /* ----- whose: the marks ----- */

  const yourIds = useMemo(() => (yourAlbumList ? new Set(yourAlbumList.map((album) => album.id)) : null), [yourAlbumList])
  //? yourArtists' count (lib/yourLibrary.ts): each artist's albums among yours, by the albums' artist ids
  const yourCounts = useMemo(() => {
    if (!yourAlbumList) return null
    const counts = new Map<string, number>()
    for (const album of yourAlbumList) if (album.artistId) counts.set(album.artistId, (counts.get(album.artistId) ?? 0) + 1)
    return counts
  }, [yourAlbumList])

  function marksNow(): Marks {
    const albums = new Map<string, Album>()
    for (const album of results?.albums ?? []) albums.set(album.id, album)
    if (kindLibrary?.kind === 'albums') for (const album of kindLibrary.rows as Album[]) albums.set(album.id, album)
    return {
      personal,
      index: owned?.index ?? null,
      yourAlbums: personal ? yourIds : null,
      yourArtists: personal ? yourCounts : null,
      albumOf: (id) => albums.get(id) ?? ready.get(id) ?? null,
    }
  }
  const marks = marksNow()

  /** What else says a pressing you hold has a song (lib/songs.ts SongEvidence, second review): the library's
   *  songs as last answered, and the pressings of any album the session already has (pressingLists). */
  const evidence: SongEvidence = { heard: results?.songs ?? null, pressings: (id) => kept(id)?.releases ?? null }

  /* ----- drawing without moving ----- */

  const inHandFor = (kind: Kind, term: string, plan: SearchPlan | null, inView: View) => {
    const key = keyFor(kind, term, plan, inView)
    const now = answerOf(kind)
    return !!key && now.state !== 'idle' && now.state !== 'searching' && now.key === key
  }

  /** Everything in hand for these words in the All view, each thing once (lib/searchList.ts pool). */
  function poolFor(term: string, plan: SearchPlan, withLibrary: boolean): Record<Kind, KindPool> {
    const done = <T extends { state: string }>(kind: Kind, now: T) => (inHandFor(kind, term, plan, 'all') && now.state === 'done' ? now : null)
    const albums = done('albums', musicbrainz) as Extract<Musicbrainz, { state: 'done' }> | null
    const found = done('artists', artists) as Extract<Artists, { state: 'done' }> | null
    const recorded = done('songs', songs) as Extract<Songs, { state: 'done' }> | null
    return pool({
      reading: plan, library: withLibrary ? results : null, artistList, index: owned?.index ?? null, marks, evidence,
      artists: found ? found.matches : null, albums: albums ? { groups: albums.groups, shown: albums.shown } : null, songs: recorded ? recorded.songs : null,
      saved: savedOf(term, plan, 'all'),
    })
  }

  const familyFor = (withLibrary: boolean) => {
    const plan = planFor(run.text)
    const kept = (plan && savedOf(run.text, plan, 'all')?.groups) ?? []
    return {
      library: withLibrary ? results : null, artistList, index: owned?.index ?? null, evidence,
      //? a song's named album is a saved group's, or MusicBrainz's answer's, when either holds it - marked as saved
      //? when it is what's saved's
      groups: [...kept, ...(musicbrainz.state === 'done' && musicbrainz.text === run.text ? musicbrainz.groups : [])],
      saved: new Set(kept.map((group) => group.id)),
    }
  }

  /** The sections for a draw: each kind with library rows, MusicBrainz's rows in hand, a slot for a kind still out,
   *  or its failure while another kind answered. Every kind asked failed (none late, none refused): the foot's block. */
  function sectionsOf(term: string, plan: SearchPlan, rows: Record<Kind, KindPool>, out: readonly Kind[], frameAt: Frame): { sections: DrawnSection[]; allFailed: Failure | null } {
    const wanted = drawnMusicBrainz(term) ? wantedKinds(term, plan, 'all') : []
    const failed = wanted.filter((kind) => !out.includes(kind) && answerOf(kind).state === 'failed' && inHandFor(kind, term, plan, 'all'))
    const failures = failed.map((kind) => answerOf(kind) as Failure)
    const allFailed = wanted.length > 0 && failed.length === wanted.length && !failures.some((each) => each.refused) ? failures[0]! : null
    const sections: DrawnSection[] = []
    for (const kind of KINDS) {
      const drawnRows = sectionRows(rows[kind], PREVIEW[frameAt][kind])
      const late = out.includes(kind)
      const failing = failed.includes(kind) && !allFailed
      if (!drawnRows.length && !late && !failing) continue
      sections.push({ kind, rows: drawnRows, slot: late ? { state: 'asking' } : failing ? { state: 'failed' } : null, ...(drawnRows.some(fromSaved) ? { saved: true } : {}) })
    }
    return { sections, allFailed }
  }

  const drawnMusicBrainz = (term: string) => asked.current === term || asksMusicBrainzBySettling(term)

  /** The library settled for these words: answered, failed, not asked (Navidrome not OK), or LIBRARY_LATE_MS past. */
  const librarySettled = (term: string) => (!!library && library.text === term && (library.state === 'answered' || library.state === 'failed' || library.state === 'skipped'))
    || lateFor === term

  /**
   * The All view's next draw, if any (lib/searchList.ts holds the rules): a new run's moment 1 once the library has
   * settled - Top results' decided prefix and an asking line, or everything at once when nothing is out, the run is a
   * redraw, or Behind holds; moment 2 when the sections are ready - Top results completed, the sections in the asking
   * line's place, a slot for each kind still out; and afterwards a late kind landing in its slot.
   */
  function advance(was: Drawn | null): { drawn: Drawn | null; said: string | null } {
    if (view !== 'all' || !query || run.text !== query) return { drawn: was, said: null }
    const term = run.text
    const plan = planFor(term)
    if (!plan) return { drawn: was, said: null }
    //? (2.0.0-player.56) ...and what's saved, while it is asked for (at most SAVED_WAIT_MS)
    const settled = librarySettled(term) && savedSettled(term)
    const musicBrainz = drawnMusicBrainz(term)
    const wanted = musicBrainz ? wantedKinds(term, plan, 'all') : []
    const out = lateKinds(wanted, (kind) => inHandFor(kind, term, plan, 'all'))
    const counts = (lib: boolean) => (lib && results ? { artists: results.artists.length, albums: results.albums.length, songs: results.songs.length } : {})

    if (!was || was.run !== run.id) {
      if (!settled) return { drawn: was, said: null }
      const libraryLate = !(library?.text === term && (library.state === 'answered' || library.state === 'failed' || library.state === 'skipped'))
      const withLibrary = !libraryLate && library?.state === 'answered'
      const rows = poolFor(term, plan, withLibrary)
      const found = withLibrary && !!results && (results.artists.length + results.albums.length + results.songs.length) > 0
      const whole = !out.length || !run.phantoms || (run.behind && found)
      const base = {
        text: term, run: run.id, frame, libraryLate, libraryProblem: library?.text === term && library.state === 'failed' ? library.message : null,
        musicBrainz, studio: false, allFailed: null,
      }
      const candidates = candidatesOf(rows, term, plan)
      const said = libraryWords(counts(withLibrary), personal)
      if (whole) {
        const top = topResults(candidates, TOP_RESULTS[frame], familyFor(withLibrary)).map((each) => each.row!).filter(Boolean)
        const { sections, allFailed } = sectionsOf(term, plan, rows, out, frame)
        const settledAll = !out.length && wanted.length > 0
        return {
          drawn: { ...base, top, topPlace: false, sections, allFailed, studio: studioOn(term, plan, out) },
          said: [said, savedSaid(sections), settledAll ? mbWords(term, plan, rows, wanted, frame, sections) : ''].filter(Boolean).join(' '),
        }
      }
      const phantoms = out.map((kind) => phantom(kind, plan)).filter((each): each is Candidate => !!each)
      const { prefix, place } = decidedTop(candidates, phantoms, TOP_RESULTS[frame], familyFor(withLibrary))
      //? a phantom first: no prefix - and then no Top results section at all, no heading and no place, until moment 2
      return { drawn: { ...base, top: prefix, topPlace: place && prefix.length > 0, sections: null }, said }
    }

    if (!was.sections) {
      if (!sectionsReady({ librarySettled: settled, musicBrainz, asked: run.asked || !out.length, out, capPassed: run.capPassed })) return { drawn: was, said: null }
      const withLibrary = !was.libraryLate && library?.text === term && library.state === 'answered'
      const rows = poolFor(term, plan, withLibrary)
      const top = was.topPlace || !was.top.length
        ? topResults(candidatesOf(rows, term, plan), TOP_RESULTS[was.frame], familyFor(withLibrary), was.top).map((each) => each.row!).filter(Boolean)
        : was.top
      const { sections, allFailed } = sectionsOf(term, plan, rows, out, was.frame)
      const settledAll = !out.length && wanted.length > 0
      const told = [savedSaid(sections), settledAll ? mbWords(term, plan, rows, wanted, was.frame, sections) : ''].filter(Boolean).join(' ')
      return {
        drawn: { ...was, top, topPlace: false, sections, allFailed, studio: studioOn(term, plan, out) },
        said: told || null,
      }
    }

    //? moment 2 drawn: a late kind landing in its slot
    let changed = false
    let folded: string | null = null
    let sections = was.sections
    for (const section of was.sections) {
      if (section.slot?.state !== 'asking' || !inHandFor(section.kind, term, plan, 'all')) continue
      changed = true
      const kind = section.kind
      const order = sections.map((each) => each.kind)
      if (answerOf(kind).state === 'failed') {
        sections = sections.map((each) => (each.kind === kind ? { ...each, slot: { state: 'failed' } } : each))
        continue
      }
      const withLibrary = !was.libraryLate && library?.text === term && library.state === 'answered'
      const rows = poolFor(term, plan, withLibrary)
      const cap = PREVIEW[was.frame][kind]
      //? (2.0.0-player.56) what's saved may be drawn above the slot already: MusicBrainz's answer adds only what
      //? isn't, each part's cap less what it has drawn
      const [libraryDrawn, musicBrainzDrawn] = drawnCounts(rows[kind], section.rows)
      const landing = lateRows(rows[kind], [Math.max(0, cap[0] - libraryDrawn), Math.max(0, cap[1] - musicBrainzDrawn)], new Set(section.rows.map((row) => row.key)))
      const where = drawInOrFold(kind, order)
      if (landing.length) {
        sections = sections.map((each) => (each.kind !== kind ? each : where === 'in' ? { ...each, rows: [...each.rows, ...landing], slot: null } : { ...each, slot: { state: 'show', rows: landing } }))
        if (where === 'fold') folded = foldWords(kind, landing.length).said
      } else if (where === 'in') {
        sections = section.rows.length ? sections.map((each) => (each.kind === kind ? { ...each, slot: null } : each)) : sections.filter((each) => each.kind !== kind)
      } else {
        //? nothing new, under rows MusicBrainz's answer already holds (what's saved): never "No albums on MusicBrainz"
        const words = section.rows.some(fromSaved) ? nothingMoreWords(kind, term) : emptyKindWords(kind, term)
        sections = sections.map((each) => (each.kind === kind ? { ...each, slot: { state: 'said', words } } : each))
      }
    }
    if (!changed) return { drawn: was, said: null }
    const settledAll = !out.length && wanted.length > 0
    const withLibrary = !was.libraryLate && library?.text === term && library.state === 'answered'
    const words = [folded, settledAll ? mbWords(term, plan, poolFor(term, plan, withLibrary), wanted, was.frame, sections) : null].filter(Boolean).join(' ')
    //? the studio line was decided with the sections (by the request asked): never added below them as albums land
    return { drawn: { ...was, sections }, said: words || null }
  }

  /** Whether the Albums section's studio line is drawn - decided as the sections are drawn, never later (a line added
   *  under Albums as its late answer landed would push everything below it down): its answer asked with the studio
   *  clause, or - albums still out - its request asking it. */
  const studioOn = (term: string, plan: SearchPlan, out: readonly Kind[]) => (out.includes('albums')
    ? allAlbumsQuery(plan).studio
    : musicbrainz.state === 'done' && inHandFor('albums', term, plan, 'all') && musicbrainz.studio)

  /** Why a late kind's slot holds no rows: nothing found, everything held (the albums' words), or songs on no release. */
  function emptyKindWords(kind: Kind, term: string): string {
    if (kind === 'albums' && musicbrainz.state === 'done' && musicbrainz.groups.length) return words.allHeld
    if (kind === 'songs' && songs.state === 'done' && songs.recordings.length && !songs.songs.length) return noReleaseWords(term)
    return emptyWords(kind, term)
  }

  const noReleaseWords = (term: string) => `MusicBrainz has songs for “${term}”, but on no release yet - nothing to get.`

  /** The region's words for MusicBrainz once every kind asked has settled: what it brought to the list, as drawn -
   *  more than what's saved above it, when that is drawn (`sections`). */
  function mbWords(term: string, plan: SearchPlan, rows: Record<Kind, KindPool>, wanted: readonly Kind[], frameAt: Frame, sections: readonly DrawnSection[] = []): string {
    const answered = wanted.some((kind) => answerOf(kind).state === 'done' && inHandFor(kind, term, plan, 'all'))
    //? every kind refused (a 422 with words): the refusal's words, as the slots say them - refused is not away, and is
    //? never said as "isn't answering" (late review)
    const failures = wanted.filter((kind) => inHandFor(kind, term, plan, 'all')).map(answerOf).flatMap((now) => (now.state === 'failed' ? [now] : []))
    if (!answered && failures.length && failures.every((each) => each.refused)) return failureWords(failures[0]!)
    const savedLeft = Object.fromEntries(KINDS.map((kind) => [kind, Math.max(0, PREVIEW[frameAt][kind][1] - Math.min(rows[kind].saved.length, PREVIEW[frameAt][kind][1]))]))
    const drawnOf = (kind: Kind) => Math.min(rows[kind].musicbrainz.length, savedLeft[kind]!)
    return musicBrainzWords({ artists: drawnOf('artists'), albums: drawnOf('albums'), songs: drawnOf('songs') }, answered, sections.some((each) => each.saved))
  }

  /** The region's words for what's saved, as the sections holding it are drawn: "Saved from MusicBrainz: 1 song." */
  const savedSaid = (sections: readonly DrawnSection[]) => savedWords(Object.fromEntries(sections.map((each) => [each.kind, each.rows.filter(fromSaved).length])))

  useLayoutEffect(() => {
    const next = advance(drawn)
    if (next.drawn !== drawn) setDrawn(next.drawn)
    if (next.said !== null) {
      //? Back to All just pressed - "Showing everything." said - and its whole draw made in the same commit: said
      //? together, as a kind view's are (late review: the draw's words replaced it before a screen reader could read it)
      const words = said === viewWords('all') && showingAll.current === run.id ? [said, next.said].filter(Boolean).join(' ') : next.said
      if (words !== said) setSaid(words)
    }
    //? Behind: a run whose every kind asked answered in time ends it; one whose cap passed with a kind out, or whose
    //? kind failed as MusicBrainz away, turns it on (lib/searchList.ts nextBehind)
    if (run.asked && !run.outcome && view === 'all' && run.text === query) {
      const plan = planFor(run.text)
      const wanted = plan ? wantedKinds(run.text, plan, 'all') : []
      const out = lateKinds(wanted, (kind) => inHandFor(kind, run.text, plan, 'all'))
      const away = wanted.some((kind) => { const now = answerOf(kind); return now.state === 'failed' && now.key === keyFor(kind, run.text, plan, 'all') && !now.refused })
      if (away) noteOutcome(run.id, 'failed')
      else if (run.capPassed && out.length) noteOutcome(run.id, 'late')
      else if (!out.length && wanted.length && !run.capPassed) {
        const refusedAll = wanted.every((kind) => { const now = answerOf(kind); return now.state === 'failed' && now.refused })
        noteOutcome(run.id, refusedAll ? 'refused' : 'in-time')
      }
    }
    //? a kind view's region (review: it said only "Showing albums."): its library's rows as they draw, then
    //? MusicBrainz's or its failure - each once for the view's words; More's own words then follow as ever
    if (view !== 'all' && query) {
      const model = kindModel(view)
      const key = `${model.lateKey}\n${model.keyNow ?? ''}`
      if (kindSaid.current.key !== key) kindSaid.current = { key, library: false, musicBrainz: false }
      const parts: string[] = []
      if (!kindSaid.current.library && model.showLib) {
        kindSaid.current.library = true
        //? a view that asks MusicBrainz nothing (Artists under album-by-artist) and found nothing says so (late review)
        parts.push(libraryWords({ [view]: model.libraryRows.length }, personal) || (model.noMusicBrainz && model.nothing ? nothingWords(view, query) : ''))
      }
      const mine = model.mine
      if (!kindSaid.current.musicBrainz && model.mbAllowed && !model.mbHeld && !model.noMusicBrainz && (mine?.state === 'done' || mine?.state === 'failed')) {
        kindSaid.current.musicBrainz = true
        //? (2.0.0-player.56) what's saved, said with MusicBrainz's words: drawn above them
        const kept = model.savedCount
        if (kept) parts.push(savedWords({ [view]: kept }))
        parts.push(mine.state === 'failed' ? (kept ? savedAwayWords(mine, true) : failureWords(mine, true)) : musicBrainzWords({ [view]: model.mbRows.length - model.mbRows.filter(fromSaved).length }, true, kept > 0))
      }
      const told = parts.filter(Boolean)
      //? "Showing albums." just said, and the view drawn at once: said together
      if (told.length) setSaid([said === viewWords(view) ? said : '', ...told].filter(Boolean).join(' '))
    }
  })

  //? a control its own tap took away, which had focus: focus to the first row it brought, else its section's heading -
  //? never the page's body. Only when it had focus (a finger's tap on WebKit gives none, so a finger's page is never
  //? scrolled), and never over focus that has gone somewhere since.
  //? The control can still be drawn, and focused, in the render its tap sets off - a Try again or Show them redraws
  //? from the run a render later - so the hand waits while it is (review: the hand was spent on the old draw and
  //? focus fell to the body as the control went). And it goes only to what the new draw really holds: nothing yet
  //? (moment 1 with no heading), it is kept for the draw that brings one, unless focus has gone somewhere since.
  useLayoutEffect(() => {
    const hand = handFocus.current
    if (!hand || typeof document === 'undefined') return
    const now = document.activeElement
    if (hand.control && now === hand.control && hand.control.isConnected) return
    if (now && now !== document.body) {
      handFocus.current = null
      return
    }
    const box = root.current
    const target = (hand.key ? rowNamed(box, hand.key) : null)
      //? a More's last page that brought no row: the note said in its place
      ?? (hand.note ? box?.querySelector<HTMLElement>('.app-search-more-note') : null)
      ?? (hand.kind ? box?.querySelector<HTMLElement>(`#${sectionId(hand.kind)}`) : null)
      ?? box?.querySelector<HTMLElement>('#app-search-top')
      ?? box?.querySelector<HTMLElement>('.app-search-title')
    if (!target) return
    handFocus.current = null
    target.focus()
  })

  //? See all pressed from the keyboard: focus to the chip it pressed
  useLayoutEffect(() => {
    if (!chipFocus.current) return
    chipFocus.current = false
    chips.current?.querySelector<HTMLElement>('[aria-pressed="true"]')?.focus()
  })

  /**
   * A MusicBrainz album the library holds: Navidrome's album for a release of it you hold - the album you have -
   * else, Navidrome not having found it (or not answering), the album you don't have, which says "in your library".
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

  /**
   * An album a song is on (2.0.0-player.53): the album you don't have, opened on a pressing with the song's
   * recordings, the song marked (App) - or the album you have when you hold the song on it:
   *  - a pressing the song was found on, or whose kept tracklist has it: Navidrome's album for it from the id
   *    bridge, through the held rows' latestOnly, as a held row opens it;
   *  - a pressing the library's search shows the song on: that album of Navidrome's, at once;
   *  - only a pressing nothing vouches for - the album's pressings asked first, the row busy (they are the album
   *    page's own, kept, so it then asks nothing): a held pressing with the song opens the album you have, through
   *    the bridge; none, the album you don't have, on a pressing with it.
   * Navidrome not having found it, the bridge failing or MusicBrainz failing: the album you don't have. The box
   * changing, or the tab no longer showing, calls any of it off (standDown).
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

  /**
   * Get on a MusicBrainz song (2.0.0-player.55): the album it names, on a pressing that has the song (songGet) -
   * its pressings from the session's lists, else asked, through getRequests (only the newest tap opens), the chip
   * "Get…" meanwhile. MusicBrainz unable to list them: the album page opens instead, the song marked, and its Get
   * takes over - a download is never filed without a year.
   */
  async function getSong(song: FoundSong, album: SongAlbum, event: MouseEvent) {
    const opener = takeOpener(event)
    const request = getRequests.begin()
    const key = `${song.key}\n${album.id}`
    let pressings: ReleaseGroupResponse | null = kept(album.id)
    if (!pressings) {
      setResolving(key)
      try {
        const found = await getReleaseGroup(album.id, request.signal)
        if (!found.problem) {
          keep(album.id, found)
          pressings = found
        }
      } catch (reason) {
        if (!request.current() || isAbort(reason)) return
      }
    }
    if (!request.current()) return
    setResolving(null)
    const get = songGet(album, album.recordings, pressings)
    if (get) onGet(get, opener)
    else onOpenSongAlbum({ id: album.id, title: album.title }, album.recordings)
  }

  const submit = (event: Event) => {
    event.preventDefault()
    submitNow.current()
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
    //? Enter reads the box afresh: words MusicBrainz was asked for, read another way since (the library has named
    //? the artist) are asked again by the new reading
    const kept = asked.current === query && askedPlan.current?.text === query ? askedPlan.current.plan : null
    const reading = readBox(query)
    const reread = !!kept && !!reading && (kept.kind !== reading.kind || kept.query !== reading.query)
    //? Enter on words MusicBrainz hadn't been asked for - or read anew - its list already drawn: drawn afresh, your own act
    const drawnNow = !!drawn && drawn.text === query && drawn.run === runNow.current.id
    const fresh = drawnNow && ((asked.current !== query && !drawn.musicBrainz) || reread)
    //? ...and Enter on a list drawn with a failure in it - a kind's slot, the all-failed foot, the library's problem: the
    //? failed asked again AND the list drawn afresh for them, as Try again does (late review: a drawn list is frozen, so
    //? an ask again's answer landed nowhere - the slot kept its failure, the foot stayed, the library's rows never came)
    const plan = kept ?? reading
    const libraryFailed = library?.text === query && library.state === 'failed'
    const kindFailed = !!plan && wantedKinds(query, plan, 'all').some((kind) => {
      const now = answerNow(kind)
      return now.state === 'failed' && now.key === keyFor(kind, query, plan, 'all')
    })
    const retry = !fresh && drawnNow && viewNow.current === 'all' && (libraryFailed || kindFailed)
    if (fresh) startRun(query, true)
    else if (retry) startRun(query, true, false)
    if (libraryAsked.current !== query || library?.state === 'failed') askLibrary(query)
    if (retry && libraryFailed) armLibraryLate(query)
    if (viewNow.current !== 'all') askKindLibrary(query, viewNow.current)
    askMusicBrainz(query, viewNow.current, true)
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

  /** (2.0.0-player.57) A library song's •••: the song menu with the song in hand - its album's answer too when Search
   *  holds it (for Info), else the song alone on a stand-in for its album. */
  const songMenu = (song: Song, event: MouseEvent) => {
    const album = song.albumId ? ready.get(song.albumId) : undefined
    const stub: AlbumWithSongs = { id: song.albumId ?? '', name: song.album ?? '' }
    onQueueMenu?.(event, { label: song.title, tracks: [toQueueTrack(song, album ?? stub)], albums: album ? [album] : [] })
  }

  /** A MusicBrainz album's tap: the album you have when the library holds it, else the album you don't have. */
  const openAnyGroup = (group: ReleaseGroup) => (groupHeld(owned?.index ?? null, group.id) ? openGroup(group) : onOpenGroup(group))

  const context: RowContext = {
    marks, evidence, index: owned?.index ?? null, personal, ready, resolving, opening, openSongs, openFolds,
    onPlay: playSong, onSongMenu: songMenu, onOpenAlbum, onOpenArtist, onOpenMusicBrainzArtist, onOpenGroup: openAnyGroup, onOpenSongAlbum: openSongAlbum,
    onGetGroup: (group, event) => void getAlbum(group, event), onGetSong: (song, album, event) => void getSong(song, album, event),
    onToggleSong: (key) => toggle(setOpenSongs, key), onToggleFold: (key) => toggle(setOpenFolds, key),
  }

  /* ----- the chips, See all, and the slots' own acts ----- */

  /**
   * A chip: that kind in full, or All - drawn afresh from everything in hand (your own act, so nothing moves under a
   * finger), MusicBrainz asked only for the kinds the view needs that nobody has asked for these words. Back to All:
   * everything at once, no phantom, a slot for each kind still out.
   */
  function choose(next: View) {
    if (next === view) return
    viewNow.current = next
    setView(next)
    setSaid(viewWords(next))
    if (!query) return
    if (next !== 'all') {
      //? back to a view whose library has answered for these words: drawn afresh from what is in hand - its rows, not
      //? the place its late answer was once kept behind (review)
      const mine = kindNow.current
      if (mine && mine.text === query && mine.kind === next && mine.state === 'answered') setKindShown(`${query}\n${next}`)
      if (libraryAsked.current === query || library?.text === query) askKindLibrary(query, next)
    }
    takeKept(query, next)
    //? back to All: a run of its own, drawn whole at once - begun before anything is asked, so the cap counts for it
    if (next === 'all') {
      startRun(query, false)
      showingAll.current = runNow.current.id
    }
    //? words MusicBrainz was asked for: the kinds this view needs that nobody asked, now - else the pause asks them
    if (asked.current === query) askMusicBrainz(query, next)
  }

  function seeAll(kind: Kind, event: MouseEvent) {
    chipFocus.current = typeof document !== 'undefined' && document.activeElement === event.currentTarget
    choose(kind)
    chips.current?.scrollIntoView?.({ block: 'nearest' })
  }

  /** A control its own tap takes away, tapped with focus (a keyboard, VoiceOver - a finger's tap on WebKit gives
   *  none): where focus goes once the draw it sets off has taken it away (the focus effect above). */
  function handOn(event: MouseEvent | undefined, kind: Kind | null, key: string | null = null) {
    if (event && typeof document !== 'undefined' && document.activeElement === event.currentTarget) handFocus.current = { key, kind, control: event.currentTarget as Element }
  }

  /** Any Try again: the list drawn afresh for these words - everything in hand at once, the failed kinds asked again,
   *  following the moments. */
  function tryAgain(event?: MouseEvent, kind: Kind | null = null) {
    handOn(event, kind)
    startRun(query, true, false)
    askMusicBrainz(query, 'all')
  }

  /** The library's own Try again (its failure at the top, or in its place). */
  function tryLibraryAgain(event?: MouseEvent) {
    handOn(event, null)
    startRun(query, true, false)
    //? words MusicBrainz was asked for: the cap counts from this Try again, as any run's does
    if (asked.current === query) armCap(query)
    askLibrary(query)
    armLibraryLate(query)
  }

  /** "N in your library - Show them": the list drawn afresh, whole, the library in it. */
  function showLibrary(event: MouseEvent) {
    const first = results ? [...results.artists.map((a) => `artist:${a.id}`), ...results.albums.map((a) => `album:${a.id}`), ...results.songs.map((s) => `song:${s.id}`)][0] ?? null : null
    handOn(event, null, first ? `top:${first}` : null)
    setLateFor(null)
    startRun(query, false)
  }

  /** "Show 3 albums from MusicBrainz": a folded kind's rows opened in place. */
  function showFolded(kind: Kind, event: MouseEvent) {
    if (!drawn?.sections) return
    const section = drawn.sections.find((each) => each.kind === kind)
    if (!section || section.slot?.state !== 'show') return
    const rows = section.slot.rows
    handOn(event, kind, rows[0]?.key ?? null)
    setDrawn({ ...drawn, sections: drawn.sections.map((each) => (each.kind === kind ? { ...each, rows: [...each.rows, ...rows], slot: null } : each)) })
  }

  /* ----- what is drawn ----- */

  const slotOf = (section: DrawnSection): SlotState | null => {
    const now = section.slot
    if (!now) return null
    if (now.state === 'asking') return { state: 'asking' }
    if (now.state === 'show') return { state: 'show', kind: section.kind, count: now.rows.length, onShow: (event) => showFolded(section.kind, event) }
    if (now.state === 'said') return { state: 'said', words: now.words }
    const answer = answerOf(section.kind)
    const failure = answer.state === 'failed' ? answer : { message: "MusicBrainz isn't answering.", unavailable: true, busy: false, refused: false }
    //? (2.0.0-player.56) under what's saved: MusicBrainz isn't answering, and these are what deadwax has saved
    return { state: 'failed', failure, onRetry: (event) => tryAgain(event, section.kind), ...(section.saved ? { words: savedAwayWords(failure, true) } : {}) }
  }

  function allView() {
    if (!drawn) {
      const musicBrainz = drawnMusicBrainz(query)
      return (
        <div class="app-asking app-search-asking">
          <span class="app-sweep" aria-hidden="true" />
          <span class="app-asking-text">{words.searching(musicBrainz)}</span>
        </div>
      )
    }
    const tiles = drawn.frame === 'desktop'
    const late = drawn.libraryLate && library?.text === drawn.text ? library : null
    const lateSlot: SlotState | null = !drawn.libraryLate ? null
      : !late || late.state === 'asking' || late.state === 'waiting' ? { state: 'asking', words: personal ? 'Searching the store…' : 'Searching your library…' }
        : late.state === 'failed' ? { state: 'failed', failure: { message: late.message, unavailable: false, busy: false, refused: false }, onRetry: tryLibraryAgain }
          : late.state === 'answered' ? (() => {
            const said = libraryLateWords({ artists: late.results.artists.length, albums: late.results.albums.length, songs: late.results.songs.length }, personal, drawn.text)
            return said.button ? { state: 'button' as const, words: said.button, onPress: showLibrary } : { state: 'said' as const, words: said.line }
          })()
            //? Navidrome known not OK as it came: the library wasn't searched - never "nothing in your library" (review);
            //? the place is kept, so Navidrome coming back fills it
            : { state: 'said', words: librarySkippedWords(personal) }
    const sections = drawn.sections ?? []
    const nothing = drawn.sections !== null && !drawn.top.length && !sections.length && !drawn.allFailed && drawn.musicBrainz && !drawn.libraryProblem && !drawn.libraryLate
    return (
      <div class="app-search-list" data-text={drawn.text}>
        {lateSlot && slot(lateSlot, 'library-late')}
        {drawn.libraryProblem && (
          //? the library's problem, drawn as MusicBrainz's is: one look, and a 44px Try again
          <div class="app-search-problem">
            <p class="app-search-empty">{drawn.libraryProblem}</p>
            <button type="button" class="app-button" onClick={tryLibraryAgain}>
              Try again
            </button>
          </div>
        )}
        {(drawn.top.length > 0 || drawn.topPlace) && (
          <section class="app-section app-search-section app-search-top" aria-labelledby="app-search-top">
            <h2 id="app-search-top" class="app-section-title app-search-title" tabIndex={-1}>Top results</h2>
            <ul class={`app-results${tiles ? ' app-top-tiles' : ''}`}>
              {drawn.top.map((row) => topRow(row, context, tiles))}
              {drawn.topPlace && topPlace(tiles)}
            </ul>
          </section>
        )}
        {drawn.sections === null ? (
          //? where the sections will go: one asking line, no region of its own
          <div class="app-asking app-search-asking">
            <span class="app-sweep" aria-hidden="true" />
            <span class="app-asking-text">Asking MusicBrainz…</span>
          </div>
        ) : (
          sections.map((section) => {
            const holder = slotOf(section)
            return (
              <section key={section.kind} class="app-section app-search-section" aria-labelledby={sectionId(section.kind)} aria-busy={section.slot?.state === 'asking'}>
                {head(section.kind, (event) => seeAll(section.kind, event))}
                {section.rows.length > 0 && <ul class="app-results">{section.rows.map((row, at) => sectionRow(row, context, at))}</ul>}
                {holder && slot(holder, `slot-${section.kind}`)}
                {section.kind === 'albums' && drawn.studio && <p class="app-search-filter-note">{STUDIO_NOTE}</p>}
              </section>
            )
          })
        )}
        {drawn.sections !== null && !drawn.musicBrainz && <p class="app-search-empty app-search-foot">{TYPE_MORE}</p>}
        {drawn.allFailed && (
          <div class="app-search-problem app-search-foot">
            <p class="app-search-empty">
              {sections.some((each) => each.saved) || drawn.top.some(fromSaved)
                //? (2.0.0-player.56) what's saved drawn above: one line saying MusicBrainz is away and these are saved
                ? savedAwayWords(drawn.allFailed)
                : failureWords(drawn.allFailed)}
              {/* only when something of the library's IS drawn above - what's saved isn't (review: "What's in your library is
                  above." under saved rows alone) */}
              {drawn.top.some((row) => !fromSaved(row)) || sections.some((each) => each.rows.some((row) => !fromSaved(row)))
                ? ` ${personal ? "What's in the store is above." : "What's in your library is above."}` : ''}
            </p>
            <button type="button" class="app-button" onClick={(event) => tryAgain(event)}>
              Try again
            </button>
          </div>
        )}
        {nothing && (
          <div class="app-search-foot">
            <p class="app-search-empty">{nothingWords('all', drawn.text)}</p>
            <p class="app-search-empty">Check the spelling or try a new search.</p>
          </div>
        )}
      </div>
    )
  }

  /** What a kind view holds as it stands: its library's rows (its chip's own search3), then MusicBrainz's - for the view
   *  and for what the region says of it. */
  function kindModel(kind: Kind) {
    const plan = planFor(query)
    const lib = kindLibrary && kindLibrary.text === query && kindLibrary.kind === kind ? kindLibrary : null
    const lateKey = `${query}\n${kind}`
    //? the view's library missed LIBRARY_LATE_MS: a place kept at its top until Show them
    const late = kindLateFor === lateKey && kindShown !== lateKey
    //? settled: answered, failed, or not asked (Navidrome known not OK - counts as empty); never while it asks or
    //? waits for Navidrome's status (not known yet is not "not OK", review)
    const libSettled = !!lib && (lib.state === 'answered' || lib.state === 'failed' || lib.state === 'skipped')
    const awayKnown = statusKnown.current && !navidromeOk.current
    const showLib = libSettled && !late
    const index = owned?.index ?? null
    //? the library's rows of this kind, once it has answered - under album-by-artist, Artists leads with the artist the
    //? box named; drawn when not late (or Show them pressed)
    //? (the artist named looked for among the full list AND search3's own artists, as All's pool does - an older full
    //? list may not have them yet, late review)
    const answeredRows: Row[] = []
    if (lib && libSettled) {
      if (kind === 'artists' && plan) {
        const named = namedArtist(plan, knownArtists(artistList, results?.artists ?? []))
        if (named && !lib.rows.some((row) => row.id === named.id)) answeredRows.push(artistRow(named))
      }
      for (const row of lib.rows) answeredRows.push(kind === 'artists' ? artistRow(row as Artist) : kind === 'albums' ? albumRow(row as Album) : librarySongRow(row as Song))
    } else if (!lib && awayKnown && kind === 'artists' && plan) {
      const named = namedArtist(plan, knownArtists(artistList, results?.artists ?? []))
      if (named) answeredRows.push(artistRow(named))
    }
    const libraryRows = showLib || !lib ? answeredRows : []
    const keyNow = keyFor(kind, query, plan, kind)
    const musicBrainz = drawnMusicBrainz(query)
    const answer = answerOf(kind)
    const mine = !!keyNow && answer.state !== 'idle' && answer.key === keyNow ? answer : null
    const mbAllowed = libSettled || kindLateFor === lateKey || (!lib && awayKnown)
    const libraryOf = lib?.rows ?? []
    //? MusicBrainz's rows of this kind, in its order, the library's left out
    const mbRows: Row[] = []
    if (mbAllowed && mine?.state === 'done') {
      if (kind === 'albums' && mine.state === 'done' && 'groups' in mine) {
        const held = new Set(heldUnlisted(mine.groups, index, libraryOf as Album[]).map((group) => group.id))
        const shownIds = new Set(mine.shown.map((group) => group.id))
        for (const group of mine.groups) if (shownIds.has(group.id) || held.has(group.id)) mbRows.push(groupRow(group))
      } else if (kind === 'artists' && 'matches' in mine) {
        const listed = [...(libraryOf as Artist[]), ...answeredRows.flatMap((row) => (row.type === 'artist' ? [row.artist] : []))]
        const split = newArtists(mine.matches, knownArtists(artistList, listed), index, listed)
        const brought = new Map(split.brought.map((each) => [each.position, each.artist]))
        const kept = new Map(split.musicbrainz.map((each) => [each.position, each.match]))
        mine.matches.forEach((_, at) => {
          const artist = brought.get(at)
          const match = kept.get(at)
          if (artist) mbRows.push(artistRow(artist))
          else if (match) mbRows.push(mbArtistRow(match))
        })
      } else if (kind === 'songs' && 'songs' in mine) {
        const split = newSongs(mine.songs, libraryOf as Song[], index, evidence)
        const keptSongs = new Set([...split.musicbrainz, ...split.brought].map((each) => each.song.key))
        for (const song of mine.songs) if (keptSongs.has(song.key)) mbRows.push(mbSongRow(song))
      }
    }
    //? (2.0.0-player.56) what's saved leads MusicBrainz's rows - deduped against the library's as MusicBrainz's are, and
    //? MusicBrainz's answer against it by key: drawn as soon as the view's library is, MusicBrainz's added below
    const savedRows: Row[] = []
    const kept = mbAllowed && plan ? savedOf(query, plan, kind) : null
    if (kept && kind === 'albums') {
      const held = new Set(heldUnlisted(kept.groups, index, libraryOf as Album[]).map((group) => group.id))
      const shownIds = new Set(kept.shown.map((group) => group.id))
      for (const group of kept.groups) if (shownIds.has(group.id) || held.has(group.id)) savedRows.push(savedRow(groupRow(group)))
    } else if (kept && kind === 'artists') {
      const listed = [...(libraryOf as Artist[]), ...answeredRows.flatMap((row) => (row.type === 'artist' ? [row.artist] : []))]
      const split = newArtists(kept.matches, knownArtists(artistList, listed), index, listed)
      const brought = new Map(split.brought.map((each) => [each.position, each.artist]))
      const found = new Map(split.musicbrainz.map((each) => [each.position, each.match]))
      kept.matches.forEach((_, at) => {
        const artist = brought.get(at)
        const match = found.get(at)
        if (artist) savedRows.push(artistRow(artist))
        else if (match) savedRows.push(savedRow(mbArtistRow(match)))
      })
    } else if (kept && kind === 'songs') {
      const split = newSongs(kept.songs, libraryOf as Song[], index, evidence)
      const keptSongs = new Set([...split.musicbrainz, ...split.brought].map((each) => each.song.key))
      for (const song of kept.songs) if (keptSongs.has(song.key)) savedRows.push(savedRow(mbSongRow(song)))
    }
    //? MusicBrainz's rows held while what's saved is still being asked for these words (SAVED_WAIT_MS at most, then
    //? given up): the two drawn together, saved first - as the All view's moment waits for it (review)
    //? - never once any of them is drawn (taken away again, they would move everything below)
    const areaKey = `${kind}\n${query}`
    const drewBefore = kindAreas.current.get(areaKey) ?? null
    //? - its failure as its rows (second review: a 503 back before what's saved was drawn, then pushed down by it)
    const mbHeld = !savedSettled(query) && (mine?.state === 'done' || mine?.state === 'failed') && !drewBefore?.rest.length && !drewBefore?.problem
    //? ...and what is drawn kept where it is as answers land after it (kindArea): a late saved answer goes below - below
    //? MusicBrainz's failure too, once that is drawn (second review: else its Try again moved down under the finger)
    const problem = mbAllowed && !mbHeld && mine?.state === 'failed'
    const { lead, rest, area } = kindArea(drewBefore, savedRows, mbHeld ? [] : mbRows, new Set(answeredRows.map((row) => row.key)), problem)
    if (mbAllowed) kindAreas.current.set(areaKey, area)
    savedRows.splice(0, savedRows.length, ...lead)
    mbRows.splice(0, mbRows.length, ...rest)
    //? how many of each are drawn, for the region's words (a late saved row is among MusicBrainz's)
    const savedCount = [...lead, ...rest].filter(fromSaved).length
    const noMusicBrainz = kind === 'artists' && plan?.kind === 'album-by-artist'
    //? before its library lands: one asking line where its rows will go (review: the view drew its heading alone)
    const searching = !late && !libSettled && !(!lib && awayKnown)
    //? nothing at all found: never under the library's failure - it wasn't searched (late review, as All's
    //? `!drawn.libraryProblem`); and for a view that asks MusicBrainz nothing, the library's answer alone decides it -
    //? else its heading stood alone (late review)
    const nothing = libSettled && lib?.state !== 'failed' && !answeredRows.length && !savedRows.length && !mbHeld
      && (noMusicBrainz || (mine?.state === 'done' && !mbRows.length && !(kind === 'albums' && 'groups' in mine && mine.groups.length)))
    return { plan, lib, lateKey, late, libSettled, showLib, answeredRows, libraryRows, keyNow, musicBrainz, mine, mbAllowed, mbHeld, savedRows, mbRows, savedCount, noMusicBrainz, searching, nothing }
  }

  /** A kind view: that kind in full - the library's rows (its chip's own search3), More from your library, then
   *  MusicBrainz's appended at the foot as they land (never before the view's library rows), then More. */
  function kindView(kind: Kind) {
    const { plan, lib, lateKey, late, showLib, answeredRows, libraryRows, keyNow, musicBrainz, mine, mbAllowed, mbHeld, savedRows, mbRows, noMusicBrainz, searching, nothing } = kindModel(kind)
    const pages = mine?.state === 'done' ? morePages(mine.nextOffset, mine.count, mine.last, kind === 'albums' ? MUSICBRAINZ_LIMIT : kind === 'artists' ? ARTIST_SEARCH_LIMIT : SONG_SEARCH_LIMIT) : 'end'
    const more = mine?.state === 'done' ? mine.more : null
    const moreNote = more?.state === 'added' && kind === 'albums' && 'held' in more ? morePageWords(more.added, more.held, personal).note
      : more?.state === 'added' && kind === 'songs' && 'grown' in more ? moreSongsWords(more.added, more.grown).note
        : null
    const asksMore = kind === 'albums' ? askMore : kind === 'artists' ? askMoreArtists : askMoreSongs
    const lateSlot: SlotState | null = !late ? null
      : !lib || lib.state === 'asking' || lib.state === 'waiting' ? { state: 'asking', words: personal ? 'Searching the store…' : 'Searching your library…' }
        : lib.state === 'failed' ? { state: 'failed', failure: { message: lib.message, unavailable: false, busy: false, refused: false }, onRetry: (event) => askKindLibraryAgain(kind, event) }
          //? Navidrome known not OK: the library wasn't searched - never "nothing in your library" (review)
          : lib.state === 'skipped' ? { state: 'said', words: librarySkippedWords(personal) }
            : lib.rows.length ? {
              state: 'button', words: `${lib.rows.length} ${personal ? 'in the store' : 'in your library'} - Show them`,
              onPress: (event) => {
                handOn(event, kind, answeredRows[0]?.key ?? null)
                setKindShown(lateKey)
              },
            }
              : { state: 'said', words: libraryLateWords({}, personal, query).line }
    return (
      <div class="app-search-list" data-text={query}>
        <section class="app-section app-search-section" aria-labelledby={sectionId(kind)} aria-busy={searching || (!!mine && mine.state === 'searching')}>
          {head(kind, null)}
          {lateSlot && slot(lateSlot, 'library-late')}
          {searching && (
            <div class="app-asking">
              <span class="app-sweep" aria-hidden="true" />
              <span class="app-asking-text">{words.searching(musicBrainz && !!keyNow && !noMusicBrainz)}</span>
            </div>
          )}
          {lib?.state === 'failed' && !lateSlot && (
            <div class="app-search-problem">
              <p class="app-search-empty">{lib.message}</p>
              <button type="button" class="app-button" onClick={(event) => askKindLibraryAgain(kind, event)}>
                Try again
              </button>
            </div>
          )}
          {libraryRows.length > 0 && <ul class="app-results">{libraryRows.map((row, at) => sectionRow(row, context, at))}</ul>}
          {showLib && lib?.state === 'answered' && lib.full && (
            <button
              type="button"
              class={`app-button app-search-more app-search-more-library${lib.more === 'asking' ? ' is-busy' : ''}`}
              aria-busy={lib.more === 'asking'}
              aria-disabled={lib.more === 'asking'}
              onClick={askMoreLibrary}
            >
              {lib.more === 'asking' ? (personal ? 'Asking the store…' : 'Asking your library…') : lib.more === 'failed' ? 'Try again' : personal ? 'More from the store' : 'More from your library'}
            </button>
          )}
          {!noMusicBrainz && (!musicBrainz && !mine ? (
            <p class="app-search-empty app-search-foot">{TYPE_MORE}</p>
          ) : kind === 'songs' && plan?.kind === 'artist' ? (
            <p class="app-search-empty app-search-foot">{SONGS_NEED_A_TITLE}</p>
          ) : !mbAllowed ? null : (<>
          {/* (2.0.0-player.56) what's saved, at once - MusicBrainz's answer below it */}
          {savedRows.length > 0 && <ul class="app-results">{savedRows.map((row, at) => sectionRow(row, context, libraryRows.length + at))}</ul>}
          {mine?.state === 'searching' || (!mine && musicBrainz) || mbHeld ? (<>
            <div class="app-asking">
              <span class="app-sweep" aria-hidden="true" />
              <span class="app-asking-text">Asking MusicBrainz…</span>
            </div>
            {/* what's saved that landed below a failure stays drawn while it is asked again (its Try again) */}
            {mbRows.length > 0 && <ul class="app-results">{mbRows.map((row, at) => sectionRow(row, context, libraryRows.length + savedRows.length + at))}</ul>}
          </>) : mine?.state === 'failed' ? (<>
            <div class="app-search-problem">
              <p class="app-search-empty">{savedRows.length ? savedAwayWords(mine) : failureWords(mine)}</p>
              {!mine.refused && (
                <button type="button" class="app-button" onClick={(event) => askMusicBrainzAgain(kind, event)}>
                  Try again
                </button>
              )}
            </div>
            {/* what's saved landing after the failure was drawn: below it, never pushing it down (second review) */}
            {mbRows.length > 0 && <ul class="app-results">{mbRows.map((row, at) => sectionRow(row, context, libraryRows.length + savedRows.length + at))}</ul>}
          </>) : mine?.state === 'done' ? (
            <>
              {mbRows.length > 0 ? (
                <ul class="app-results">{mbRows.map((row, at) => sectionRow(row, context, libraryRows.length + savedRows.length + at))}</ul>
              ) : nothing || savedRows.length ? null : kind === 'albums' && 'groups' in mine && mine.groups.length ? (
                <p class="app-search-empty">{words.allHeld}</p>
              ) : kind === 'songs' && 'recordings' in mine && mine.recordings.length ? (
                <p class="app-search-empty">{noReleaseWords(query)}</p>
              ) : (
                <p class="app-search-empty">{emptyWords(kind, query)}</p>
              )}
              {moreNote && <p class="app-search-empty app-search-more-note" tabIndex={-1}>{moreNote}</p>}
              {more?.state === 'failed' && <p class="app-search-empty app-search-more-note">{failureWords(more.failure)}</p>}
              {pages === 'more' ? (
                <button
                  type="button"
                  class={`app-button app-search-more app-search-more-musicbrainz${more?.state === 'asking' ? ' is-busy' : ''}`}
                  aria-busy={more?.state === 'asking'}
                  aria-disabled={more?.state === 'asking'}
                  onClick={() => void asksMore()}
                >
                  {more?.state === 'asking' ? 'Asking MusicBrainz…' : more?.state === 'failed' ? 'Try again' : kind === 'songs' ? 'More songs' : 'More from MusicBrainz'}
                </button>
              ) : pages === 'far' ? (
                <p class="app-search-empty app-search-more-note" tabIndex={-1}>{"That's as far into one search as deadwax goes - add a word to narrow it."}</p>
              ) : null}
            </>
          ) : null}
          </>))}
          {nothing && (
            <p class="app-search-empty app-search-foot">{nothingWords(kind, query)}</p>
          )}
        </section>
      </div>
    )
  }

  /** A kind view's library asked again (its Try again) - focus, if the button had it, on to the view's heading. */
  function askKindLibraryAgain(kind: Kind, event?: MouseEvent) {
    handOn(event, kind)
    askKindLibrary(query, kind)
  }

  /** A kind view's MusicBrainz asked again (its Try again) - focus, if the button had it, on to the view's heading. */
  function askMusicBrainzAgain(kind: Kind, event?: MouseEvent) {
    handOn(event, kind)
    askMusicBrainz(query, kind)
  }

  const chosen = (each: View) => (
    <button
      key={each}
      type="button"
      class={`app-chip app-library-view${view === each ? ' is-on' : ''}`}
      aria-pressed={view === each}
      onClick={() => choose(each)}
    >
      {each === 'all' ? 'All' : each === 'artists' ? 'Artists' : each === 'albums' ? 'Albums' : 'Songs'}
    </button>
  )

  return (
    <section ref={root} class="app-search">
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

      {/* the chips: the Library's view chips, verbatim - outside the form, which a desktop doesn't draw */}
      {query && (
        <div ref={chips} class="app-library-views app-search-kinds" role="group" aria-label="Show">
          {(['all', 'artists', 'albums', 'songs'] as const).map(chosen)}
        </div>
      )}

      {/* the list's one live region, there from the first render (iOS reads only regions already in the page) */}
      <p class="app-visually-hidden" role="status" aria-live="polite">{said}</p>

      {!query ? (
        <p class="app-search-hint">{words.hint}</p>
      ) : (
        <>
          {/* Navidrome away or unset: its notice once, above the results - MusicBrainz's rows draw below it */}
          {status && !status.ok && <NeedsNavidrome status={status} onRetry={onRetry}>{null}</NeedsNavidrome>}
          {view === 'all' ? allView() : kindView(view)}
        </>
      )}
    </section>
  )
}

