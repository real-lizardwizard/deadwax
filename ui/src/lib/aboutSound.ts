/**
 * Info > About's "Sound" group (2.0.7, UX batch 4) - the song's Format, Gapless and Normalization, said to a
 * listener. James (2026-10-23): "apply that same review to the info panel and everything else. I want to make
 * sure it all provides a good user experience." Until 2.0.7 the group was "Playing", built by Debug's own row
 * functions (lib/debugRows.ts), so every listener read Debug's words: "Album, -3.56 dB · the album at -14.4
 * LUFS" in monospace, "Asked for; deadwax hasn't said yet", "Not levelled - deadwax is running without numpy and
 * soundfile", "On, in one stream", "Navidrome didn't say". Now About has its own formatters, here, from the same
 * inputs as Debug's rows - so the two say one thing in two ways - and Debug, an admin's, keeps the numbers.
 *
 *  - Format: the file plainly ("FLAC, 24-bit, 192 kHz, stereo"), in the text face; "Not known" when Navidrome
 *    gave none of it.
 *  - Gapless: "On" or "Off" - whether the song is inside a one-stream run is Debug's.
 *  - Normalization (the vocabulary's name; "volume" and "adjusted" in its sentences): "Album volume matching,
 *    3.6 dB quieter"; "Checking…" while deadwax hasn't answered; "Off for this song - …" and why in a
 *    listener's words (a server's reason is read by what it is, ABOUT_REASONS, never shown as it is); "Not this
 *    time - …" for a song played as it is this time.
 *
 * Pure, like the rest of lib/; ui/test/info.sim.cjs holds every line to its words, and reads levels.py's reasons
 * so none is said raw.
 */

import { formatWords, NOT_KNOWN, type DebugRow } from './debugRows'
import { levels, type LevelAnswer, type LevelledTrack } from './loudness'
import type { QueueTrack } from './playQueue'
import { isFlac } from './streamWrap'

/** The group's heading (was "Playing", which read like a status - the review's 1.9). */
export const SOUND_TITLE = 'Sound'

/** What About's Normalization says while deadwax hasn't answered (Debug: "Asked for; deadwax hasn't said yet"). */
export const LEVEL_CHECKING = 'Checking…'

/** "Off for this song - …": the start of every line for a song asked for a level and played as it is. */
const OFF_FOR_SONG = 'Off for this song - '

/** The reasons a listener reads for a song deadwax won't level, by what the server's words are. */
export const OFF_WORDS = {
  /** numpy or soundfile can't be loaded, or the player's cache can't be used: nothing can be levelled here */
  server: `${OFF_FOR_SONG}this server can't adjust volume`,
  /** not a FLAC: deadwax levels only FLAC */
  kind: `${OFF_FOR_SONG}only FLAC songs are adjusted`,
  /** a FLAC this browser can't play, so Navidrome sends it as MP3 - with no FLAC in it to level */
  transcoded: `${OFF_FOR_SONG}this device can't play FLAC, so it's sent as MP3`,
  /** too large to hold in memory to make the levelled copy */
  large: `${OFF_FOR_SONG}its file is too large`,
  /** anything else: a file deadwax can't read or measure */
  file: `${OFF_FOR_SONG}its file can't be measured`,
} as const

/**
 * Which listener's line a server reason is (src/levels.py describe()'s `why`): its constants NO_LIBRARIES and
 * NO_CACHE, NOT_FLAC (and player_cache.py's own "it isn't a FLAC file"), the player cache's too-big words ("…MiB
 * a song is held in memory to repackage") - and everything else (UNREADABLE, the channels, the STREAMINFO, a
 * measurement's own error) as a file that can't be measured. info.sim reads each from the Python. Navidrome not
 * answering in time is never a reason here: describe() answers it as 'unmeasured' (its CannotPlan, and the album's
 * asking), so it reads as "Not this time - … hasn't been measured yet".
 */
