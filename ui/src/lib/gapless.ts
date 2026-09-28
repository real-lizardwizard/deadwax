/**
 * The gapless switch's decisions: which song the second audio element gets ready, whether a song
 * change can hand over to it or has to go the one-element way, which events of which element
 * count, what goes into memory, and how a song change is timed for the readout.
 *
 * With the switch off none of this runs and the player is the one element it always was (see
 * player/usePlayer.ts). With it on there are two elements: the one playing, and a STANDBY holding
 * the next song, muted, ready to start. When a song ends the standby starts and the two swap
 * roles; when it can't - nothing ready, the wrong song ready, it failed, iOS refused it - the song
 * goes on the element that was playing, exactly as it would with the switch off, so the music
 * never stops because of this mode.
 *
 * Why it is built this way is in CLAUDE.md ("Gapless (experimental)" under the phone player); the
 * short of it, from WebKit's source: iOS unlocks audio per element, and load() in a tap unlocks
 * one for good; a play() from an 'ended' handler is always allowed (a one-second grace); and a
 * paused element on a locked phone may have its buffer thrown away - which is why the next song
 * is held in MEMORY where it fits, not left to the element to keep.
 *
 * Pure, like the rest of lib/, so ui/test/gapless.sim.cjs can hold it to the answers.
 */

import { nextIndex, MEDIA_ERR_ABORTED, afterFailure, type Failure, type FailureAction, type PlayQueue, type QueueTrack } from './playQueue'

/**
 * The largest file held in memory for the next song, in bytes. Two are held at the peak - the
 * song playing and the one after - and a page that uses too much memory on an iPhone is simply
 * reloaded, which stops the music. 64 MiB holds nearly any CD-quality FLAC (about 6.5 MB a
 * minute, so ten minutes) and few hi-res ones; a bigger file is left to the element to buffer
 * as iOS allows, which is what happens to every song with the switch off.
 */
export const MEMORY_MAX_BYTES = 64 * 1024 * 1024

/**
 * How long after a song starts playing its successor starts being got ready, in ms. It lets the
 * song that has just started have the connection to itself for a moment. It also keeps the
 * standby's load() out of the second after a song ends, during which WebKit counts anything done
 * to an element as a tap and marks it as the element last touched - which the lock screen prefers.
 * The standby being MUTED is what actually keeps it off the lock screen (a muted element is never
 * Now Playing); this is the belt to that brace.
 */
export const PRELOAD_DELAY_MS = 3000

/** How many song changes the readout lists. */
export const GAPS_KEPT = 5

/** Where the standby's song comes from: held in memory, or its address, left to the element. */
export type StandbySource = 'memory' | 'stream'

/** The standby element, and the song it holds or is getting. */
export interface Standby {
  /** the queue position it was got ready for, and the song there - both, so a queue changed
   *  under it (a new album, "previous") is noticed rather than handed over to */
  index: number
  id: string
  /** still downloading into memory, or holding a source - from memory, or an address */
  stage: 'fetching' | StandbySource
  /** its element reported an error while it waited */
  failed: boolean
}

export type StandbyPlan =
  | { kind: 'none' }
  | { kind: 'keep' }
  | { kind: 'clear' }
  | { kind: 'load'; index: number; track: QueueTrack }

/**
 * What the standby should hold now: the song after the one playing, when the switch is on and
 * there is one. A standby already holding that song is kept - one that FAILED too, since getting
 * it again would only fail again on every 'playing', and the one-element way deals with a song
 * that won't load when its turn comes. Anything else it holds is cleared.
 *
 * Nothing is got ready while the sound goes to AirPlay (`wireless`): handoverDecision() never
 * hands over there, so a standby would only download or buffer every next song for nothing,
 * beside the stream the speaker is playing - and have Navidrome transcode songs nobody hears.
 */
