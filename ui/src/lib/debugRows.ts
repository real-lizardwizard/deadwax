/**
 * Info > Debug, in the app's now-playing screen (2.0.0-player.10): what the song's file is, what
 * this device was sent of it and why, how the last song changes and the last seek went, and the
 * names of the fields Navidrome sent - as labelled rows.
 *
 * Until 2.0.0-player.10 the first three were two lines at the top of the now-playing sheet (the
 * gapless readout and the "Last seek" line). James: "the 'in one stream' and the quality shouldn't
 * be displayed in the player, at least not by default, but I would like an 'info' tab in the menu
 * in the player that would show you everything". So they moved here, and the rows are BUILT ON the
 * same three functions the lines were - describeGaps() (lib/gapless), describeSeek() (lib/scrub)
 * and describeWrap() (lib/streamWrap) - so the words the guide explains, and the sims pin, are the
 * words still shown: "handed over, from memory", "in one stream", "FLAC in MP4", "the song ended
 * on time, so it landed there".
 *
 * "Navidrome sent" lists the NAMES of the fields on the playing song and on its album, as
 * deadwax's route passed them through untouched. It is there so the fields later screens want to
 * rely on (musicBrainzId, played, playCount, discTitles...) can be read off a phone against a real
 * Navidrome first. Names only: what Navidrome sent, never what deadwax hoped for, and never a
 * value - but a name alone misleads both ways, so two things more are said. Navidrome writes some
 * fields ALWAYS, empty when the file has nothing (musicBrainzId as "", discTitles as [], bitDepth
 * as 0), so a listed name isn't a value: those are named apart, as "Empty". And it leaves others
 * out whenever they are zero or never set (playCount and played on a song never played, starred,
 * userRating, year...), so a missing name isn't a field it can't send: the names other songs of
 * the album carry and this one doesn't are named too.
 *
 * Pure, like the rest of lib/, so ui/test/debug.sim.cjs holds every row to its words.
 */

import type { DeckReport } from './deckVoice'
import { describeGaps, type GapReading } from './gapless'
import type { QueueTrack } from './playQueue'
import { clock, describeSeek, type SeekReading } from './scrub'
import { RESAMPLED_TO, describeWrap, isFlac, resamples, type MaxRate, type Wrapped } from './streamWrap'

/** How much quieter deadwax sends a resampled song, in dB - src/resample.py's HEADROOM_DB, which
 *  the sim reads and holds this to. */
export const RESAMPLE_HEADROOM_DB = 3

/** The "Maximum quality" choices by the names You gives them (app/QualityChoice.tsx; the sim holds
 *  the two to each other). */
export const MAX_RATE_LABELS: Readonly<Record<MaxRate, string>> = {
  '48000': 'Up to 48 kHz',
  original: 'Original',
}

/** What Info says where there is nothing to say. */
export const NOT_KNOWN = 'Not known'

export interface DebugRow {
  label: string
  value: string
  /** a second, smaller line under the value - the song changes before the last */
  note?: string
  /** a data value - numbers, rates, field names - set in the monospace face */
  mono?: boolean
}

export interface DebugSection {
  title: string
  rows: DebugRow[]
}

export interface DebugInput {
  track: QueueTrack
  /** whether Gapless is on */
  gapless: boolean
  maxRate: MaxRate
  gaps: GapReading[]
  lastSeek: SeekReading | null
  wrapped: Wrapped | null
  /**
   * Which of the two the player asks Navidrome for: the file as it is, or a transcode to MP3 for a
   * file this browser can't play (streamFormat() in player/api.ts). Null when nobody could say.
   */
  format: 'raw' | 'mp3' | null
  /** the playing song and its album exactly as Navidrome's answer gave them; null when not in hand */
  song: Readonly<Record<string, unknown>> | null
  album: Readonly<Record<string, unknown>> | null
  /** the turntable's sound (2.0.0-player.14, player/deck.ts): null while no turntable shows */
  turntable?: DeckReport | null
}

/** A rate as every row says it: 192 kHz, 44.1 kHz. */
function khz(rate: number): string {
  return `${rate / 1000} kHz`
}

