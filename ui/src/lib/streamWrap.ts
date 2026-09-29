/**
 * Whether a song is asked for as FLAC inside an MP4 (`wrap=mp4` on its stream), and what the
 * now-playing readout says about what came back.
 *
 * Safari plays <audio> through AVFoundation, which doesn't land a seek in a FLAC file where it was
 * asked to: seconds off in an ordinary song, whatever the seek table says, while its clock reports
 * the time asked for (see "Seeking" in CLAUDE.md's phone-player section). The very same frames in
 * an MP4 land exactly, so deadwax repackages a FLAC song for it - losslessly, the frames untouched
 * (src/flac_mp4.py, src/player_cache.py). Chromium seeks FLAC exactly and keeps getting the file as
 * it is, which is also what Navidrome sends without deadwax doing anything.
 *
 * So the question is "is this WebKit, and not Chromium". On an iPhone or an iPad every browser is
 * WebKit - Chrome (CriOS) and Firefox (FxiOS) included, since Apple allows no other engine there - and
 * an iPad asking for desktop sites says it is a Mac, which the touch points give away (a Mac has
 * none). Anywhere else, WebKit says AppleWebKit/ and Chromium, which says that too, also says Chrome/.
 * Then only if the browser says it can play FLAC in an MP4 at all.
 *
 * And the one rule for which songs deadwax RESAMPLES (resamples()): with the "Maximum quality"
 * setting at 48 kHz, a hi-res FLAC is asked for with `max_rate=48000`, which deadwax answers with
 * the song resampled to 48 or 44.1 kHz and still lossless FLAC, repackaged - so in an MP4 in every
 * browser, and as fragmented MP4 for the gapless stream. Its addresses, whether it may stream, and
 * the readout all ask this one function, so they can't disagree.
 *
 * Pure, like the rest of lib/, so ui/test/wrap.sim.cjs can hold it to the answers.
 */

import type { QueueTrack } from './playQueue'

/** What the page knows about the browser it is in. */
export interface Browser {
  userAgent: string
  /** navigator.maxTouchPoints - an iPad asking for desktop sites has them, a Mac doesn't */
  maxTouchPoints: number
  canPlayType: (type: string) => string
}

/** What the browser is asked before it is sent one. */
export const FLAC_IN_MP4 = 'audio/mp4; codecs="flac"'

/** WebKit that isn't Chromium: Safari on a Mac, and every browser on an iPhone or iPad. */
export function isAppleWebKit(userAgent: string, maxTouchPoints: number): boolean {
  if (/\b(iPhone|iPad|iPod)\b/.test(userAgent)) return true
  if (/\bMacintosh\b/.test(userAgent) && maxTouchPoints > 1) return true
  //? no \b before Chrome: HeadlessChrome/ is Chromium too
  return /AppleWebKit\//.test(userAgent) && !/(Chrome|Chromium)\//.test(userAgent)
}

/** Whether this page asks for its FLAC songs inside an MP4 - decided once, for the page. */
export function wrapsFlac(browser: Browser): boolean {
  return isAppleWebKit(browser.userAgent, browser.maxTouchPoints) && browser.canPlayType(FLAC_IN_MP4) !== ''
}

/** A FLAC file, by its extension or by the type Navidrome gives it. */
export function isFlac(track: Pick<QueueTrack, 'suffix' | 'contentType'>): boolean {
  const type = (track.contentType ?? '').split(';')[0]!.trim().toLowerCase()
  return track.suffix?.toLowerCase() === 'flac' || type === 'audio/flac' || type === 'audio/x-flac'
}

/**
 * The player's "Maximum quality" setting: '48000' has deadwax resample songs above 48 kHz, 'original'
 * sends every song as it is. Per device, like the gapless switch (readPlayerMaxRate in
 * state/persisted), and 48 kHz unless it says otherwise.
 */
export type MaxRate = '48000' | 'original'
export const DEFAULT_MAX_RATE: MaxRate = '48000'

/**
 * Which rates deadwax resamples, and to what - the same table as the server's (RESAMPLED_TO in
 * src/resample.py). Only whole ratios: 2, 4 or 8 times 44.1 or 48 kHz. Any other rate above 48 kHz is
 * sent as it is, and everything at or below 48 kHz is never touched.
 */
export const RESAMPLED_TO: Readonly<Record<number, number>> = {
  88200: 44100, 176400: 44100, 352800: 44100,
  96000: 48000, 192000: 48000, 384000: 48000,
}

