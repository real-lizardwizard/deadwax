/**
 * The player's calls, all to deadwax - which passes each one on to Navidrome with a login the
 * page never sees. See src/routes/navidrome.py for the list, and why it is a list.
 *
 * The shapes are Navidrome's own (the Subsonic API's ID3 calls), trimmed to what the player reads.
 * Every field is optional in the API and treated that way here.
 */

import { fetchOk, get, post, url } from '../api/http'
import { levelParam, levels, type Level, type LevelAnswer, type LevelledTrack } from '../lib/loudness'
import { createPlayedAlbums } from '../lib/playedAlbums'
import type { QueueTrack } from '../lib/playQueue'
import type { QueueAnswer } from '../lib/resume'
import { asksForMp4, resamples, type MaxRate } from '../lib/streamWrap'
import { discArtPath } from '../lib/turntable'

export interface NavidromeStatus {
  configured: boolean
  ok: boolean
  /** "Navidrome 0.55.2" */
  server: string | null
  problem: string | null
}

export interface Album {
  id: string
  name: string
  artist?: string
  /** the album artist's Navidrome id: what the album page's artist line opens (2.0.0-player.17) */
  artistId?: string
  coverArt?: string
  songCount?: number
  /** seconds */
  duration?: number
  year?: number
  genre?: string
  /** OpenSubsonic: the release's MusicBrainz id, as Navidrome read it from the files ('' for none) */
  musicBrainzId?: string
  /** OpenSubsonic: the labels the files name - Info's album line (2.0.0-player.17) */
  recordLabels?: { name?: string }[]
  /** OpenSubsonic: when it was last played (ISO), sent only once it has been - Home's "Not played in
   *  a while" (2.0.0-player.18, lib/home.ts) */
  played?: string
  /** when the asker starred it (ISO) - sent only if they have: with logins on deadwax asks as you
   *  (2.0.0-player.52), so it says the album is in YOUR library - your starred albums */
  starred?: string
  /** when Navidrome first had it (ISO) - "Recently added", the Library's own order (lib/shelves.ts) */
  created?: string
  /** (2.0.0-player.59) how many times the asker has played it - sent once they have: the Library's Most played */
  playCount?: number
}

export interface Song {
  id: string
  title: string
  album?: string
  albumId?: string
  artist?: string
  /** the song's own artist's Navidrome id */
  artistId?: string
  track?: number
  discNumber?: number
  /** seconds */
  duration?: number
  coverArt?: string
  contentType?: string
  suffix?: string
  bitRate?: number
  /** OpenSubsonic's, which Navidrome sends every client it doesn't list as legacy
   *  (osChildFromMediaFile, server/subsonic/helpers.go): Hz, bits and channels */
  samplingRate?: number
  bitDepth?: number
  channelCount?: number
  /** how many times it has been played - omitted by Navidrome until it has been (2.0.0-player.17) */
  playCount?: number
  /** OpenSubsonic: who wrote it, as one line ('' for nobody) */
  displayComposer?: string
  /** OpenSubsonic: everyone credited on it, by role - composers among them */
  contributors?: { role?: string; artist?: { name?: string } }[]
  /** (2.0.0-player.58) its album's year, and its album's artist as one line - Navidrome sends both on every song */
  year?: number
  displayAlbumArtist?: string
}

/** One disc's own title - MusicBrainz's medium title, which deadwax writes as `discsubtitle` and
 *  Navidrome hands back as OpenSubsonic's `discTitles` on getAlbum. Only the discs that have one. */
export interface DiscTitle {
  disc: number
  title: string
}

export interface AlbumWithSongs extends Album {
  song?: Song[]
  /** (2.0.0-player.58) a playlist's stub of the album (lib/playlists.ts playlistAlbums): `song` holds only the
   *  playlist's songs of it, so Info counts nothing from it and it never stands in for the album's own answer */
  partial?: boolean
  /** OpenSubsonic, passed through untouched by deadwax's route: "Disc 4 · <title>" on the album page */
  discTitles?: DiscTitle[]
}

/** Subsonic's own orders for an album list, as the routes accept them. */
export type AlbumOrder = 'newest' | 'alphabeticalByName' | 'alphabeticalByArtist' | 'recent'

export const PAGE_SIZE = 60

export function navidromeStatus(signal?: AbortSignal): Promise<NavidromeStatus> {
  return get('/navidrome/status', signal)
}