export function standbyPlan(queue: PlayQueue, enabled: boolean, standby: Standby | null, wireless: boolean): StandbyPlan {
  const index = enabled && !wireless ? nextIndex(queue) : null
  const track = index === null ? null : queue.tracks[index]
  if (index === null || !track) return standby ? { kind: 'clear' } : { kind: 'none' }
  if (standby && standby.index === index && standby.id === track.id) return { kind: 'keep' }
  return { kind: 'load', index, track }
}

/** Why a song change went the one-element way, for the readout. */
export type SameElementReason =
  | 'off'
  | 'paused'
  | 'airplay'
  | 'nothing ready'
  | 'another song ready'
  | 'failed to get ready'
  | 'refused'

/**
 * What a handover starts: the song in memory, the address the standby was already buffering, or -
 * its download into memory not finished - the song's address, given to the standby there and then.
 */
export type HandoverSource = StandbySource | 'unfinished'

export type HandoverDecision =
  | { kind: 'handover'; source: HandoverSource }
  | { kind: 'same element'; reason: SameElementReason }

export interface HandoverQuestion {
  enabled: boolean
  standby: Standby | null
  /** the queue as it will be, and the position being moved to */
  queue: PlayQueue
  index: number
  /** whether the song is to start playing - a song ending, or "next" while playing */
  autoplay: boolean
  /** whether the element playing is sending its sound to an AirPlay device */
  wireless: boolean
}

/**
 * Whether moving to `index` can start the standby, or goes on the element playing.
 *
 * Only a standby holding exactly that song, got ready without an error, hands over. A move that
 * isn't to play (next while paused) stays on the one element - a paused standby handed over would
 * be a second element for nothing. So does anything sent to AirPlay: which element's sound goes
 * to the speaker is iOS's to say, and handing over mid-AirPlay is untested, so AirPlay keeps the
 * one element it has always worked with.
 *
 * A standby still DOWNLOADING exactly that song hands over too, by address ('unfinished'): the
 * download is abandoned and the standby given the song's address to play, as one holding an
 * address would be. That costs what the one-element way costs - one fresh request for the song.
 * Going the one-element way instead would abandon the download, ask for the song again on the
 * element playing, and leave nothing gained.
 */
export function handoverDecision({ enabled, standby, queue, index, autoplay, wireless }: HandoverQuestion): HandoverDecision {
  const same = (reason: SameElementReason): HandoverDecision => ({ kind: 'same element', reason })
  if (!enabled) return same('off')
  if (!autoplay) return same('paused')
  if (wireless) return same('airplay')
  if (!standby) return same('nothing ready')
  const track = queue.tracks[index]
  if (!track || standby.index !== index || standby.id !== track.id) return same('another song ready')
  if (standby.failed) return same('failed to get ready')
  if (standby.stage === 'fetching') return { kind: 'handover', source: 'unfinished' }
  return { kind: 'handover', source: standby.stage }
}

export interface MemoryQuestion {
  /** the answer to the download: its status was 2xx */
  ok: boolean
  contentType: string | null
  /** bytes, from Content-Length; null when it didn't say */
  contentLength: number | null
  /** whether the song was asked for as it is (format=raw) rather than as a transcode */
  raw: boolean
  max?: number
}

/**
 * Whether the next song's download goes into memory, or is abandoned and its address handed to
 * the standby instead. Memory only for a file as it is, that is audio, that says it fits: a
 * transcode's length is Navidrome's estimate and it may end short; and anything that isn't audio
 * is an error page in disguise. A file that doesn't say how big it is goes into memory, counted
 * as it arrives (see overMemoryMax). (Nothing is downloaded at all while AirPlaying - see
 * standbyPlan() - which also means a speaker is never handed a blob: address it can't fetch.)
 */
export function memoryPlan({ ok, contentType, contentLength, raw, max = MEMORY_MAX_BYTES }: MemoryQuestion): StandbySource {
  if (!ok || !raw) return 'stream'
  const type = (contentType ?? '').toLowerCase()
  if (!type.startsWith('audio/') && !type.startsWith('application/ogg')) return 'stream'
  if (contentLength !== null && contentLength > max) return 'stream'
  return 'memory'
}