/**
 * Whether deadwax is asked to resample this song: the setting at 48 kHz, a FLAC asked for as it is,
 * a rate from the table, and 16 or 24 bits where Navidrome says - the server can't read the other
 * depths, and sends such a song as it is. A rate or depth Navidrome didn't give (0, or none at all)
 * is unknown, and an unknown rate is not resampled: the song is asked for exactly as it always was.
 */
export function resamples(
  track: Pick<QueueTrack, 'suffix' | 'contentType'> & Partial<Pick<QueueTrack, 'sampleRate' | 'bitDepth'>>,
  cap: MaxRate, format: 'raw' | 'mp3',
): boolean {
  if (cap !== '48000' || format !== 'raw' || !isFlac(track)) return false
  const rate = track.sampleRate ?? 0
  const depth = track.bitDepth ?? 0
  return RESAMPLED_TO[rate] !== undefined && (depth === 0 || depth === 16 || depth === 24)
}

/** What deadwax says it did: `X-Deadwax-Resampled: 192000-48000`. */
export interface Resampled {
  from: number
  to: number
}

/** The header read, or null when there is none, or it says something else. */
export function resampledFrom(header: string | null): Resampled | null {
  const match = /^\s*(\d+)-(\d+)\s*$/.exec(header ?? '')
  if (!match) return null
  const from = Number(match[1])
  const to = Number(match[2])
  return from > 0 && to > 0 ? { from, to } : null
}

/**
 * Whether this song is asked for inside an MP4: a page that wraps, or a song deadwax resamples -
 * which it sends only repackaged, in any browser - a FLAC, and the file as it is. A transcode is
 * produced as it plays, and there is no FLAC in it to repackage.
 */
export function asksForMp4(
  track: Pick<QueueTrack, 'suffix' | 'contentType'>, format: 'raw' | 'mp3', pageWraps: boolean, resampled = false,
): boolean {
  return (pageWraps || resampled) && format === 'raw' && isFlac(track)
}

/**
 * What came back for the song playing when it was asked for inside an MP4: `mp4` it was, `flac`
 * deadwax sent the FLAC as it is instead (a file it wouldn't repackage - its log says why), null
 * not known yet. Null altogether for a song not asked for that way. `stream` is a song playing
 * inside a one-stream run (lib/streamPlan.ts): fragmented MP4 appended to a MediaSource, which is
 * known the moment it plays, so there is nothing to ask. `resampled` is what deadwax's answer said
 * it did to a hi-res song, null when it didn't (or hasn't said yet). `hiRes` is the rate of a song
 * playing in a stream above 48 kHz as it is - under "Original" - so the readout can show the rate
 * was kept; null for every other song.
 */
export interface Wrapped {
  id: string
  got: 'mp4' | 'flac' | 'stream' | null
  resampled: Resampled | null
  hiRes: number | null
}

/** What an answer's Content-Type says came back. */
export function wrappedAs(contentType: string | null): 'mp4' | 'flac' {
  return (contentType ?? '').split(';')[0]!.trim().toLowerCase() === 'audio/mp4' ? 'mp4' : 'flac'
}

/** A rate as the readout says it: 192 kHz, 44.1 kHz. */
function khz(rate: number): string {
  return `${rate / 1000} kHz`
}

/**
 * The end of the readout's "Last seek" line: how the song playing came, so the phone can show it
 * was sent as an MP4 - which is what makes a seek land there - and when deadwax resampled it, from
 * what to what, or the rate a hi-res song kept in a stream. Nothing for a song that wasn't asked for
 * that way (every song in Chromium but a resampled or streaming one), or for another song than
 * `trackId`.
 */
export function describeWrap(wrapped: Wrapped | null, trackId: string | null): string {
  if (!wrapped || wrapped.id !== trackId) return ''
  const rate = wrapped.resampled
    ? `, ${khz(wrapped.resampled.from)} resampled to ${khz(wrapped.resampled.to)}`
    : wrapped.hiRes ? `, ${khz(wrapped.hiRes)}` : ''
  if (wrapped.got === 'mp4') return ` · FLAC in MP4${rate}`
  if (wrapped.got === 'flac') return ' · sent as FLAC, not in an MP4'
  if (wrapped.got === 'stream') return ` · in one stream${rate}`
  return ' · asked for FLAC in MP4'
}