export async function albumPage(
  order: AlbumOrder | 'starred', offset: number, signal?: AbortSignal, size: number = PAGE_SIZE,
): Promise<Album[]> {
  const page = await get<{ albums: Album[] }>(
    `/navidrome/albums?order=${order}&size=${size}&offset=${offset}`,
    signal,
  )
  return page.albums
}

/** (2.0.0-player.59) The Library's whole list of one scope's albums - yours (your starred albums, asked as you) or
 *  the store's - in one answer (src/routes/navidrome.py /album_index), in Navidrome's order, trimmed to what the
 *  Library reads; `truncated` past the route's 10,000. Asked only through app/albumIndex.ts, which shares it. The
 *  route sends an ETag, so an unchanged list is the browser's own copy after a 304. */
export interface AlbumIndexAnswer {
  albums: Album[]
  truncated: boolean
}

export function albumIndexOf(scope: 'yours' | 'store', signal?: AbortSignal): Promise<AlbumIndexAnswer> {
  return get<AlbumIndexAnswer>(`/navidrome/album_index?scope=${scope}`, signal)
}

/** An artist as Navidrome answers - search3, getArtists, getArtist: what the Search tab's top
 *  result, Library > Artists and the artist page show. */
export interface Artist {
  id: string
  name: string
  albumCount?: number
  coverArt?: string
  /** OpenSubsonic: the album artist's MusicBrainz id, from the files' musicbrainz_albumartistid */
  musicBrainzId?: string
}

/** getArtist: the artist and the albums Navidrome has of theirs. */
export interface ArtistWithAlbums extends Artist {
  album?: Album[]
}

/** The library half of the Search tab: Navidrome's search3, as deadwax's route passes it on. */
export interface LibraryResults {
  artists: Artist[]
  albums: Album[]
  songs: Song[]
}

/** How much of each the Search tab asks for: a screenful of each, songs enough to choose from. */
export const SEARCH_COUNTS = { artistCount: 5, albumCount: 8, songCount: 12 } as const

/** How many of each a search3 asks for (SEARCH_COUNTS' shape), and where each kind's page starts. */
export interface LibraryPage {
  counts?: { artistCount: number; albumCount: number; songCount: number }
  offsets?: { artistOffset?: number; albumOffset?: number; songOffset?: number }
}

/**
 * The library's artists, albums and songs matching `query` (2.0.0-player.13) - Navidrome's search3,
 * through deadwax's route, which declares and bounds every parameter (src/routes/navidrome.py).
 * `page` (2.0.0-player.55, Search's kind chips and More from your library): other counts and each kind's offset,
 * an offset sent only past the first page - the two-argument call asks exactly what it always did.
 */
export function searchLibrary(query: string, signal?: AbortSignal, page: LibraryPage = {}): Promise<LibraryResults> {
  const params = new URLSearchParams({ q: query })
  for (const [name, count] of Object.entries(page.counts ?? SEARCH_COUNTS)) params.set(name, String(count))
  for (const [name, offset] of Object.entries(page.offsets ?? {})) if (offset && offset > 0) params.set(name, String(offset))
  return get<LibraryResults>(`/navidrome/search?${params}`, signal)
}

/**
 * Every artist in the library (2.0.0-player.17), in Navidrome's order - getArtists through deadwax's
 * route, flattened from its index by initial. Kept for the page's life once answered, since the
 * artist page reads it to find an artist opened from MusicBrainz; `fresh` asks again (Library >
 * Artists, as it is opened, and the artist page when a kept list doesn't have who it looks for -
 * an artist new to the library since: artistIndexAge says how old the kept one is).
 */
let artistIndex: Promise<Artist[]> | null = null
let artistIndexAt = 0

export function libraryArtists(fresh = false): Promise<Artist[]> {
  if (fresh || !artistIndex) {
    const asking = get<{ artists: Artist[] }>('/navidrome/artists').then((answer) => answer.artists ?? [])
    //? a failed ask isn't kept: the next one asks again
    asking.catch(() => {
      if (artistIndex === asking) artistIndex = null
    })
    artistIndex = asking
    artistIndexAt = Date.now()
  }
  return artistIndex
}

/** How long ago the kept list of artists was asked for, in ms - Infinity when none is kept. */
export function artistIndexAge(): number {
  return artistIndex ? Date.now() - artistIndexAt : Infinity
}