function channelWords(channels: number): string {
  if (channels === 1) return 'mono'
  if (channels === 2) return 'stereo'
  return `${channels} channels`
}

const upperFirst = (words: string) => (words ? words[0]!.toUpperCase() + words.slice(1) : words)

/** The file's kind in capitals - FLAC, MP3 - from its extension, else from its type; '' unknown. */
function kindOf(track: Pick<QueueTrack, 'suffix' | 'contentType'>): string {
  if (track.suffix) return track.suffix.toUpperCase()
  const type = (track.contentType ?? '').split(';')[0]!.trim().toLowerCase()
  return type.startsWith('audio/') ? type.slice('audio/'.length).replace(/^x-/, '').toUpperCase() : ''
}

/** A depth and a rate as a row's tail: ", 24-bit, 48 kHz" - each left out when nobody said. */
function depthAndRate(depth: number, rate: number): string {
  return [depth > 0 ? `${depth}-bit` : '', rate > 0 ? khz(rate) : ''].filter(Boolean).map((part) => `, ${part}`).join('')
}

/**
 * The file as Navidrome read it: "FLAC, 24-bit, 192 kHz, stereo". From OpenSubsonic's
 * samplingRate, bitDepth and channelCount, which the queue keeps as 0 when Navidrome didn't say -
 * and a part nobody gave is left out, never guessed.
 */
export function formatRow(track: QueueTrack): DebugRow {
  const parts = [
    kindOf(track),
    track.bitDepth > 0 ? `${track.bitDepth}-bit` : '',
    track.sampleRate > 0 ? khz(track.sampleRate) : '',
    track.channels > 0 ? channelWords(track.channels) : '',
  ].filter(Boolean)
  return { label: 'Format', value: parts.length ? parts.join(', ') : "Navidrome didn't say", mono: true }
}

/** What came back for THIS song when it was asked for inside an MP4, or null. */
function wrappedFor(wrapped: Wrapped | null, track: QueueTrack): Wrapped | null {
  return wrapped && wrapped.id === track.id ? wrapped : null
}

/**
 * Asked for resampled, and deadwax hasn't said yet what it did: in an MP4, before the answer's
 * headers are in (`got` null); in one stream, before the song's head is in - the stream knows
 * whether it was resampled, or kept its hi-res rate, only then (`resampled` and `hiRes` both null).
 * deadwax makes ALL of a resampled song before sending any of it, so on a NAS that is seconds, and
 * it is exactly when Debug is likeliest to be opened: a hi-res song slow to start. Said as not
 * known yet, never as the "No" and the file's own rate the rows would otherwise read.
 */
export function awaitingResample({ track, wrapped, maxRate, format }: Pick<DebugInput, 'track' | 'wrapped' | 'maxRate' | 'format'>): boolean {
  const mine = wrappedFor(wrapped, track)
  if (!mine || mine.resampled || format === null) return false
  const unanswered = mine.got === null || (mine.got === 'stream' && mine.hiRes === null)
  return unanswered && resamples(track, maxRate, format)
}

/**
 * How the song came. describeWrap()'s own words for a song asked for inside an MP4 ("FLAC in MP4",
 * "in one stream", "sent as FLAC, not in an MP4", "asked for FLAC in MP4"), with the depth and rate
 * it was SENT at: 24-bit at the new rate when deadwax resampled it, the file's own otherwise. For
 * any other song, the file as it is, or Navidrome's MP3 transcode.
 */
export function sentAsRow(input: Pick<DebugInput, 'track' | 'wrapped' | 'maxRate' | 'format'>): DebugRow {
  const { track, wrapped, format } = input
  const label = 'Sent as'
  const mine = wrappedFor(wrapped, track)
  if (mine) {
    //? without its rates: they are the Resampled row's, and the tail below
    const words = describeWrap({ ...mine, resampled: null, hiRes: null }, track.id).replace(/^ · /, '').replace(/^sent as /, '')
    //? not answered yet: no depth or rate, since which it will be is what hasn't been said
    if (mine.got === null || awaitingResample(input)) return { label, value: upperFirst(words) }
    const tail = mine.resampled ? depthAndRate(24, mine.resampled.to) : depthAndRate(track.bitDepth, track.sampleRate)
    return { label, value: upperFirst(words) + tail, mono: true }
  }
  if (format === 'mp3') return { label, value: 'MP3, transcoded by Navidrome' }
  if (format === 'raw') {
    const kind = kindOf(track)
    return { label, value: kind ? `${kind}, as the file is` : 'The file as it is' }
  }
  return { label, value: NOT_KNOWN }
}