export const ABOUT_REASONS: readonly (readonly [RegExp, keyof typeof OFF_WORDS])[] = [
  [/without numpy|player's cache can't be used/, 'server'],
  [/^it isn't a FLAC file/, 'kind'],
  [/MiB a song is held in memory/, 'large'],
]

/** The listener's line for deadwax's reason not to level a song. */
export function offWords(why: string | null | undefined): string {
  const words = why ?? ''
  const found = ABOUT_REASONS.find(([pattern]) => pattern.test(words))
  return OFF_WORDS[found ? found[1] : 'file']
}

/** A gain as a listener reads it: "3.6 dB quieter", "1.2 dB louder", "no change needed". */
export function volumeChange(gain: number): string {
  const size = Math.abs(gain).toFixed(1)
  if (size === '0.0') return 'no change needed'
  return `${size} dB ${gain < 0 ? 'quieter' : 'louder'}`
}

/**
 * About's Normalization, in words - the same states Debug's describeLevel() (lib/loudness.ts) reads, said to a
 * listener: Off; off for this song, and why; checking; measuring (and how far along an album is); not this
 * time; "Album volume matching, 3.6 dB quieter" - "as loud as it can go without distorting" when its peak held
 * it, "kept as it is" when its peak held it at no change at all, "nothing to adjust" for a silent one.
 */
export function aboutLevel(
  track: Pick<LevelledTrack, 'suffix' | 'contentType' | 'level'>,
  format: 'raw' | 'mp3' | null,
  answer: LevelAnswer | null,
): string {
  if (!track.level) return 'Off'
  if (!levels(track, format ?? 'raw')) return isFlac(track) ? OFF_WORDS.transcoded : OFF_WORDS.kind
  if (!answer) return LEVEL_CHECKING
  if (answer.state === 'not_levelled') return offWords(answer.why)
  const whose = answer.level === 'album' ? 'album' : 'song'
  if (answer.state === 'measuring') {
    return answer.level === 'album'
      ? `Measuring the album… (${answer.measured_songs} of ${answer.songs} ${answer.songs === 1 ? 'song' : 'songs'})`
      : 'Measuring the song…'
  }
  //? answered as it is this time, its level not to be had in time (Debug's "Played as it is this time")
  if (answer.state === 'plain') return `Not this time - the ${whose} was still being measured`
  if (answer.state === 'unmeasured' || answer.gain_db === null) return `Not this time - the ${whose} hasn't been measured yet`
  const head = `${answer.level === 'album' ? 'Album' : 'Song'} volume matching`
  if (answer.loudness_lufs === null) return `${head} - nothing to adjust, the ${whose} is silent`
  //? held by its peak at a gain that rounds to nothing: a change was wanted and couldn't be made - never "no
  //? change needed" (a quiet master that already peaks at full scale)
  if (answer.held && (answer.wanted_db ?? 0) > 0 && Math.abs(answer.gain_db).toFixed(1) === '0.0') return `${head} - kept as it is, it can't go louder without distorting`
  const change = `${head}, ${volumeChange(answer.gain_db)}`
  return answer.held ? `${change} - as loud as it can go without distorting` : change
}

/** What About's Sound group is drawn from: Debug's own inputs. */
export interface SoundInput {
  track: QueueTrack
  gapless: boolean
  format: 'raw' | 'mp3' | null
  level: LevelAnswer | null | undefined
}

/** About's Sound group, top to bottom: Format, Gapless, Normalization - in the text face, every one. */
export function soundRows(input: SoundInput): DebugRow[] {
  const track = input.track as LevelledTrack
  const answer = input.level && input.level.level === track.level ? input.level : null
  return [
    { label: 'Format', value: formatWords(input.track) || NOT_KNOWN },
    { label: 'Gapless', value: input.gapless ? 'On' : 'Off' },
    { label: 'Normalization', value: aboutLevel(track, input.format, answer) },
  ]
}