/** One artist and the albums Navidrome has of theirs (getArtist) - the artist page. */
export function artistAlbums(id: string, signal?: AbortSignal): Promise<ArtistWithAlbums> {
  return get<ArtistWithAlbums>(`/navidrome/artists/${encodeURIComponent(id)}`, signal)
}

/** One song as Navidrome has it now (getSong) - Info's play count and writers. */
export function songDetails(id: string, signal?: AbortSignal): Promise<Song> {
  return get<Song>(`/navidrome/songs/${encodeURIComponent(id)}`, signal)
}

/** How many songs Library > Songs asks for at a time. */
export const SONGS_PAGE = 100

/**
 * A page of every song in the library (2.0.0-player.17's Library > Songs): search3 with an EMPTY
 * query, which Navidrome answers with everything, a page at a time - no artists or albums asked.
 */
export async function librarySongs(offset: number, count: number = SONGS_PAGE, signal?: AbortSignal): Promise<Song[]> {
  const params = new URLSearchParams({ q: '', artistCount: '0', albumCount: '0', songCount: String(count), songOffset: String(offset) })
  const found = await get<LibraryResults>(`/navidrome/search?${params}`, signal)
  return found.songs ?? []
}

/** (2.0.0-player.57, Part B) A whole library's shuffle, as deadwax holds it: its order's token, how many songs it
 *  has, and its first page - every song of the scope once, in a random order deadwax made. */
export interface ShuffleStart {
  token: string
  total: number
  songs: Song[]
}

/** How many songs a page of a library's shuffle holds - SHUFFLE_PAGE in src/routes/navidrome.py. */
export const SHUFFLE_PAGE = 200

/**
 * A new order of every song of `scope` (Part B): `yours` your starred albums' songs with logins on (the store's
 * with logins off, or for the break-glass admin), `store` everything - each once, in a random order deadwax makes
 * as you (src/routes/navidrome.py /shuffle). Asked as the list shows, so its first page is in hand at the tap.
 */
export function shuffleStart(
  scope: 'yours' | 'store', signal?: AbortSignal, how: { playing?: string | null; claim?: boolean } = {},
): Promise<ShuffleStart> {
  //? `playing`: the order the list's Shuffle just played, claimed before this ask's order replaces it; `claim`: the
  //? order asked for plays at once (the feed's), so claimed as it is made - see /shuffle in src/routes/navidrome.py
  const playing = how.playing ? `&playing=${encodeURIComponent(how.playing)}` : ''
  return get<ShuffleStart>(`/navidrome/shuffle?scope=${scope}${playing}${how.claim ? '&claim=true' : ''}`, signal)
}

/** The next page of a shuffle's order, from `offset` - a 404 once deadwax no longer holds it (it restarted, or a
 *  day untouched): the feed then starts a fresh order (app/useShuffleFeed.ts). */
export function shufflePage(token: string, offset: number, signal?: AbortSignal): Promise<{ total: number; songs: Song[] }> {
  return get(`/navidrome/shuffle/${encodeURIComponent(token)}?offset=${offset}`, signal)
}

/* ===== resume what was playing (2.0.0-player.64) - app/useResume.ts, lib/resume.ts ===== */

/** What deadwax answered a save with: the record's rev and the ids_rev a position save names - both null for the
 *  break-glass admin, who keeps no queue. */
export interface SavedQueue {
  rev: number | null
  ids_rev: number | null
}

/** A full save (POST /deadwax/navidrome/queue): the window's ids, the song playing in them, the second, this device,
 *  and the snapshot of Up Next (lib/resume.ts toSave). */
export interface QueueSave {
  ids: string[]
  index: number
  position: number
  device: string
  label: string
  snapshot: string | null
}

/** A position save (POST /deadwax/navidrome/queue/at): the song and the second, against the full save `ids_rev`. */
export interface QueueAt {
  ids_rev: number
  index: number
  position: number
  device: string
  label: string
}

/** The signed-in person's play queue - Navidrome's, as them, with deadwax's record when deadwax saved it last. */
export function resumeQueue(signal?: AbortSignal): Promise<QueueAnswer<Song>> {
  return get<QueueAnswer<Song>>('/navidrome/queue', signal)
}