/** What Resampled says while deadwax hasn't answered. */
export const NOT_KNOWN_YET = 'Not known yet'

/** Whether deadwax resampled the song, from what to what, and how much quieter it made it. */
export function resampledRow(input: Pick<DebugInput, 'track' | 'wrapped' | 'maxRate' | 'format'>): DebugRow {
  const resampled = wrappedFor(input.wrapped, input.track)?.resampled
  if (resampled) {
    return { label: 'Resampled', value: `${khz(resampled.from)} to ${khz(resampled.to)}, ${RESAMPLE_HEADROOM_DB} dB quieter`, mono: true }
  }
  return { label: 'Resampled', value: awaitingResample(input) ? NOT_KNOWN_YET : 'No' }
}

/**
 * Why the song came the way it did: the setting that had it resampled, or the first reason it
 * wasn't. The reasons that hold whatever the setting come first - the rate, the kind, the ratio,
 * the depth: resamples()'s own tests (lib/streamWrap), so the two can't disagree - and the
 * setting after them, since saying "Original" of a 44.1 kHz song would suggest the setting was
 * what kept it as it is.
 */
export function whyRow({ track, wrapped, maxRate, format }: Pick<DebugInput, 'track' | 'wrapped' | 'maxRate' | 'format'>): DebugRow {
  const label = 'Why'
  const mine = wrappedFor(wrapped, track)
  const setting = (rate: MaxRate) => `Maximum quality: ${MAX_RATE_LABELS[rate]}`
  if (mine?.resampled) {
    //? the setting applies from the next song started: this one was asked for under the other
    return { label, value: maxRate === '48000' ? setting('48000') : `Maximum quality was ${MAX_RATE_LABELS['48000']} when this song was asked for` }
  }
  if (format === 'mp3') {
    const kind = kindOf(track)
    return { label, value: `This browser can't play ${kind || 'this file'}, so Navidrome transcodes it to MP3` }
  }
  const rate = track.sampleRate
  if (!(rate > 0)) return { label, value: "Navidrome didn't give its sample rate, so it is sent as it is" }
  if (rate <= 48000) return { label, value: '48 kHz and below is never resampled' }
  if (!isFlac(track)) return { label, value: 'Only FLAC is resampled' }
  if (RESAMPLED_TO[rate] === undefined) return { label, value: `deadwax doesn't resample ${khz(rate)}` }
  if (!(track.bitDepth === 0 || track.bitDepth === 16 || track.bitDepth === 24)) {
    return { label, value: 'deadwax resamples only 16-bit and 24-bit songs' }
  }
  if (maxRate === 'original') return { label, value: setting('original') }
  if (format === null) return { label, value: NOT_KNOWN }
  //? the setting says resample (resamples() agrees, by the rules above) and this song wasn't
  if (!resamples(track, maxRate, format)) return { label, value: NOT_KNOWN }
  if (awaitingResample({ track, wrapped, maxRate, format })) return { label, value: "Asked for resampled; deadwax hasn't answered yet" }
  return { label, value: "Maximum quality changed after this song started, or deadwax sent it as it is (its log says why)" }
}

/** Whether Gapless is on, and whether this song is playing inside a one-stream run. */
export function gaplessRow({ track, wrapped, gapless }: Pick<DebugInput, 'track' | 'wrapped' | 'gapless'>): DebugRow {
  if (!gapless) return { label: 'Gapless', value: 'Off' }
  return { label: 'Gapless', value: wrappedFor(wrapped, track)?.got === 'stream' ? 'On, in one stream' : 'On' }
}

const GAP_PREFIX = 'Last song change '
const GAP_EARLIER = ' · before: '

/**
 * The last song change - describeGaps()'s line, less its opening words - and the ones before it on
 * an "Earlier" line: the last GAPS_KEPT (5) changes in all, newest first.
 */