/** A download read so far past the limit is abandoned for the address. */
export function overMemoryMax(received: number, max: number = MEMORY_MAX_BYTES): boolean {
  return received > max
}

/** What an element's event is for: the player, the standby's own bookkeeping, or nobody. */
export type EventRoute = 'player' | 'standby' | 'availability' | 'ignore'

/**
 * Which element's events count. Everything from the element PLAYING drives the player, as with
 * one element. From the standby, only an error means anything - that its song won't load, so the
 * song change goes the one-element way - and nothing it sends may touch what the player shows or
 * counts: its 'pause', 'durationchange' or 'timeupdate' would otherwise stop the lock screen,
 * shorten the song or count listening nobody did.
 *
 * Whether an AirPlay device is on the network is the exception, from EITHER element: see
 * airplayShown(). It reads like a fact about the network, but WebKit keeps it per element
 * (MediaElementSession::m_hasPlaybackTargets, false until a change is broadcast), an element made
 * after the page started watching for devices - the standby, the moment the switch goes on - is
 * never told the current answer, and a broadcast only reaches an element whose answer changes.
 * Taken from the element playing alone, the standby's stale 'not-available' hid the button once it
 * took over; taken from it alone, a speaker leaving while the standby played was never heard.
 */
export function routeEvent(name: string, fromActive: boolean): EventRoute {
  if (name === 'webkitplaybacktargetavailabilitychanged') return 'availability'
  if (fromActive) return 'player'
  if (name === 'error') return 'standby'
  return 'ignore'
}

/**
 * Whether to show the AirPlay button, from each element's last answer. An element's answer can
 * only be stale one way - every session starts at "none" and every broadcast reaches every session
 * whose answer it changes - so "available" from either is true, and "none" from both is true too.
 */
export function airplayShown(answers: Iterable<boolean>): boolean {
  for (const answer of answers) if (answer) return true
  return false
}

/** The two elements, by number: the first is made with the page, the second by the switch. */
export type ElementSlot = 0 | 1

/** What happens to which element is playing. */
export type RoleEvent =
  /** a song change started the standby: it plays, and the other becomes the standby */
  | 'handover'
  /** the standby wouldn't start: the song goes back to the element that was playing */
  | 'refused'
  /** a song change the one-element way, or anything else on the element playing */
  | 'same element'
  /** the switch turned off: whichever is playing now is the one element from here on */
  | 'switch off'

export function activeAfter(active: ElementSlot, event: RoleEvent): ElementSlot {
  if (event === 'handover' || event === 'refused') return active === 0 ? 1 : 0
  return active
}

export type PlaybackFailureAction = FailureAction | { kind: 'stream' }

/**
 * afterFailure(), for a song that may be playing from memory. One that fails from memory is asked
 * for from Navidrome straight away - the copy in memory is what failed, not the connection, so
 * there is nothing to wait for - and that doesn't use up the song's one retry. Otherwise, and
 * when nobody means it to be playing, afterFailure() decides as it always has.
 */
export function afterPlaybackFailure(failure: Failure & { fromMemory: boolean }): PlaybackFailureAction {
  const { fromMemory, ...rest } = failure
  if (fromMemory && rest.intendsToPlay && rest.code !== MEDIA_ERR_ABORTED) return { kind: 'stream' }
  return afterFailure(rest)
}

/**
 * The longest a song change is timed for, in ms. One that takes longer didn't go straight from a
 * song's end to the next one's sound: the music stopped - a refused play(), a call, a failure at
 * the end of the queue - and something started it again later, and timing that would read as a
 * gap of minutes. Every way the player knows the music stopped already ends the timing (see
 * usePlayer.ts); this is the bound behind them.
 */
export const CHANGE_MAX_MS = 30_000

/** A song change being timed: from the outgoing song's 'ended' until the incoming song's clock runs. */
export interface Change {
  /** performance clock, ms */
  endedAt: number
  how: HandoverDecision
  /** for a handover, the incoming element's readyState when it was started (0 nothing - 4
   *  enough to play through): whether iOS had kept what it buffered; null otherwise */
  readyState: number | null
  /** where the incoming song's clock starts from, in seconds - 0, or where a seek landed */
  from: number
  /** the element that took the song over failed before its clock moved */
  failed: boolean
}