/** A full save; `keepalive` as the page goes away (a body of at most lib/resume.ts BEACON_MAX). */
export function saveQueue(body: QueueSave, keepalive = false): Promise<SavedQueue> {
  return post<SavedQueue>('/navidrome/queue', body, undefined, keepalive)
}

/**
 * A position save. `beacon`, as the page goes away: navigator.sendBeacon with the body as a JSON Blob - neither needs
 * a secure page, both work over plain http - falling back to a keepalive fetch where sendBeacon is missing or
 * refuses it; nobody waits for its answer, so it resolves with nothing. Otherwise an ordinary POST, its answer
 * through api/http.ts as any request's (a 401 brings the sign-in back).
 */
export function saveQueueAt(body: QueueAt, beacon = false): Promise<SavedQueue | null> {
  if (!beacon) return post<SavedQueue>('/navidrome/queue/at', body)
  const address = url('/navidrome/queue/at')
  const text = JSON.stringify(body)
  let sent = false
  try {
    sent = typeof navigator !== 'undefined' && typeof navigator.sendBeacon === 'function' &&
      navigator.sendBeacon(address, new Blob([text], { type: 'application/json' }))
  } catch {
    sent = false
  }
  if (!sent) {
    fetch(address, { method: 'POST', keepalive: true, headers: { 'Content-Type': 'application/json' }, body: text }).catch(() => {})
  }
  return Promise.resolve(null)
}

/** How long an album asked for ahead of its page opening is worth using. */
export const PREFETCH_KEEP_MS = 30_000

interface Prefetched {
  at: number
  answer: Promise<AlbumWithSongs>
  controller: AbortController | null
  /** someone keeps this answer (Search): a press that turned into a scroll must not call it off */
  kept: boolean
}

const prefetched = new Map<string, Prefetched>()

const albumPath = (id: string) => `/navidrome/albums/${encodeURIComponent(id)}`

/**
 * An album's songs asked for as a finger lands on its tile - before the tap has finished - so the
 * album page usually has them, and Play is live, by the time it opens. A tile never plays anything
 * itself: Play must be pressed on the page, in the same turn as the tap (see "The one app" in
 * CLAUDE.md), and that needs the songs in hand. Asked for once however often it is pressed, and
 * kept for PREFETCH_KEEP_MS.
 *
 * `keep`: the caller holds on to the answer - Search (2.0.0-player.13), whose song rows play once
 * their album is in hand. A tile's press shares the one ask, and a press that turns into a scroll
 * calls it off (dropPrefetch) - which, on an ask Search was waiting for, would have left that
 * album's songs opening the album instead of playing, with nothing asking again (review). So a
 * kept ask is never called off, whoever asked first.
 *
 * `fresh` (2.0.0-player.17): asked anew whatever is held - Requests asking again for an album it
 * asked for before Navidrome could have scanned what a download filed into it.
 */
export function prefetchAlbum(id: string, keep = false, fresh = false): Promise<AlbumWithSongs> {
  const now = Date.now()
  for (const [key, held] of prefetched) if (now - held.at >= PREFETCH_KEEP_MS) prefetched.delete(key)
  const held = fresh ? undefined : prefetched.get(id)
  if (held) {
    if (keep) held.kept = true
    return held.answer
  }
  const controller = typeof AbortController === 'function' ? new AbortController() : null
  const answer = get<AlbumWithSongs>(albumPath(id), controller?.signal)
  //? an ask nobody takes must not report an unhandled rejection; album() hands the answer on as it is.
  //? A FAILED ask is let go (2.0.0-player.17), so the next asks afresh - the album page opening, or
  //? the artist page's Try again - rather than being handed the same failure for the rest of 30 s
  answer.catch(() => {
    if (prefetched.get(id)?.answer === answer) prefetched.delete(id)
  })
  prefetched.set(id, { at: now, answer, controller, kept: keep })
  //? Search keeps the answer it is handed (2.0.0-player.13), so a song's tap plays with its album in
  //? hand; the album page still takes the ask here once, as it opens
  return answer
}

/** The press turned into a scroll: the ask is called off, unless the page already took it - or
 *  someone keeps it (`keep`), and then it stays, for the page to take as well. */
export function dropPrefetch(id: string): void {
  const held = prefetched.get(id)
  if (!held || held.kept) return
  held.controller?.abort()
  prefetched.delete(id)
}

/** One album with its songs: the one asked for as the tile was pressed when there is one, taken
 *  once, else asked for now. */
