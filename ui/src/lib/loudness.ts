/**
 * The player's Normalization (2.0.0-player.62): which level a song is played at, and the words Info says
 * about it.
 *
 * James: "I'd like the default to be album-wide normalization when an album is played, but when any single
 * song is played, it should be song normalization." deadwax's server applies the gain, in the copy it makes of
 * a FLAC song for the player (src/levels.py, src/loudness.py): an iPhone locks the audio element's volume, and
 * Web Audio on the playing element is banned. So the page only says which level it wants - `level=album` or
 * `level=track` on the song's address (player/api.ts) - and the level rides ON the queue entry: the engine keeps
 * track objects by reference, so every address built from an entry carries the level it was queued with.
 *
 * The rule, in one sentence: Automatic levels by album whatever you queued as an album - an album page's Play
 * or a row, an album's Play Next or Play Last, a Search song's tap (it plays its album from that song), a
 * request's ▶, an artist's Play - and song by song everything else: a playlist, a shuffle, a song you add.
 * By song and By album do what they say whatever was queued; Off asks for no level at all, and queues exactly
 * what was queued before this setting existed - the same array, the same objects.
 *
 * Pure, like the rest of lib/, so ui/test/loudness.sim.cjs holds it to the table.
 */

import type { QueueTrack } from './playQueue'
import { isFlac } from './streamWrap'

/** The setting, per device (state/persisted's readPlayerNormalization). */
export type Normalization = 'auto' | 'song' | 'album' | 'off'
export const DEFAULT_NORMALIZATION: Normalization = 'auto'

/** How the songs were queued: an album played as an album, or songs. */
export type QueuedAs = 'album' | 'songs'

/** What deadwax is asked for: the song's album's gain, or its own. */
export type Level = 'album' | 'track'

/**
 * A queue entry with the level it was queued at. Declared here, not in playQueue.ts (an engine file): a
 * QueueTrack is one (the field is optional), so the address builders take what the engine hands them and
 * read the level off the very object the page queued.
 */
export type LevelledTrack = QueueTrack & { level?: Level }

/** The level a setting asks for, for songs queued `as` - undefined for none (Off). */
export function levelFor(setting: Normalization, as: QueuedAs): Level | undefined {
  if (setting === 'off') return undefined
  if (setting === 'song') return 'track'
  if (setting === 'album') return 'album'
  return as === 'album' ? 'album' : 'track'
}

/**
 * The tracks with `level` set - a copy of each - or, with no level (Off), THE SAME ARRAY of the same
 * objects, so Off queues exactly what was queued before the setting existed.
 */
export function atLevel<T extends QueueTrack>(tracks: T[], level: Level | undefined): Array<T & { level?: Level }> {
  if (level === undefined) return tracks
  return tracks.map((track) => ({ ...track, level }))
}

/** The tracks as the setting queues them, queued `as` an album or as songs. */
export function levelled<T extends QueueTrack>(tracks: T[], setting: Normalization, as: QueuedAs): Array<T & { level?: Level }> {
  return atLevel(tracks, levelFor(setting, as))
}

/**
 * Whether deadwax is asked to level this song: a level on the entry, a FLAC, and the file as it is (a
 * transcode to MP3 has no FLAC in it to level). An MP3, an Opus or an AAC file never is - deadwax levels
 * only FLAC, and they play as they are.
 */
export function levels(track: Pick<LevelledTrack, 'suffix' | 'contentType' | 'level'>, format: 'raw' | 'mp3'): boolean {
  return !!track.level && format === 'raw' && isFlac(track)
}

/**
 * The track without its level - the same object when it has none. The engine asks for a levelled copy
 * deadwax made and the browser couldn't decode as the file itself, WITHOUT its level, as it asks for a
 * refused resampled copy as the song as it is: asked again with its level, deadwax would only make the same
 * copy again.
 */
export function unlevelled<T extends LevelledTrack>(track: T): T {
  if (!track.level) return track
  const { level: _level, ...rest } = track
  return rest as T
}