export function gapRow(gaps: GapReading[]): DebugRow {
  const line = describeGaps(gaps)
  const at = line.indexOf(GAP_EARLIER)
  const last = (at === -1 ? line : line.slice(0, at)).replace(GAP_PREFIX, '')
  return {
    label: 'Gap',
    value: upperFirst(last),
    ...(at === -1 ? {} : { note: `Earlier: ${line.slice(at + GAP_EARLIER.length)}` }),
  }
}

const SEEK_PREFIX = 'Last seek: '

/** The last seek - describeSeek()'s line, less its opening words. */
export function seekRow(lastSeek: SeekReading | null): DebugRow {
  return { label: 'Last seek', value: upperFirst(describeSeek(lastSeek).replace(SEEK_PREFIX, '')) }
}

/** Bytes as the turntable row says them: "3.4 MB". */
function megabytes(bytes: number): string {
  return `${(bytes / 1_000_000).toFixed(1)} MB`
}

/**
 * "Turntable sound" (2.0.0-player.14): whether the turntable's own sound is ready - the window of the
 * song it has, "0:42-1:12, FLAC, decoded at 48 kHz" - or off, and why: the turntable isn't showing; no
 * Web Audio, or nothing to play it on, in this browser; the sound couldn't start (the browser's words);
 * not a FLAC; a window this browser couldn't decode (its words); waiting for a tap to start the sound
 * (an audio context starts only from one); still starting; deadwax not sending a window; its window
 * loading, or none yet. Off, a press on the record is 2.0.0-player.11's: it scrubs silently, the song
 * playing on (2.0.0-player.16 - the deck takes a press only when the record can sound there). This is
 * how an iPhone tells what WebKit made of it. The note says which voice plays it and why (2.0.0-player.16:
 * on the main thread when the page has no AudioWorklet - it isn't on HTTPS - or it wouldn't load), then
 * how far the audio's clock moves at a time (2.0.0-player.24: the audio's own render - about 21 ms on an
 * iPhone - which the deck maps smoothly over; how James's phone renders, read off it), then what windows
 * have cost since the turntable showed - and when, after it showed, the last of them came: the deck
 * reports as things change, not as time passes, so that is the time the bytes are measured to (divide
 * one by the other for a rate).
 */
export function turntableRow(report: DeckReport | null | undefined): DebugRow {
  const label = 'Turntable sound'
  if (!report) return { label, value: "Off: the turntable isn't showing" }
  const voice = report.voice === 'script'
    ? `On the main thread - ${report.voiceWhy ?? 'this browser has no AudioWorklet'}`
    : report.voice === 'worklet' ? 'On its own audio thread (an AudioWorklet)' : undefined
  const step = report.clockStep && report.clockStep > 0 ? `Its clock moves ${(report.clockStep * 1000).toFixed(1)} ms at a time` : undefined
  const cost = report.fetched > 0
    ? `${report.window ? `${megabytes(report.window.bytes)} a window; ` : ''}${megabytes(report.fetched)} fetched since the turntable showed, the last window ${clock(report.lastFetchAt / 1000)} in`
    : undefined
  //? the row's own note first, then which voice, then its clock's step, then the cost
  const withNotes = (row: DebugRow): DebugRow => {
    const note = [row.note, voice, step, cost].filter(Boolean).join(' · ')
    return note ? { ...row, note } : row
  }
  const window = report.window
  const stretch = window ? `${clock(window.start)}-${clock(window.end)}, ${window.kind}, decoded at ${khz(window.decodedAt)}` : ''
  if (report.context === 'unsupported') return { label, value: 'Off: this browser has no Web Audio' }
  if (report.context === 'no-voice') return { label, value: 'Off: this browser has neither an AudioWorklet nor a ScriptProcessorNode to play it' }
  if (report.context === 'failed') return withNotes({ label, value: upperFirst(`off: ${report.problem ?? "the sound couldn't start"}`) })
  if (report.refused) return withNotes({ label, value: `Off: ${report.refused}` })
  if (report.context === 'none') {
    return withNotes({ label, value: 'Off: waiting for a tap to start the sound', ...(window ? { note: `Its window is ready: ${stretch}` } : {}) })
  }
  if (report.context === 'starting') {
    return withNotes({ label, value: 'Off: still starting - a press scrubs silently until it has', ...(window ? { note: `Its window is ready: ${stretch}` } : {}) })
  }
  if (window) return withNotes({ label, value: `Ready: ${stretch}`, mono: true })
  if (report.failed) return withNotes({ label, value: `Off: ${report.failed}` })
  if (report.loading) return withNotes({ label, value: 'Off: its window is loading - a press scrubs silently until it is in' })
  return withNotes({ label, value: 'Off: no window yet - a press scrubs silently; one is fetched while the song plays, or as the record is pressed' })
}