export function album(id: string, signal?: AbortSignal): Promise<AlbumWithSongs> {
  const held = prefetched.get(id)
  prefetched.delete(id)
  if (held && Date.now() - held.at < PREFETCH_KEEP_MS) return held.answer
  return get(albumPath(id), signal)
}

const played = createPlayedAlbums<AlbumWithSongs>()

/**
 * The album answer a queue is about to be played from, kept for Info (lib/playedAlbums.ts): the
 * queue's own songs carry only what playing needs. Called by the screen that starts playback, in
 * the tap, before it calls the player - it asks nothing of anyone, so the tap loses nothing.
 */
export function rememberPlayed(album: AlbumWithSongs): void {
  played.remember(album)
}

/**
 * The album answers a queue of SEVERAL albums is about to be played from (2.0.0-player.17: an
 * artist's Play and Shuffle), in the order they play - every one kept until the next queue starts,
 * so Info and the turntable know each song's album whichever plays. In the tap, like rememberPlayed.
 */
export function rememberQueue(albums: readonly AlbumWithSongs[]): void {
  played.rememberQueue(albums)
}

/**
 * (2.0.0-player.57) The albums of songs added to Up Next - Play Next and Play Last, from the song menu - in the
 * tap, before the player is called: each kept beside the queue's, which stay (lib/playedAlbums.ts `also`), so
 * Info and the turntable know an added song's album as they know the queue's.
 */
export function rememberAdded(albums: readonly AlbumWithSongs[]): void {
  for (const album of albums) played.also(album)
}

/** The answer a song's album was played from, exactly as Navidrome sent it; null when not in hand. */
export function playedAlbum(id: string | null | undefined): AlbumWithSongs | null {
  return played.get(id)
}

/**
 * The sizes covers are asked for at - three, not one per place a cover is drawn. A cover is a
 * download per SIZE: asked for at 260 for Home, 400 for the Library, 800 for its page, 1000 for
 * Now Playing, 120 for the mini player and 512 for the lock screen, one album came down six times
 * over the phone's connection. Asked for at the step that covers it, the tile Home fetched is the
 * Library's, the album page's cover is Now Playing's and the lock screen's, and a row's is the mini
 * player's - already in the browser's cache when the next screen wants it.
 */
export const COVER_SIZES: readonly number[] = [128, 400, 1024]

/** The step a cover drawn at `size` is asked for at: the smallest that covers it, else the largest. */
export function coverSize(size: number): number {
  return COVER_SIZES.find((step) => step >= size) ?? COVER_SIZES[COVER_SIZES.length - 1]!
}

/**
 * A cover at a size Navidrome resizes to. Asked for at twice the size it is drawn, because every
 * phone this is for has a 2x or 3x screen and a 1x cover looks soft beside the text - and then at
 * one of COVER_SIZES, so the screens share what they fetch.
 */
export function coverUrl(id: string | null | undefined, size: number): string | null {
  return id ? url(`/navidrome/cover/${encodeURIComponent(id)}?size=${coverSize(size)}`) : null
}

/**
 * A cover as Navidrome has it, not resized - the cover viewer's (2.0.0-player.44: an album page's cover
 * opened full size, where its own pixels are the point). No `size`, so the route asks Navidrome for none.
 */
export function coverFullUrl(id: string | null | undefined): string | null {
  return id ? url(`/navidrome/cover/${encodeURIComponent(id)}`) : null
}

/**
 * The turntable's record face (2.0.0-player.11): the CD art deadwax holds for a Navidrome album's
 * disc - a library route, which finds the album's folder itself, not a Navidrome one. A 404 when
 * there is none, and the turntable draws its plain record.
 */
export function discArtUrl(albumId: string | null | undefined, disc: number): string | null {
  const path = discArtPath(albumId, disc)
  return path ? url(path) : null
}

/**
 * What to ask the browser about a song's file. Mostly its content type, but Navidrome gives .ogg,
 * .oga and .opus files the same audio/ogg, and a container says nothing about the codec inside
 * it - so an Ogg file is asked about with its codec, the way Navidrome's own web player probes
 * (ui/src/transcode/browserProfile.js in its source). A .ogg is taken to hold Vorbis, which is
 * what .ogg files nearly always do. Null when nobody said what the file is.
 */