/** What a song's address ends with: `&level=album`, `&level=track`, or nothing. LAST in the query, after
 *  `&max_rate`, so every address with no level is the same string it always was. */
export function levelParam(track: Pick<LevelledTrack, 'suffix' | 'contentType' | 'level'>, format: 'raw' | 'mp3'): string {
  return levels(track, format) ? `&level=${track.level}` : ''
}

/** deadwax's answer about a song's level (GET /deadwax/navidrome/level/{id}, src/levels.py describe()). */
export interface LevelAnswer {
  level: Level
  state: 'measured' | 'measuring' | 'unmeasured' | 'plain' | 'not_levelled'
  gain_db: number | null
  wanted_db: number | null
  loudness_lufs: number | null
  peak_db: number | null
  held: boolean
  songs: number
  measured_songs: number
  why: string | null
}

/** A gain as Info says it: +1.20 dB, -7.42 dB. */
export function signedDb(value: number): string {
  const fixed = Math.abs(value).toFixed(2)
  return `${value < 0 && fixed !== '0.00' ? '-' : '+'}${fixed} dB`
}

/** A loudness as Info says it: -10.6 LUFS. */
function lufs(value: number): string {
  const fixed = Math.abs(value).toFixed(1)
  return `${value < 0 && fixed !== '0.0' ? '-' : ''}${fixed} LUFS`
}

/** What a song plays as when it isn't levelled because of what it is: "MP3 songs play as they are". */
function kindWords(track: Pick<LevelledTrack, 'suffix' | 'contentType'>): string {
  const kind = track.suffix ? track.suffix.toUpperCase() : ''
  return kind ? `${kind} songs play as they are` : 'only FLAC songs are levelled'
}

/** What Debug says while deadwax hasn't answered about a levelled song. */
export const LEVEL_NOT_KNOWN_YET = "Asked for; deadwax hasn't said yet"

/**
 * Info > Debug's Normalization row, in words: Off; not levelled and why; Album or Song, the gain, and the
 * loudness it came from - or the peak that held it; measuring (and how far along an album is); not measured
 * yet. `answer` is deadwax's (null while it hasn't answered, or for a song asked for no level).
 */
export function describeLevel(
  track: Pick<LevelledTrack, 'suffix' | 'contentType' | 'level'>,
  format: 'raw' | 'mp3' | null,
  answer: LevelAnswer | null,
): string {
  if (!track.level) return 'Off'
  if (!levels(track, format ?? 'raw')) return `Not levelled - ${kindWords(track)}`
  if (!answer) return LEVEL_NOT_KNOWN_YET
  if (answer.state === 'not_levelled') return `Not levelled - ${answer.why ?? "deadwax won't level it"}`
  if (answer.state === 'measuring') {
    return answer.level === 'album'
      ? `Measuring its album\u2026 (${answer.measured_songs} of ${answer.songs} ${answer.songs === 1 ? 'song' : 'songs'})`
      : 'Measuring the song\u2026'
  }
  //? (after review) deadwax answered it as it is this time - its level not to be had in time: what is heard, whatever
  //? has been measured since
  if (answer.state === 'plain') {
    return `Played as it is this time - its ${answer.level === 'album' ? 'album was' : 'loudness was'} still being measured`
  }
  if (answer.state === 'unmeasured' || answer.gain_db === null) return 'Not measured yet - it played as it is this time'
  const whose = answer.level === 'album' ? 'album' : 'song'
  const head = `${answer.level === 'album' ? 'Album' : 'Song'}, ${signedDb(answer.gain_db)}`
  if (answer.held && answer.wanted_db !== null) return `${head} \u00b7 held there by its peak (it wanted ${signedDb(answer.wanted_db).replace(' dB', '')})`
  if (answer.loudness_lufs === null) return `${head} \u00b7 the ${whose} is silent`
  return `${head} \u00b7 the ${whose} at ${lufs(answer.loudness_lufs)}`
}
