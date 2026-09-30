/**
 * Info > About, in the app's now-playing screen (2.0.0-player.10): the song, its album and its
 * artist, from what the app already has - the queue's own copy of the song and the album answer
 * its songs were played from. Nothing here asks a server for anything.
 *
 * James: "I'd like the info to be more about the song, album, and artist". The rule for every
 * line: a field Navidrome didn't send is LEFT OUT, never guessed and never filled with a
 * placeholder. No year means no year in the album's line; an album that isn't in hand means no
 * "Track 4 of 10", only the length the queue knows.
 *
 * The disc line is the album page's own heading for the song's disc (lib/discTitles.ts): "Disc 2 ·
 * Unreleased Tracks" - the title deadwax writes as `discsubtitle` and Navidrome hands back as
 * `discTitles`. Shown when the album page would show headings at all: more than one disc, or a
 * disc with a title.
 *
 * Pure, like the rest of lib/; ui/test/info.sim.cjs holds it to the answers.
 */

import { discHeadings, type DiscTitleEntry } from './discTitles'
import { sharedFormat, trackTime } from './format'
import type { QueueTrack } from './playQueue'

/** A song as Navidrome's album answer carries it - only what About reads, every field optional. */
export interface AboutSongFields {
  id?: string
  artist?: string
  track?: number
  discNumber?: number
  duration?: number
  suffix?: string
}

/** The album answer the playing songs came from - only what About reads. */
export interface AboutAlbumFields {
  id?: string
  name?: string
  artist?: string
  year?: number
  coverArt?: string
  songCount?: number
  song?: readonly AboutSongFields[]
  discTitles?: readonly DiscTitleEntry[]
}

export interface About {
  song: {
    title: string
    artist: string
    /** "Track 4 of 10 · 7:05", then "Disc 2 · Unreleased Tracks" - each only when known */
    lines: string[]
  }
  /** null when the song names no album at all */
  album: {
    /** what "Go to album" opens; null when the queue has no id for it */
    id: string | null
    title: string
    coverArt: string | null
    /** "1973 · FLAC · 10 songs" - '' when none of it is known */
    line: string
  } | null
  /** null when nobody named one */
  artist: {
    name: string
    /** the album's own artist, when it isn't the song's - a compilation, a guest */
    note: string | null
  } | null
}

const discOf = (song: AboutSongFields): number => song.discNumber || 1
const whole = (value: unknown): number => (typeof value === 'number' && Number.isInteger(value) && value > 0 ? value : 0)
const same = (a: string, b: string) => a.trim().toLowerCase() === b.trim().toLowerCase()

/**
 * "Track 4 of 10": the song's own track number, of the songs on its disc - track numbers start
 * again on each disc of a set deadwax filed. A number past its disc's count (files numbered
 * straight through the set) is counted against the whole album instead, and past that the count is
 * left out. '' when the song has no track number.
 */
function trackOf(song: AboutSongFields, songs: readonly AboutSongFields[]): string {
  const number = whole(song.track)
  if (!number) return ''
  const onDisc = songs.filter((other) => discOf(other) === discOf(song)).length
  const of = number <= onDisc ? onDisc : number <= songs.length ? songs.length : 0
  return of ? `Track ${number} of ${of}` : `Track ${number}`
}

/**
 * The heading the album page draws over the song's disc, or '' where it draws none - read off the
 * album page's own discHeadings(), so the two can't disagree: the heading above the first song of
 * the song's disc.
 */
function discLine(song: AboutSongFields, album: AboutAlbumFields): string {
  const songs = album.song ?? []
  const first = songs.findIndex((other) => discOf(other) === discOf(song))
  return (first === -1 ? null : discHeadings(songs, album.discTitles)[first]) ?? ''
}

/**
 * What About shows for the song playing. `album` is the answer its queue was played from, or null
 * when that isn't in hand (the lines that need it are then left out).
 */
export function aboutRows(track: QueueTrack, album: AboutAlbumFields | null): About {
  const songs = album?.song ?? []
  const song = songs.find((candidate) => candidate.id === track.id) ?? null

  const length = trackTime(song?.duration ?? track.duration)
  const first = [song ? trackOf(song, songs) : '', length].filter(Boolean).join(' · ')
  const lines = [first, song && album ? discLine(song, album) : ''].filter(Boolean)

  const title = album?.name || track.album
  const count = songs.length || whole(album?.songCount)
  const albumLine = [
    whole(album?.year) ? String(album!.year) : '',
    sharedFormat(songs) ?? '',
    count ? `${count} ${count === 1 ? 'song' : 'songs'}` : '',
  ].filter(Boolean).join(' · ')

  const name = song?.artist || track.artist || album?.artist || ''
  const albumArtist = album?.artist ?? ''

  return {
    song: { title: track.title, artist: track.artist, lines },
    album: title
      ? { id: track.albumId ?? album?.id ?? null, title, coverArt: album?.coverArt ?? track.coverArt ?? null, line: albumLine }
      : null,
    artist: name
      ? { name, note: albumArtist && !same(albumArtist, name) ? `The album is by ${albumArtist}` : null }
      : null,
  }
}