export function playableType(track: Pick<QueueTrack, 'contentType' | 'suffix'>): string | null {
  switch (track.suffix?.toLowerCase()) {
    case 'opus':
      return 'audio/ogg; codecs="opus"'
    case 'ogg':
    case 'oga':
      return 'audio/ogg; codecs="vorbis"'
    default:
      return track.contentType || null
  }
}

/**
 * Where a song's audio is. The file as it is when this browser can play it - which is also the
 * only kind Navidrome can serve byte ranges of, and Safari won't play without them. A transcode
 * to MP3 only for what it can't, which on an iPhone is mostly Ogg and WMA.
 *
 * "As it is" is asked for BY NAME, as format=raw, rather than by leaving the format out. Navidrome
 * answers raw before it consults anything set for this player on its Players page
 * (ResolveRequest, core/stream/legacy_client.go), whereas with no format a transcoding or a max
 * bit rate set there turns every song into a transcode - one with no byte ranges until Navidrome
 * has cached it (core/stream/media_streamer.go answers Accept-Ranges: none) and, from a bit rate
 * alone, in Opus. A file nobody named a type for is sent as it is too: asking for MP3 would be a
 * guess.
 *
 * `pageWraps` - Safari and every iPhone browser (wrapsFlac() in lib/streamWrap) - asks for a FLAC
 * inside an MP4 of the same frames, which is the form of it whose seeks Safari lands exactly.
 *
 * `maxRate` - the "Maximum quality" setting. At 48 kHz a hi-res FLAC (resamples() in lib/streamWrap)
 * is asked for resampled, `max_rate=48000`, which deadwax sends only repackaged: in an MP4 in any
 * browser. 'original', the default here, is every address exactly as it was before the setting.
 *
 * The entry's level (2.0.0-player.62, the player's Normalization - lib/loudness.ts): a FLAC queued with
 * one is asked for levelled, `&level=album` or `&level=track` LAST, which deadwax too sends only in a
 * container it made - so in an MP4 in any browser, as a resampled song is. An entry with no level (Off)
 * has exactly the address it always had.
 */
export function streamUrl(
  track: LevelledTrack, canPlay: (type: string) => boolean, pageWraps = false, maxRate: MaxRate = 'original',
): string {
  const format = streamFormat(track, canPlay)
  const resampled = resamples(track, maxRate, format)
  const levelled = levels(track, format)
  //? deadwax sends a resampled or a levelled song only in a container it made - in any browser
  const wrap = asksForMp4(track, format, pageWraps, resampled || levelled) ? '&wrap=mp4' : ''
  const rate = resampled ? '&max_rate=48000' : ''
  return url(`/navidrome/stream/${encodeURIComponent(track.id)}?format=${format}${wrap}${rate}${levelParam(track, format)}`)
}

/**
 * A FLAC song as fragmented MP4 - the pieces the gapless switch's one stream is made of (see
 * player/streamSource.ts). Always the file as it is: there is no FLAC in a transcode to repackage.
 * Resampled, as streamUrl() says, when `maxRate` is 48 kHz and the song is hi-res; levelled at the
 * entry's level, last, as streamUrl() says.
 */
export function fragmentedUrl(track: LevelledTrack, maxRate: MaxRate = 'original'): string {
  const rate = resamples(track, maxRate, 'raw') ? '&max_rate=48000' : ''
  return url(`/navidrome/stream/${encodeURIComponent(track.id)}?format=raw&wrap=fmp4${rate}${levelParam(track, 'raw')}`)
}

/** Which of the two streamUrl() asks for: the file as it is, or a transcode to MP3. */
export function streamFormat(track: QueueTrack, canPlay: (type: string) => boolean): 'raw' | 'mp3' {
  const type = playableType(track)
  return !type || canPlay(type) ? 'raw' : 'mp3'
}

/**
 * Which of the two a song is asked for as, for Info's "Sent as" row: streamFormat()'s question, put
 * to the player's OWN audio element - the one the engine asks before it chooses an address. Never
 * to a new one: iOS unlocks audio per element, and the app makes none (see "The one app" in
 * CLAUDE.md). It only asks the element what it can play; nothing on it is set or started. Null
 * where there is no element to ask.
 */
export function sentFormat(track: QueueTrack): 'raw' | 'mp3' | null {
  const element = typeof document === 'undefined' ? null : document.querySelector('audio')
  if (!element) return null
  return streamFormat(track, (type) => element.canPlayType(type) !== '')
}

