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
 * FILLED IN since 2.0.0-player.17, from `details` - what Info asks for as it opens (app/
 * useInfoDetails.ts): the song as Navidrome has it now (getSong: "played 12 times", "Written by …"),
 * the store's folder of the album (the id bridge: "This pressing: …" and the folder itself), and the
 * artist (getArtist: "4 albums in your library"; MusicBrainz's facts: "Group · London · 1965 to
 * 2014"), whose card goes to their page. Every one of them by the same rule: not sent, not drawn -
 * each is a key of the answer only when there is something to say.
 *
 * WHOSE card it is (`cardArtist`): the song's own artist, as the card is titled - the album's artist
 * only when that is the same person: the same name, the same Navidrome artist, or (`details.artist`,
 * which useInfoDetails decides by MusicBrainz id) a renamed artist's old credit - Kanye West's verse
 * on a Ye album goes to Ye's page, as the album is filed. A Portishead track on a compilation goes to
 * Portishead's, with Portishead's facts and count, never Various Artists' under Portishead's name
 * (review). The facts and the count are drawn only for the artist the card goes to.
 *
 * Pure, like the rest of lib/; ui/test/info.sim.cjs holds it to the answers.
 */

import type { ArtistFactsLight, StoreAlbumResponse } from '../api/types'
import { albumCountLine, factsLine } from './artistPage'
import { discHeadings, type DiscTitleEntry } from './discTitles'
import { sharedFormat, trackTime } from './format'
import { folderLine, pressingLine } from './idBridge'
import type { QueueTrack } from './playQueue'

/** A song as Navidrome's album answer carries it - only what About reads, every field optional. */
export interface AboutSongFields {
  id?: string
  artist?: string
  artistId?: string
  track?: number
  discNumber?: number
  duration?: number
  suffix?: string
  /** omitted by Navidrome until the song has been played */
  playCount?: number
  /** OpenSubsonic: who wrote it, as one line */
  displayComposer?: string
  /** OpenSubsonic: everyone credited, by role */
  contributors?: readonly { role?: string; artist?: { name?: string } }[]
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
  /** the album artist's Navidrome id: where the artist's card goes */
  artistId?: string
  /** OpenSubsonic: the labels the files name */
  recordLabels?: readonly { name?: string }[]
}

/** What Info asks for as it opens (app/useInfoDetails.ts) - each null until, or unless, it answers. */
export interface AboutDetails {
  /** the song as Navidrome has it now: its play count, its writers */
  song?: AboutSongFields | null
  /** the id bridge's answer for the song's album: its folder and edition */
  store?: Pick<StoreAlbumResponse, 'present'> | null
  /** the artist the card goes to, as Navidrome has them: how many albums of theirs you have */
  artist?: { id?: string; albumCount?: number } | null
  /** who they are, from MusicBrainz - the artist the card goes to (`artist.id`) */
  facts?: ArtistFactsLight | null
}

export interface About {
  song: {
    title: string
    artist: string
    /** "Track 4 of 10 · 7:05 · played 12 times", then "Disc 2 · Unreleased Tracks" - each only when known */
    lines: string[]
    /** "Nick Mason, Roger Waters" - only when Navidrome names a writer */
    writtenBy?: string
  }
  /** null when the song names no album at all */
  album: {
    /** what "Go to album" opens; null when the queue has no id for it */
    id: string | null
    title: string
    coverArt: string | null
    /** "1973 · Harvest · FLAC · 10 songs" - '' when none of it is known */
    line: string
    /** "This pressing: 20th Anniversary Reissue 180gram · 2014 · FLAC" - only when the store holds it */
    pressing?: string
    /** its folder in the library (one per line for a set kept one per disc) - only when known */
    folder?: string
  } | null
  /** null when nobody named one */
  artist: {
    name: string
    /** the album's own artist, when it isn't the song's - a compilation, a guest */
    note: string | null
    /** Navidrome's id for the artist the card goes to (cardArtist) - only when known */
    id?: string
    /** ...and the name their page goes by: the album's artist when the card goes to them */
    pageName?: string
    /** "Group · London · 1965 to 2014" - only when MusicBrainz said */
    facts?: string
    /** "4 albums in your library" - only when Navidrome counted */
    count?: string
  } | null
}

/** Who wrote a song, as Navidrome sends it: OpenSubsonic's one line, else its composers. */
export function writtenBy(song: AboutSongFields | null | undefined): string {
  const line = (song?.displayComposer ?? '').trim()
  if (line) return line
  const names = (song?.contributors ?? [])
    .filter((credit) => (credit.role ?? '').toLowerCase() === 'composer')
    .map((credit) => (credit.artist?.name ?? '').trim())
    .filter(Boolean)
  return [...new Set(names)].join(', ')
}

/** "played 12 times", "played once" - '' for a song never played (Navidrome then sends no count). */
export function playedLine(count: number | null | undefined): string {
  const plays = whole(count)
  return plays ? (plays === 1 ? 'played once' : `played ${plays} times`) : ''
}

/** The labels the files name, joined: "Harvest", "Go! Beat / London". */
export function labelLine(labels: readonly { name?: string }[] | null | undefined): string {
  return [...new Set((labels ?? []).map((label) => (label.name ?? '').trim()).filter(Boolean))].join(' / ')
}

const discOf = (song: AboutSongFields): number => song.discNumber || 1
const whole = (value: unknown): number => (typeof value === 'number' && Number.isInteger(value) && value > 0 ? value : 0)
/** Two artist names that are one: case and spaces aside. */
export const sameName = (a: string, b: string) => a.trim().toLowerCase() === b.trim().toLowerCase()

/**
 * The artist Info's card goes to, before useInfoDetails has said more (by Navidrome's ids): the
 * album's artist when it is the song's - no song artist known, the same id, or the same name - else
 * the song's own. '' for neither. useInfoDetails asks about this one, and - two different artists -
 * the album's too, and says the album's when MusicBrainz says they are one person.
 */
export function cardArtist(names: { song: string; album: string }, ids: { song?: string | null | undefined; album?: string | null | undefined }): string {
  const song = ids.song || ''
  const album = ids.album || ''
  if (!song || !album || song === album || (names.album && sameName(names.album, names.song))) return album || song
  return song
}

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
export function aboutRows(track: QueueTrack, album: AboutAlbumFields | null, details: AboutDetails | null = null): About {
  const songs = album?.song ?? []
  const song = songs.find((candidate) => candidate.id === track.id) ?? null
  //? the song as Navidrome has it now, else as it was when the album was played from
  const fresh = details?.song && details.song.id === track.id ? details.song : null

  const length = trackTime(song?.duration ?? track.duration)
  const played = playedLine(fresh ? fresh.playCount : song?.playCount)
  const first = [song ? trackOf(song, songs) : '', length, played].filter(Boolean).join(' · ')
  const lines = [first, song && album ? discLine(song, album) : ''].filter(Boolean)
  const writers = writtenBy(fresh ?? song)

  const title = album?.name || track.album
  const count = songs.length || whole(album?.songCount)
  const albumLine = [
    whole(album?.year) ? String(album!.year) : '',
    labelLine(album?.recordLabels),
    sharedFormat(songs) ?? '',
    count ? `${count} ${count === 1 ? 'song' : 'songs'}` : '',
  ].filter(Boolean).join(' · ')
  const present = details?.store?.present ?? []
  const pressing = pressingLine(present)
  const folder = folderLine(present)

  const name = song?.artist || track.artist || album?.artist || ''
  const albumArtist = album?.artist ?? ''
  //? the card goes to the song's artist, or the album's when it is the same person (cardArtist) -
  //? useInfoDetails's word on it once it has asked, which is only ever one of those two
  const ids = { song: song?.artistId || fresh?.artistId, album: album?.artistId }
  const decided = details?.artist?.id && (details.artist.id === ids.song || details.artist.id === ids.album) ? details.artist.id : ''
  const artistId = decided || cardArtist({ song: name, album: albumArtist }, ids)
  const pageName = artistId && artistId === album?.artistId ? albumArtist || name : name
  const theirs = !!details?.artist && details.artist.id === artistId
  const facts = theirs ? factsLine(details?.facts ?? null) : ''
  const held = theirs ? albumCountLine(details!.artist!.albumCount) : ''

  return {
    song: { title: track.title, artist: track.artist, lines, ...(writers ? { writtenBy: writers } : {}) },
    album: title
      ? {
          id: track.albumId ?? album?.id ?? null, title, coverArt: album?.coverArt ?? track.coverArt ?? null, line: albumLine,
          ...(pressing ? { pressing } : {}), ...(folder ? { folder } : {}),
        }
      : null,
    artist: name
      ? {
          name, note: albumArtist && !sameName(albumArtist, name) ? `The album is by ${albumArtist}` : null,
          ...(artistId ? { id: artistId, pageName } : {}), ...(facts ? { facts } : {}), ...(held ? { count: held } : {}),
        }
      : null,
  }
}
