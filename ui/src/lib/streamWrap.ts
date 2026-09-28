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
 * Whether this song is asked for inside an MP4: a page that wraps, a FLAC, and the file as it is -
 * a transcode is produced as it plays, and there is no FLAC in it to repackage.
 */
export function asksForMp4(
  track: Pick<QueueTrack, 'suffix' | 'contentType'>, format: 'raw' | 'mp3', pageWraps: boolean,
): boolean {
  return pageWraps && format === 'raw' && isFlac(track)
}

/**
 * What came back for the song playing when it was asked for inside an MP4: `mp4` it was, `flac`
 * deadwax sent the FLAC as it is instead (a file it wouldn't repackage - its log says why), null
 * not known yet. Null altogether for a song not asked for that way.
 */
export interface Wrapped {
  id: string
  got: 'mp4' | 'flac' | null
}

/** What an answer's Content-Type says came back. */
export function wrappedAs(contentType: string | null): 'mp4' | 'flac' {
  return (contentType ?? '').split(';')[0]!.trim().toLowerCase() === 'audio/mp4' ? 'mp4' : 'flac'
}

/**
 * The end of the readout's "Last seek" line: how the song playing came, so the phone can show it
 * was sent as an MP4 - which is what makes a seek land there. Nothing for a song that wasn't asked
 * for that way (every song in Chromium), or for another song than `trackId`.
 */
export function describeWrap(wrapped: Wrapped | null, trackId: string | null): string {
  if (!wrapped || wrapped.id !== trackId) return ''
  if (wrapped.got === 'mp4') return ' · FLAC in MP4'
  if (wrapped.got === 'flac') return ' · sent as FLAC, not in an MP4'
  return ' · asked for FLAC in MP4'
}