/** The turntable's window of a song, as deadwax answered it: the FLAC's bytes, and exactly where in
 *  the song it sits - its first sample, how many, at what rate (X-Deadwax-Window). */
export interface ScrubWindow {
  bytes: ArrayBuffer
  first: number
  samples: number
  rate: number
}

/**
 * A stretch of a song as a FLAC file of its own, for the turntable's sound (2.0.0-player.14): from
 * `at` seconds, `seconds` long, cut by deadwax from its own MP4 of the song (src/flac_window.py) -
 * starting on a frame at or before `at`, and shorter than asked for a hi-res song. `maxRate` (48000)
 * when the song is played resampled, so the window is cut from that very copy - its rate, its level -
 * as streamUrl() and fragmentedUrl() ask for it - and `level` (2.0.0-player.62) when the song plays
 * levelled, so the window is cut from its levelled copy: what it plays or shows is what is heard.
 * Throws ApiError: a 415 for a song that isn't a FLAC (its detail says so), a 416 past the end, a 503
 * when deadwax can't just now. Never touches the player's own audio.
 */
export async function scrubWindow(
  id: string, at: number, seconds: number, signal?: AbortSignal, maxRate: number | null = null,
  level: Level | null = null,
): Promise<ScrubWindow> {
  const cap = maxRate ? `&max_rate=${maxRate}` : ''
  const levelled = level ? `&level=${level}` : ''
  const response = await fetchOk(`/navidrome/scrub/${encodeURIComponent(id)}?at=${at}&seconds=${seconds}${cap}${levelled}`, signal ? { signal } : undefined)
  const [first, samples, rate] = (response.headers.get('x-deadwax-window') ?? '').split('/').map(Number)
  if (!(Number.isFinite(first) && Number.isFinite(samples) && (rate ?? 0) > 0)) throw new Error("deadwax didn't say where the window is")
  return { bytes: await response.arrayBuffer(), first: first!, samples: samples!, rate: rate! }
}

/**
 * (2.0.0-player.62) What deadwax would level a song at, from what it has measured - Info's Normalization row
 * (src/routes/navidrome.py /level). `maxRate` the cap the engine asked at, as scrubWindow() takes it.
 */
export function levelOf(id: string, level: Level, maxRate: number | null, signal?: AbortSignal): Promise<LevelAnswer> {
  const cap = maxRate ? `&max_rate=${maxRate}` : ''
  return get<LevelAnswer>(`/navidrome/level/${encodeURIComponent(id)}?level=${level}${cap}`, signal)
}

/**
 * (2.0.0-player.62) "This album is about to be played": an album page with its songs in hand has deadwax measure
 * them ahead, so the first levelled play waits less (Part A). Fire and forget - not a playback action, nothing
 * awaits it, and a failure costs only the wait.
 */
export function warmLevels(albumId: string): void {
  //? (2.0.0-player.65) never twice at once: an album page and a play of the same album, or two taps
  if (warming.has(albumId)) return
  warming.add(albumId)
  post(`/navidrome/level/album/${encodeURIComponent(albumId)}`).catch(() => {}).finally(() => warming.delete(albumId))
}

/** The albums whose warmLevels() is on its way. */
const warming = new Set<string>()

/** Fire and forget: a play that isn't counted is not worth interrupting the music over. */
export function scrobble(id: string, submission: boolean, time?: number): void {
  const query = `submission=${submission}${time ? `&time=${time}` : ''}`
  post(`/navidrome/scrobble/${encodeURIComponent(id)}?${query}`).catch((error: unknown) => {
    console.warn('deadwax player: Navidrome did not take the scrobble', error)
  })
}

export function toQueueTrack(song: Song, fallback: AlbumWithSongs): QueueTrack {
  return {
    id: song.id,
    title: song.title,
    artist: song.artist ?? fallback.artist ?? '',
    album: song.album ?? fallback.name,
    albumId: song.albumId ?? fallback.id,
    coverArt: song.coverArt ?? fallback.coverArt ?? null,
    duration: song.duration ?? 0,
    contentType: song.contentType ?? null,
    suffix: song.suffix ?? null,
    sampleRate: song.samplingRate ?? 0,
    bitDepth: song.bitDepth ?? 0,
    channels: song.channelCount ?? 0,
  }
}
