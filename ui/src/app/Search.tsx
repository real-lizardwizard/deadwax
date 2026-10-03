import { useEffect, useMemo, useRef, useState } from 'preact/hooks'

import { MusicBrainzUnavailable } from '../api/http'
import { fullySearch, getReleaseGroup } from '../api/musicbrainz'
import type { ReleaseGroup, ReleaseGroupResponse } from '../api/types'
import { isAbort, latestOnly } from '../lib/latest'
import { coverAddresses, pressingLabel, type PageRelease } from '../lib/pressings'
import { buildDownloadRelease, usualPressing } from '../lib/releasePayload'
import {
  LIBRARY_SETTLE_MS, MUSICBRAINZ_SETTLE_MS, SEARCH_MAX_CHARS, artistNames, asksMusicBrainzBySettling, musicBrainzOnTyping, searchQuery,
  type SearchPlan,
} from '../lib/searchQuery'
import { albumsToPrefetch, artistLine, groupHeld, groupLine, notInLibrary, songIndex, topArtist } from '../lib/searchResults'
import {
  dropPrefetch, prefetchAlbum, rememberPlayed, searchLibrary, toQueueTrack,
  type Album, type AlbumWithSongs, type LibraryResults, type NavidromeStatus, type Song,
} from '../player/api'
import { Cover } from '../player/Cover'
import { PlayIcon, SearchIcon } from '../player/icons'
import { ArchiveCover } from './ArchiveCover'
import { usePlayerActions } from './context'
import { NeedsNavidrome } from './NeedsNavidrome'
import { keep, kept } from './pressingLists'
import type { GetRequest } from './Sources'
import { useGetSettings } from './useGetSettings'
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

type Musicbrainz =
  | { state: 'idle' }
  | { state: 'searching'; text: string }
  //? `shown`: the groups less the held ones, worked out once as the list was drawn (notInLibrary)
  | { state: 'done'; text: string; plan: SearchPlan; groups: ReleaseGroup[]; shown: ReleaseGroup[] }
  | { state: 'failed'; text: string; message: string; unavailable: boolean }

/**
 * The Search tab (2.0.0-player.13): one box, the library first, then MusicBrainz.
 *
 * James: "One search box: library first, then MusicBrainz; an album you don't have opens like one
 * you do". The boards are Search.dc.html (this) and Request.dc.html (the album you don't have).
 *
 *  - THE LIBRARY HALF is Navidrome's search3 (deadwax's /navidrome/search), LIBRARY_SETTLE_MS after
 *    typing stops. An artist whose name is what was typed is the Top result - not a link: there is
 *    no artist page yet, and a row that went somewhere else would be a lie. Then albums, which open
 *    their page (asking for its songs as the finger lands, as a tile does), and songs.
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
 *    album you don't have.
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
 *
 * The albums of the songs found are asked for KEPT (prefetchAlbum's `keep`): a tile or an album
 * row pressed and scrolled shares the ask, and must not call off the one a song's tap waits for.
 *
 * Each half's answers go through its own latestOnly(): a superseded search never draws, and its
 * fetch is called off. The Navidrome gate covers the library half alone - MusicBrainz works with
 * Navidrome unset or down. A page: it reads the player's actions from context.
 */
