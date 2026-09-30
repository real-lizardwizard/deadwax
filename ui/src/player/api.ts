/**
 * The player's calls, all to deadwax - which passes each one on to Navidrome with a login the
 * page never sees. See src/routes/navidrome.py for the list, and why it is a list.
 *
 * The shapes are Navidrome's own (the Subsonic API's ID3 calls), trimmed to what the player reads.
 * Every field is optional in the API and treated that way here.
 */

import { get, post, url } from '../api/http'
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
  coverArt?: string
  songCount?: number
  /** seconds */
  duration?: number
  year?: number
  genre?: string
}

export interface Song {
  id: string
  title: string
  album?: string
  albumId?: string
  artist?: string
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

/** How long an album asked for ahead of its page opening is worth using. */
export const PREFETCH_KEEP_MS = 30_000

interface Prefetched {
  at: number
  answer: Promise<AlbumWithSongs>
  controller: AbortController | null
}

const prefetched = new Map<string, Prefetched>()

const albumPath = (id: string) => `/navidrome/albums/${encodeURIComponent(id)}`

/**
 * An album's songs asked for as a finger lands on its tile - before the tap has finished - so the
 * album page usually has them, and Play is live, by the time it opens. A tile never plays anything
 * itself: Play must be pressed on the page, in the same turn as the tap (see "The one app" in
 * CLAUDE.md), and that needs the songs in hand. Asked for once however often it is pressed, and
 * kept for PREFETCH_KEEP_MS.
 */
export function prefetchAlbum(id: string): void {
  const now = Date.now()
  for (const [key, held] of prefetched) if (now - held.at >= PREFETCH_KEEP_MS) prefetched.delete(key)
  if (prefetched.has(id)) return
  const controller = typeof AbortController === 'function' ? new AbortController() : null
  const answer = get<AlbumWithSongs>(albumPath(id), controller?.signal)
  //? an ask nobody takes must not report an unhandled rejection; album() hands the answer on as it is
  answer.catch(() => {})
  prefetched.set(id, { at: now, answer, controller })
}

/** The press turned into a scroll: the ask is called off, unless the page already took it. */
export function dropPrefetch(id: string): void {
  prefetched.get(id)?.controller?.abort()
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