export function startChange(endedAt: number, how: HandoverDecision, readyState: number | null, from = 0): Change {
  return { endedAt, how, readyState, from, failed: false }
}

/** One song change, timed. */
export interface GapReading {
  ms: number
  how: HandoverDecision
  readyState: number | null
  failed: boolean
}

export function gapReading(change: Change, soundAt: number): GapReading {
  const { endedAt, how, readyState, failed } = change
  return { ms: Math.max(0, Math.round(soundAt - endedAt)), how, readyState, failed }
}

/** A 'timeupdate' from the element the song changed to. */
export interface ClockUpdate {
  /** its currentTime, in seconds */
  position: number
  /** when that was read, performance clock ms */
  at: number
  playbackRate: number
  /** whether it sought since the last update: a jump that isn't the clock running */
  seeked: boolean
}

export type ClockStep =
  | { kind: 'wait'; change: Change }
  | { kind: 'reading'; reading: GapReading }
  | { kind: 'stale' }

/**
 * Whether a 'timeupdate' from the incoming element ends the song change being timed.
 *
 * A change ends when the incoming song's media CLOCK is seen running - its position moved past
 * where it started - in both modes. Not at its 'playing' event: WebKit queues 'playing' from inside
 * play() itself for an element that has enough data (HTMLMediaElement::playInternal), before the
 * audio session has admitted it or AVFoundation has made a sound, so a handover would read a few
 * ms however long the silence was - a thrown-away buffer included, which is what the readout is
 * for - while the one-element way's 'playing' waits for the network: two different things, compared.
 *
 * 'timeupdate' comes every 250ms or so, and further apart on a locked phone, so the moment is
 * BACK-DATED by how far the clock has run. A seek moves the position without the clock running,
 * so after one the change waits again from where it landed. A change older than CHANGE_MAX_MS is
 * dropped, clock or no clock.
 */
export function clockStep(change: Change, { position, at, playbackRate, seeked }: ClockUpdate): ClockStep {
  if (at - change.endedAt > CHANGE_MAX_MS) return { kind: 'stale' }
  if (seeked) return { kind: 'wait', change: { ...change, from: position } }
  if (!(position > change.from)) return { kind: 'wait', change }
  const ran = ((position - change.from) / (playbackRate > 0 ? playbackRate : 1)) * 1000
  return { kind: 'reading', reading: gapReading(change, at - ran) }
}

/** The newest reading first, `GAPS_KEPT` at most. */
export function withReading(readings: GapReading[], reading: GapReading): GapReading[] {
  return [reading, ...readings].slice(0, GAPS_KEPT)
}

const SOURCE_WORDS: Record<HandoverSource, string> = {
  memory: 'from memory',
  stream: 'streamed',
  unfinished: 'streamed (download unfinished)',
}

/** How the change was made, in words: "handed over, from memory", "one element (airplay)". */
export function describeHow(reading: GapReading): string {
  const { how, readyState, failed } = reading
  //? the time includes getting over a failure - asking again, or skipping - so it isn't the gap
  const after = failed ? ', failed before playing' : ''
  if (how.kind === 'same element') return `${how.reason === 'off' ? 'one element' : `one element (${how.reason})`}${after}`
  //? HAVE_FUTURE_DATA (3) or better is ready to play; below it the element had to load first
  const ready = readyState !== null && readyState < 3 ? ', had to load' : ''
  return `handed over, ${SOURCE_WORDS[how.source]}${ready}${after}`
}

/** The readout's line: the last change, and the ones before it. */
export function describeGaps(readings: GapReading[]): string {
  const [last, ...earlier] = readings
  if (!last) return 'No song change timed yet'
  const before = earlier.length ? ` · before: ${earlier.map((r) => r.ms).join(', ')} ms` : ''
  return `Last song change ${last.ms} ms, ${describeHow(last)}${before}`
}