export function Search({
  shown,
  active,
  status,
  onRetry,
  onOpenAlbum,
  onOpenGroup,
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
  /** a row's Get: open the Sources sheet for its usual pressing, focus given back to `opener` */
  onGet: (request: Omit<GetRequest, 'key'>, opener: HTMLElement | null) => void
}) {
  const actions = usePlayerActions()
  //? asked the first time the tab shows - not as the app starts, when it is mounted hidden
  const owned = useOwned(shown)
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

  const libraryRequests = useMemo(latestOnly, [])
  const musicRequests = useMemo(latestOnly, [])
  //? a Get chip's lookup of the album's pressings: only the newest tap opens the sheet
  const getRequests = useMemo(latestOnly, [])
  const [resolving, setResolving] = useState<string | null>(null)
  //? what each half was last asked, so Enter and the pause after it don't ask twice
  const asked = useRef<string | null>(null)
  const libraryAsked = useRef<string | null>(null)
  //? what the asks read when a pause ends: this render's, never the one that started the pause
  const navidromeOk = useRef(false)
  navidromeOk.current = !!status?.ok
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
    try {
      let found = await fullySearch(plan.query, MUSICBRAINZ_LIMIT, false, request.signal)
      //? a read that finds nothing - an artist's name that happens to start a title - is asked
      //? again as the words typed, as the metadata editor falls back to free text
      if (!found['release-groups']?.length && plan.kind !== 'free' && request.current()) {
        found = await fullySearch(term.split(/\s+/).join(' '), MUSICBRAINZ_LIMIT, false, request.signal)
      }
      const groups = found['release-groups'] ?? []
      //? the library's answer to go with it, a moment at most: what it holds is left out before the
      //? list is drawn, and never taken away once it is
      if (request.current()) await Promise.race([ownedAnswered, wait(OWNED_WAIT_MS)])
      if (!request.current()) return
      setMusicbrainz({ state: 'done', text: term, plan, groups, shown: notInLibrary(groups, ownedNow()?.index ?? null) })
    } catch (reason) {
      if (!request.current() || isAbort(reason)) return
      asked.current = null
      setMusicbrainz({ state: 'failed', text: term, message: message(reason), unavailable: reason instanceof MusicBrainzUnavailable })
    }
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
      return
    }
    if (musicBrainz === 'drop') {
      musicRequests.supersede()
      asked.current = null
      setMusicbrainz((was) => (was.state === 'idle' ? was : { state: 'idle' }))
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

  /** A Get chip's lookup still out is called off, and its chip says Get again. */
  function standDown() {
    getRequests.supersede()
    setResolving(null)
  }

  //? the tab's root no longer what shows - another tab, a page over it, Now Playing or the sheet:
  //? a chip's lookup still out must not open the sheet over where you went (review)
  useEffect(() => {
    if (!active) standDown()
  }, [active])

  //? leaving the app calls both halves off
  useEffect(() => () => {
    libraryRequests.supersede()
    musicRequests.supersede()
    getRequests.supersede()
  }, [])

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
    const usual = pressings ? usualPressing(pressings.releases as PageRelease[]) : null
    const pressing = usual ? pressings!.releases.find((release) => release.id === usual.id) ?? null : null
    const built = buildDownloadRelease(group, pressing)
    onGet({
      release: built.release,
      subtitle: [group.title, usual ? pressingLabel(usual) : 'the album as a whole'].filter(Boolean).join(' · '),
    }, opener)
  }

  const submit = (event: Event) => {
    event.preventDefault()
    if (!query) return
    askLibrary(query)
    void askMusicBrainz(query)
    //? the keyboard goes, so the answers have the screen
    input.current?.blur()
  }

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
  const found = musicbrainz.state === 'done' ? musicbrainz.shown : []

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
            aria-label="Search your library and MusicBrainz"
            enterKeyHint="search"
            autoComplete="off"
            autoCapitalize="none"
            spellcheck={false}
          />
        </label>
      </form>

      {!query ? (
        <p class="app-search-hint">Your library first, then MusicBrainz for the albums you don't have yet.</p>
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
              <div class="pl-spinner" aria-label="Searching your library" />
            ) : (
              <>
                {top && (
                  <section class="app-section app-search-section" aria-labelledby="app-search-top">
                    <h2 id="app-search-top" class="app-section-title app-search-title">Top result</h2>
                    <div class="app-result is-artist">
                      <Cover id={top.coverArt} size={112} class="app-result-cover is-round" />
                      <span class="app-result-text">
                        <span class="app-result-title is-large">{top.name}</span>
                        <span class="app-result-line">{artistLine(top.albumCount)}</span>
                      </span>
                    </div>
                  </section>
                )}
                <section class="app-section app-search-section" aria-labelledby="app-search-library">
                  <h2 id="app-search-library" class="app-section-title app-search-title">In your library</h2>
                  {results.albums.length || results.songs.length ? (
                    <ul class="app-results">
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
                              <span class="app-result-line">{['Album', album.artist, album.year].filter(Boolean).join(' · ')}</span>
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
                    <p class="app-search-empty">{top ? 'No albums or songs of theirs match.' : `Nothing in your library matches “${library!.text}”.`}</p>
                  )}
                </section>
              </>
            )}
          </NeedsNavidrome>

          <section class="app-section app-search-section" aria-labelledby="app-search-musicbrainz" aria-busy={musicbrainz.state === 'searching'}>
            <h2 id="app-search-musicbrainz" class="app-section-title app-search-title app-search-title-tight">Not in your library yet</h2>
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
            ) : found.length ? (
              <ul class="app-results">
                {found.map((group) => {
                  const held = groupHeld(owned?.index ?? null, group.id)
                  const asking = resolving === group.id
                  return (
                    <li key={group.id} class="app-result-row">
                      <button type="button" class="app-result" onClick={() => onOpenGroup(group)}>
                        <ArchiveCover addresses={coverAddresses(null, group.id, 250)} class="app-result-cover" />
                        <span class="app-result-text">
                          <span class="app-result-title">{group.title ?? ''}</span>
                          <span class="app-result-line">{groupLine(group, held)}</span>
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
                  ? 'Everything MusicBrainz found is in your library already.'
                  : `Nothing on MusicBrainz for “${musicbrainz.text}”.`}
              </p>
            )}
          </section>
        </>
      )}
    </section>
  )
}
