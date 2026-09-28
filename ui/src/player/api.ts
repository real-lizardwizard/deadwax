/**
 * The player's calls, all to deadwax - which passes each one on to Navidrome with a login the
 * page never sees. See src/routes/navidrome.py for the list, and why it is a list.
 *
 * The shapes are Navidrome's own (the Subsonic API's ID3 calls), trimmed to what the player reads.
 * Every field is optional in the API and treated that way here.
 */

import { get, post, url } from '../api/http'
import type { QueueTrack } from '../lib/playQueue'
import { asksForMp4 } from '../lib/streamWrap'

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
}

export interface AlbumWithSongs extends Album {
  song?: Song[]
}

/** Subsonic's own orders for an album list, as the routes accept them. */
export type AlbumOrder = 'newest' | 'alphabeticalByName' | 'alphabeticalByArtist' | 'recent'

export const PAGE_SIZE = 60

export function navidromeStatus(): Promise<NavidromeStatus> {
  return get('/navidrome/status')
}

export async function albumPage(order: AlbumOrder, offset: number, signal?: AbortSignal): Promise<Album[]> {
  const page = await get<{ albums: Album[] }>(
    `/navidrome/albums?order=${order}&size=${PAGE_SIZE}&offset=${offset}`,
    signal,
  )
  return page.albums
}

export function album(id: string, signal?: AbortSignal): Promise<AlbumWithSongs> {
  return get(`/navidrome/albums/${encodeURIComponent(id)}`, signal)
}

/**
 * A cover at a size Navidrome resizes to. Asked for at twice the size it is drawn, because every
 * phone this is for has a 2x or 3x screen and a 1x cover looks soft beside the text.
 */
export function coverUrl(id: string | null | undefined, size: number): string | null {
  return id ? url(`/navidrome/cover/${encodeURIComponent(id)}?size=${size}`) : null
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
 */
export function streamUrl(track: QueueTrack, canPlay: (type: string) => boolean, pageWraps = false): string {
  const format = streamFormat(track, canPlay)
  const wrap = asksForMp4(track, format, pageWraps) ? '&wrap=mp4' : ''
  return url(`/navidrome/stream/${encodeURIComponent(track.id)}?format=${format}${wrap}`)
}

/** Which of the two streamUrl() asks for: the file as it is, or a transcode to MP3. */
export function streamFormat(track: QueueTrack, canPlay: (type: string) => boolean): 'raw' | 'mp3' {
  const type = playableType(track)
  return !type || canPlay(type) ? 'raw' : 'mp3'
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
  }
}
