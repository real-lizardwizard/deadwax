/**
 * The player's calls, all to deadwax - which passes each one on to Navidrome with a login the
 * page never sees. See src/routes/navidrome.py for the list, and why it is a list.
 *
 * The shapes are Navidrome's own (the Subsonic API's ID3 calls), trimmed to what the player reads.
 * Every field is optional in the API and treated that way here.
 */

import { fetchOk, get, post, url } from '../api/http'
import { createPlayedAlbums } from '../lib/playedAlbums'
import type { QueueTrack } from '../lib/playQueue'
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
}

/** One disc's own title - MusicBrainz's medium title, which deadwax writes as `discsubtitle` and
 *  Navidrome hands back as OpenSubsonic's `discTitles` on getAlbum. Only the discs that have one. */
export interface DiscTitle {
  disc: number
  title: string
}

export interface AlbumWithSongs extends Album {
  song?: Song[]
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
  order: AlbumOrder, offset: number, signal?: AbortSignal, size: number = PAGE_SIZE,
): Promise<Album[]> {
  const page = await get<{ albums: Album[] }>(
    `/navidrome/albums?order=${order}&size=${size}&offset=${offset}`,
    signal,
  )
  return page.albums
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

/**
 * The library's artists, albums and songs matching `query` (2.0.0-player.13) - Navidrome's search3,
 * through deadwax's route, which declares and bounds every parameter (src/routes/navidrome.py).
 */
export function searchLibrary(query: string, signal?: AbortSignal): Promise<LibraryResults> {
  const params = new URLSearchParams({ q: query })
  for (const [name, count] of Object.entries(SEARCH_COUNTS)) params.set(name, String(count))
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

/** The answer a song's album was played from, exactly as Navidrome sent it; null when not in hand. */
export function playedAlbum(id: string | null | undefined): AlbumWithSongs | null {
  return played.get(id)
}

/**
 * A cover at a size Navidrome resizes to. Asked for at twice the size it is drawn, because every
 * phone this is for has a 2x or 3x screen and a 1x cover looks soft beside the text.
 */
export function coverUrl(id: string | null | undefined, size: number): string | null {
  return id ? url(`/navidrome/cover/${encodeURIComponent(id)}?size=${size}`) : null
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
 */
export function streamUrl(
  track: QueueTrack, canPlay: (type: string) => boolean, pageWraps = false, maxRate: MaxRate = 'original',
): string {
  const format = streamFormat(track, canPlay)
  const resampled = resamples(track, maxRate, format)
  const wrap = asksForMp4(track, format, pageWraps, resampled) ? '&wrap=mp4' : ''
  const rate = resampled ? '&max_rate=48000' : ''
  return url(`/navidrome/stream/${encodeURIComponent(track.id)}?format=${format}${wrap}${rate}`)
}

/**
 * A FLAC song as fragmented MP4 - the pieces the gapless switch's one stream is made of (see
 * player/streamSource.ts). Always the file as it is: there is no FLAC in a transcode to repackage.
 * Resampled, as streamUrl() says, when `maxRate` is 48 kHz and the song is hi-res.
 */
export function fragmentedUrl(track: QueueTrack, maxRate: MaxRate = 'original'): string {
  const rate = resamples(track, maxRate, 'raw') ? '&max_rate=48000' : ''
  return url(`/navidrome/stream/${encodeURIComponent(track.id)}?format=raw&wrap=fmp4${rate}`)
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
 * as streamUrl() and fragmentedUrl() ask for it. Throws ApiError: a 415 for a song that isn't a FLAC
 * (its detail says so), a 416 past the end, a 503 when deadwax can't just now. Never touches the
 * player's own audio.
 */
export async function scrubWindow(
  id: string, at: number, seconds: number, signal?: AbortSignal, maxRate: number | null = null,
): Promise<ScrubWindow> {
  const cap = maxRate ? `&max_rate=${maxRate}` : ''
  const response = await fetchOk(`/navidrome/scrub/${encodeURIComponent(id)}?at=${at}&seconds=${seconds}${cap}`, signal ? { signal } : undefined)
  const [first, samples, rate] = (response.headers.get('x-deadwax-window') ?? '').split('/').map(Number)
  if (!(Number.isFinite(first) && Number.isFinite(samples) && (rate ?? 0) > 0)) throw new Error("deadwax didn't say where the window is")
  return { bytes: await response.arrayBuffer(), first: first!, samples: samples!, rate: rate! }
}

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