type Answer = Readonly<Record<string, unknown>>

/** The names of the fields an answer carries, sorted as plain strings - the same order on every
 *  device - and only the names: what Navidrome sent, nothing else. */
export function fieldNames(answer: Answer | null | undefined): string[] {
  if (!answer || typeof answer !== 'object') return []
  return Object.keys(answer).sort()
}

/**
 * A value that carries nothing: "", 0, null, an empty list or an empty object - what Navidrome
 * writes for a field it always sends when the file has nothing for it. `false` is a value
 * (isCompilation: false says something), and so is anything inside a list or object.
 */
export function isEmptyValue(value: unknown): boolean {
  if (value === null || value === undefined || value === '' || value === 0) return true
  if (Array.isArray(value)) return value.length === 0
  return typeof value === 'object' && Object.keys(value as object).length === 0
}

/** An answer's field names, those with a value apart from those sent empty - each sorted. */
export function sentFields(answer: Answer | null | undefined): { filled: string[]; empty: string[] } {
  const names = fieldNames(answer)
  const empty = names.filter((name) => isEmptyValue(answer![name]))
  return { filled: names.filter((name) => !empty.includes(name)), empty }
}

function sentRow(label: string, answer: Answer | null): DebugRow {
  if (!answer || typeof answer !== 'object') return { label, value: NOT_KNOWN }
  const { filled, empty } = sentFields(answer)
  if (!filled.length && !empty.length) return { label, value: NOT_KNOWN }
  return {
    label,
    value: filled.length ? filled.join(', ') : 'Nothing with a value',
    mono: true,
    ...(empty.length ? { note: `Empty: ${empty.join(', ')}` } : {}),
  }
}

/**
 * The fields another song of the album carries with a value and this one doesn't - sent empty or
 * left out. Navidrome leaves out a field that is zero or never set, so this is where playCount and
 * played show for a song never played, when one beside it has been.
 */
export function otherSongsFields(song: Answer | null, album: Answer | null): string[] | null {
  const songs = album && Array.isArray(album.song) ? (album.song as unknown[]) : null
  if (!song || !songs) return null
  const mine = new Set(sentFields(song).filled)
  const theirs = new Set<string>()
  for (const other of songs) {
    if (!other || typeof other !== 'object' || other === song) continue
    if ((other as Answer).id !== undefined && (other as Answer).id === song.id) continue
    for (const name of sentFields(other as Answer).filled) if (!mine.has(name)) theirs.add(name)
  }
  return [...theirs].sort()
}

function otherSongsRow(song: Answer | null, album: Answer | null): DebugRow {
  const label = 'On other songs'
  const names = otherSongsFields(song, album)
  if (names === null) return { label, value: NOT_KNOWN }
  return names.length ? { label, value: names.join(', '), mono: true } : { label, value: 'Nothing this song lacks' }
}

/** Info > Debug, top to bottom. */
export function debugSections(input: DebugInput): DebugSection[] {
  return [
    { title: 'The file', rows: [formatRow(input.track)] },
    { title: 'What this device is sent', rows: [sentAsRow(input), resampledRow(input), whyRow(input), gaplessRow(input)] },
    { title: 'Last song change and seek', rows: [gapRow(input.gaps), seekRow(input.lastSeek)] },
    { title: 'The turntable', rows: [turntableRow(input.turntable)] },
    {
      title: 'Navidrome sent',
      rows: [sentRow('Song', input.song), otherSongsRow(input.song, input.album), sentRow('Album', input.album)],
    },
  ]
}
