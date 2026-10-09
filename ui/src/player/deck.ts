/**
 * The turntable's deck (2.0.0-player.14): the platter's movement - momentum, the motor, spin-up and
 * spin-down - and the record's own sound, which follows it. player/Turntable.tsx owns one while it
 * shows, and tells it what the hand does; this does the rest. James: "can we add momentum to the disc
 * as well?", then "And the audio will speed up and slow down with it?"
 *
 * THE SOUND IS A SEPARATE PATH. The player's audio element is never connected to Web Audio, and never
 * touched here: a createMediaElementSource is what breaks locked playback on an iPhone, and normal
 * playback must stay exactly what it was. The record's sound is a stretch of the song round the
 * playhead - a FLAC window deadwax cuts (src/flac_window.py), decoded by decodeAudioData - read by
 * lib/deckVoice.ts's voice on an AudioContext of its own, only for the moments the record is not playing
 * at its own speed: under the hand, coasting after a flick, winding down on a pause. The voice runs in
 * an AudioWorklet where the page can have one, and on the main thread in a ScriptProcessorNode where it
 * can't (a page that isn't on HTTPS - `Voice`, 2.0.0-player.16). The
 * player's own song is moved only through the player's own actions - the host's `hold` and `resume`
 * (which Turntable makes player.toggle() calls of) and the seeks Turntable makes of what this returns.
 *
 * THE AUDIO CONTEXT is made or resumed only in an activating gesture - a click, a pointerup, a keyup:
 * the record's tap and release, the look button, the transport buttons, opening the screen
 * (wakeDeckAudio(), resumeDeckAudio()) - never a pointerdown, which WebKit doesn't count. Until it runs,
 * a voice is ready and a window covering the record is in it, a press scrubs silently as
 * 2.0.0-player.11's did (`live()` false: Turntable takes that path, and the record stops under the
 * finger - `holdStill`) - all but a press on a record the deck has coasting, which it catches whenever a
 * voice is ready, the song paused by the flick already. It is suspended when the screen closes or the
 * page is hidden - nothing of it runs on a locked phone, a hide while a tap's resume is still settling
 * included - and closed when the turntable goes. While it lives the page's audio session
 * is 'playback' (iOS's silent switch would mute it otherwise), put back as the turntable goes.
 *
 * WHAT THE HAND DOES (live):
 *  - A press on a playing record lets the song play on for a moment: a tap is a tap (play/pause, from
 *    the click). The record is TAKEN as the press moves past the tap's few pixels, or rests longer than
 *    a tap (HOLD_MS): then the song pauses (`hold`) and the record's sound takes over at the song's
 *    position, at its own speed if it was playing, and follows the hand from there - silent while the
 *    finger rests. A press on a coasting record takes it at once. Since 2.0.0-player.40 a press taken by
 *    moving (a QUICK GRAB) is taken from the press itself: the deck keeps the samples inside the slop
 *    (`touched`), and the take is stamped at the press's moment, the record where it was then, with every
 *    sample since after it - so the voice, HAND_DELAY_S behind, plays the hand from when the finger went down
 *    (TAKE_BACK_S, takeOver: no further back than the voice can still be told of), and the face carries on
 *    from where it was drawn as the slop was crossed.
 *  - THE SOUND FOLLOWS THE HAND'S OWN SAMPLES (2.0.0-player.24): each pointer sample goes to the voice as
 *    it comes (`hand`), with the time the event gives it - each of a move's coalesced events too - never
 *    one drive a frame; the voice plays the path through them HAND_DELAY_S behind (lib/deckVoice). Every
 *    time it is told - a sample's, a take's, each frame's place on a coast, a wind-down or the motor's
 *    run, the handover's - is the page's clock mapped onto the audio context's by ONE smooth mapping
 *    (lib/deckClock), never a `currentTime` read for the message: its steps (the audio's own render, 21
 *    ms on an iPhone) were what made James's "it doesn't sound like anything". It is read every frame
 *    while anything moves, at every stamp, and on a timer of its own while the turntable shows and the
 *    context runs, whatever the record does (`keepClock`: every CLOCK_SETTLE_MS while the mapping
 *    settles, every CLOCK_TICK_MS after) - so the first grab of a paused record, which runs no frames,
 *    finds it settled - and held steady through a gesture, whatever it reads meanwhile.
 *  - Let go, the hand's speed over its last ~90 ms - up to its last sample, by the samples' own times, so
 *    the frame or so between the last move and the lift isn't read as slowing (releaseSpeed) - becomes
 *    the platter's (lib/platter), and the plan carries on from that sample's own moment and place, the
 *    hand still moving through those few ms (a lift after a longer rest starts it at the lift). A
 *    frame begun before what the voice was last told drives nothing (`stampedTo`). A song that was
 *    playing: the motor takes the platter back to speed - stopping it first, from a backwards flick -
 *    and the song is sought AT THE RELEASE to where the platter will be at speed (the physics is exact,
 *    so that is known then, and the element has the whole coast to buffer); at speed the song plays
 *    (`resume`, after the tap - iOS allows it on an element a tap started; if it refuses, the player's
 *    own "Tap play to start" says so, and the platter spins down rather than turning beside a paused
 *    song), and the record's sound holds the song's own speed until the song is really playing, then fades out
 *    (HANDOVER_FADE_S). A song that was paused: the platter coasts to a stop under friction, and the
 *    song is sought at the release to where it will stop, and stays paused. Either way the window is
 *    asked for over the whole of where the platter will go, at the release (`keepPath`).
 *  - A cancel drops it all and seeks nowhere - a song it paused plays on from where it was. A song
 *    change drops it all - and a song the hand had taken from playing plays on (the next one, after
 *    Next mid-coast), as does one whose turntable goes mid-coast (the look switched): the hand only
 *    scrubbed it. The arm, or a seek made by anything else meanwhile (Previous restarting the song, a
 *    key on the arm), stops the record's sound and showing where it is (`quiet`): the song is where
 *    that put it, and a coast back to speed still plays it from there.
 *  - Pause on the turntable (the record's tap, the transport's pause, on this look) with "Pause winds
 *    the record down" on: the song pauses in the tap as ever, and the record's sound starts there at
 *    the song's own speed and winds down with the platter over SPIN_DOWN_S (`pausing`), the song sought
 *    to where it stops - when the window covers it; otherwise a plain pause, never a wait.
 *  - Play: the platter spins up over SPIN_UP_S; the song itself starts as it always has - from where
 *    the record is (`resuming`) when it was coasting or winding down with its sound, so nothing heard
 *    is skipped.
 *
 * THE PLATTER is turned frame by frame (requestAnimationFrame) while anything moves and the turntable
 * shows - stopped when still, hidden or closed. Under Reduce Motion it doesn't turn at all, a release
 * lands at once (a playing song plays from there in the release's own gesture), and nothing winds down.
 *
 * THE SPEED FADER (2.0.0-player.39): the player's speed is the motor's. The platter turns at it - 1.5x
 * is 50 rpm - a hand takes a playing record at it, the motor brings a let-go record back to it (lib/
 * platter's motor with a `target`), the handover holds it until the song plays, a pause winds down from
 * it and a spin-up runs to it. Turntable says when it changes (`speedChanged`); the record's sound needs
 * nothing new - it reads at whatever rate the platter is driven at.
 *
 * THE WINDOW is kept ready while the turntable shows and the song plays - once a tap has started the
 * sound, so there is something to decode it with and play it on: WINDOW_S of it, from a little before
 * the playhead, asked again as the playhead nears its end, and on demand when a hand or a coast goes
 * outside it. One is on its way at a time, from the ask until it is in the voice (`pending`), so
 * nothing asks for it again meanwhile. A hi-res song's windows come back shorter (deadwax's budget), and
 * the margins shrink with them (windowMargins), so each still moves on by most of its length. Its cost
 * - bytes fetched since the turntable showed - is in Info > Debug.
 */

import { isAbort, latestOnly } from '../lib/latest'
import { clockReading, clockSettled, contextTimeAt, newDeckClock, resetDeckClock } from '../lib/deckClock'
import {
  HAND_DELAY_S, REPORTS_PER_SECOND, VOICE_CEILING, VOICE_LOOKAHEAD_S, VOICE_PROCESSOR, newVoiceState, renderVoice, voiceCommand, voiceReport, voiceWorkletSource,
  type DeckHealth, type DeckLatency, type DeckReport, type VoiceHeard, type VoiceMessage,
} from '../lib/deckVoice'
import {
  DEGREES_PER_SECOND, RELEASE_TAIL_MS, VELOCITY_WINDOW_MS, acceleration, coast, degreesFor, motor, phaseAt, planAt, releaseSpeed, voiceRate,
  type HandSample, type Plan,
} from '../lib/platter'
import { ApiError } from '../api/http'
import { scrubWindow, type ScrubWindow } from './api'

/** A press resting longer than a tap takes the record (and pauses a playing song), in ms. */
export const HOLD_MS = 250
/**
 * A quick grab - a press that moves past a tap's few pixels, not one that rests - is taken FROM THE PRESS
 * (2.0.0-player.40): stamped at the press's own moment, with the record where it was then, and every sample
 * of the hand since handed to the voice, which plays HAND_DELAY_S behind - so a press that turns at once is
 * heard from when the finger went down, not from when it had travelled the slop (35 ms at 1x, about 70 at
 * 0.5x, 94 at 0.25x: that much sooner). The voice can still be told of a moment up to this long before the
 * page tells it, in seconds: on the worklet HAND_DELAY_S less 20 ms for the message's delivery - it applies one
 * up to 9 ms after its moment by the page's clock (the delay-chain research) - and the clock's mapping; on the
 * main thread HAND_DELAY_S less 5 ms for the mapping alone (SCRIPT_TAKE_BACK_S), since its lag holds what it
 * is told two blocks on, and the block a message waits for plays no more than two blocks after it is posted.
 * A press older than that - counted from when the page hears of the move - is taken from its oldest sample that
 * isn't: a still record at the hand's place then, a moving one (a playing song, a coast) where it had got to on
 * its own by then, so a slower start keeps that much of the slop's delay.
 */
export const TAKE_BACK_S = HAND_DELAY_S - 0.02
export const SCRIPT_TAKE_BACK_S = HAND_DELAY_S - 0.005
/** How much of the song a window holds, how far before the playhead it starts, on what grid. A
 *  window is asked again whole, so what that costs over the song's own stream is WINDOW_S over the
 *  stretch the playhead crosses before the next (WINDOW_S - WINDOW_BACK_S - REFRESH_AHEAD_S): 40 over
 *  30, a third more than the song itself while the turntable shows and the song plays. */
export const WINDOW_S = 40
export const WINDOW_BACK_S = 4
export const WINDOW_GRID_S = 2
/** The window is asked again once the playhead is this close to its end, in seconds of listening: of
 *  the song at 1x and slower, and that times the speed faster than 1x (2.0.0-player.39 - see keep()). */
export const REFRESH_AHEAD_S = 6
/** Asked again ahead of a playhead the window still covers no more often than this, in ms - a floor
 *  under the refresh, whatever length of window deadwax sends. */
export const REFRESH_MIN_MS = 3000
/** A window that couldn't be had is asked again after this long, in ms. */
export const RETRY_MS = 10_000
/** How long one frame's drive holds past its own time, in seconds: a drive that stops coming runs out
 *  by itself. */
export const DRIVE_FOR_S = 0.12
/** The audio's clock read on the deck's own timer (keepClock), in ms: this often while its mapping is
 *  young (lib/deckClock's clockSettled - just after the context is made or resumed, its every state change
 *  starting the mapping again), CLOCK_TICK_MS once it has settled - while the turntable shows and the
 *  context runs, whatever the record does. Frames read it too, but only while something moves: a paused
 *  record runs none, so the first grab of one after its context was made or resumed was stamped by a
 *  mapping nothing had read since (second review of 2.0.0-player.24 - up to a step's jump in its first
 *  readings). Ten readings a second keep it settled and never stale (an audio clock drifting from the
 *  page's is followed), for the cost of a timer. Quick only for the first CLOCK_SETTLE_TICKS readings
 *  after the timer starts afresh (the turntable shown, the context's state changed): a clock that
 *  doesn't move (a context said to run that renders nothing) is then read slowly, not 67 times a second
 *  for nothing. */
export const CLOCK_SETTLE_MS = 15
export const CLOCK_SETTLE_TICKS = 40
export const CLOCK_TICK_MS = 100
/** The handover: the record's sound holds the song's speed for at most this long waiting for the song to play,
 *  then fades out over HANDOVER_FADE_S. A play that hasn't started by then was refused, and the
 *  platter spins down. */
export const HANDOVER_MAX_S = 3
export const HANDOVER_FADE_S = 0.04
/** A frame that came this long after the one before, while a hand holds the record, is counted late in
 *  Debug: more than two frames of a 60 Hz screen. */
export const SLOW_FRAME_MS = 34
/** A coast back to speed this short plays the song in the release's own gesture, in seconds. */
export const RESUME_IN_GESTURE_S = 0.05
/** A pause the turntable didn't ask for (a song ending, the lock screen) spins the platter down only
 *  if it lasts this long, in ms - a song change pauses for a moment, and a deck's motor doesn't stop
 *  between tracks. */
export const PAUSE_SETTLE_MS = 300
/** A song changed under a hand that had taken it from playing (Next mid-coast) is played this long
 *  after, in ms, if nothing has played it meanwhile - so a song started some other way in that moment
 *  (a tap in Search, its own play already under way) is never toggled back off: the player's playing
 *  state follows its element's 'play' a moment after the play itself. */
export const SONG_CHANGE_SETTLE_MS = 300
/** What the voice last said is believed for this long, in ms, extrapolated by its rate. */
export const HEARD_FRESH_MS = 120
/** What the voice's limiter held after the deck last reported - the counts for a hold's last moments
 *  and a coast's, which the voice plays HAND_DELAY_S behind the hand - is reported once the deck no
 *  longer steers the sound, no more often than this, in ms (review of 2.0.0-player.35). */
export const HEALTH_REPORT_MS = 250
/** The song found this far from where the deck had it sought, in seconds, was sought there by
 *  something else - Previous restarting it, a key on the arm - and the record's sound has nothing to
 *  follow. Further than any wind-down travels from where the song paused (0.3 s). */
export const SOUGHT_ELSEWHERE_S = 0.75

/** What the deck needs to know of the song playing. */
export interface DeckSong {
  id: string
  /** seconds; 0 when not known */
  length: number
  /** whether it is a FLAC - only a FLAC has the record's sound */
  flac: boolean
  /** its kind in capitals, for Debug: FLAC, MP3 */
  kind: string
  /** the cap the player asks for this song at - 48000 for a hi-res song under "Up to 48 kHz", null
   *  for the song as it is - so the window is cut from the very copy the song plays from: its rate,
   *  its level */
  maxRate?: number | null
}

/**
 * What the deck asks of the turntable. `hold` and `resume` are the player's toggle, made in
 * Turntable.tsx (ui/test/app-rules.sim.cjs pins which of its functions call it): pause the song as the
 * hand takes the record, play it as the motor has it back at speed - or as a press the deck can't take
 * catches that run back to speed (holdStill).
 */
export interface DeckHost {
  song(): DeckSong | null
  playing(): boolean
  /** the song's position as the player has it, seconds */
  position(): number
  onPosition(listener: (seconds: number) => void): () => void
  hold(): void
  resume(): void
  /** the face's angle, degrees: written straight onto it, never a render */
  turnFace(degrees: number): void
  /** what the time line and the arm show while the deck has the record: a time - `scrubbing` while a
   *  hand or a flick moves it - or null for the song's own */
  show(at: number | null, scrubbing: boolean): void
  /** the press took the record: the click after it is not a tap */
  grabbed(): void
  /**
   * Where the song's windows come from instead of deadwax (2.0.0-player.36, the test bench at
   * /player/lab/): `seconds` of the song from `from`, in the shape scrubWindow answers - bytes the
   * browser decodes, the first sample's number, how many, at what rate. The app gives none, and its
   * windows are deadwax's (scrubWindow), exactly as before.
   */
  window?(song: DeckSong, from: number, seconds: number, signal: AbortSignal | undefined): Promise<ScrubWindow>
}

/** What a release asks Turntable to do, in the release's own handler: seek, and play at once. */
export interface Released {
  seek: number | null
  play: boolean
}

/**
 * How far behind the playhead a window starts and how near its end the playhead comes before the next
 * is asked, for windows of `span` seconds: WINDOW_BACK_S and REFRESH_AHEAD_S for a whole one, and in
 * proportion for one deadwax cut short (a hi-res song's, at WINDOW_MAX_BYTES) - so each new window
 * still moves on by about three quarters of its length, rather than re-fetching what it had. Faster than
 * 1x (2.0.0-player.39) keep() asks that much earlier - `ahead` times the speed, the same time to fetch
 * and decode in - so at 2x a window moves on by 24 s of its 40, not 30, and costs 40/24 of the song.
 */
export function windowMargins(span: number): { back: number; ahead: number } {
  const scale = Math.max(0, Math.min(1, span / WINDOW_S))
  return { back: WINDOW_BACK_S * scale, ahead: REFRESH_AHEAD_S * scale }
}

type Role = 'coast' | 'handover' | 'winddown' | 'spin'

interface PlanMotion {
  kind: 'plan'
  role: Role
  plan: Plan
  since: number
  from: number
  x0: number
  sounding: boolean
  /** where the song was sought for it - the plan's end, or where a silent wind-down paused it - which
   *  a position anywhere else says something else moved it */
  sought: number
  /** the arm took it, or something else sought the song meanwhile: no sound, nothing shown, for the
   *  rest of it */
  quiet: boolean
}

type Motion =
  | { kind: 'still' }
  | { kind: 'turning'; since: number; from: number }
  | { kind: 'hand' }
  | PlanMotion

interface Press {
  taken: boolean
  /** the song's position the record was taken at, seconds - for a quick grab, where it was at the press
   *  (2.0.0-player.40): what the hand's turn since the press counts from */
  anchor: number
  /** where the hand has the record now, seconds */
  at: number
  intent: 'play' | 'pause'
  samples: HandSample[]
  /** when it went down (page ms, its event's own time) */
  since: number
  /** the hand's samples inside a tap's few pixels, before the record is taken (touched): when, how far it had
   *  turned since the press, and how far that moves the song (seconds) - a quick grab hands them on */
  early: { time: number; turned: number; offset: number }[]
}

/* ===== the audio context, one for the page, made only in a gesture ===== */

/**
 * What plays the record's sound (2.0.0-player.16) - lib/deckVoice.ts's functions, on one of two hosts:
 * an AudioWorklet, on an audio thread of its own, wherever the page can have one; or a
 * ScriptProcessorNode on the page's main thread where it can't. AudioWorklet is a SecureContext API -
 * a browser gives it only to a page on HTTPS or localhost - and deadwax is often opened at a plain
 * http:// address on a home network (James's iPhone and Mac: "the audio doesn't follow the turntable
 * when scrubbing"). ScriptProcessorNode is deprecated but in every current browser, iOS Safari too, and
 * needs no secure page. `ready` once it can sound: the worklet as its node is made, the script voice
 * once it has played its first block - a browser that never calls it stays not ready, and a press stays
 * 2.0.0-player.11's rather than pausing the song over silence.
 */
interface Voice {
  kind: 'worklet' | 'script'
  ready: boolean
  post(message: VoiceMessage, transfer: Transferable[]): void
  disconnect(): void
}

interface DeckAudio {
  context: AudioContext | null
  voice: Voice | null
  /** the voice's own node, for a recording to tap (recordDeckSound) */
  node: AudioNode | null
  loading: boolean
  problem: string | null
  missing: 'unsupported' | 'no-voice' | null
  /** why the script voice plays it, not the worklet - for Debug */
  why: string | null
  /** how many frames the voice renders at a time (2.0.0-player.40): the main-thread voice's block, the
   *  worklet's render quantum (128) - for Debug and the recorder */
  block: number | null
}

const audio: DeckAudio = { context: null, voice: null, node: null, loading: false, problem: null, missing: null, why: null, block: null }
//? the page's clock mapped onto the context's (lib/deckClock, 2.0.0-player.24): everything the voice
//? steers by is stamped through it - started again for each context, and as its clock stops and starts
const clock = newDeckClock()
let moduleUrl: string | null = null
const audioListeners = new Set<() => void>()
let heardListener: ((heard: VoiceHeard) => void) | null = null
//? the page's audio session kind before the deck set it to 'playback', while the deck lives; null when
//? the deck hasn't set it
let sessionBefore: string | null = null
//? how the sound is keeping up, counted for Info > Debug's "Turntable timing" (2.0.0-player.28): the
//? main-thread voice's blocks asked for after they were due, and the context's interruptions - and
//? (2.0.0-player.35) the peaks the voice's limiter held under the ceiling: how many runs of samples, how
//? many samples, and the deepest it turned the sound down, dB
const soundHealth = { blocks: 0, lateBlocks: 0, worstBlockMs: 0, interruptions: 0, peaksHeld: 0, samplesHeld: 0, deepestHoldDb: 0 }
//? the lowest limiter gain the health takes as it is: 120 dB down - anything lower (a gain of 0, which the
//? voice floors at) is said as that
const DEEPEST_GAIN_SAID = 1e-6
//? the limiter's counts have moved since the deck last reported (review of 2.0.0-player.35): the voice
//? plays the hand's path HAND_DELAY_S behind (and the script lag more, on the main thread), so what it
//? held over a hold's last moments - and over a whole coast - comes in after the report the hold's end
//? makes, and a paused record has no later report of its own: the deck reports again once it has
//? stopped steering the sound (onHeard). Only the limiter's counts: a late block is the page being busy,
//? and a report re-renders the page - reporting for it could make more of them
let healthMoved = false
//? the turntable was hidden while its context was still starting or resuming (a tap's, and the page
//? hidden before it settled): suspended as soon as it runs, since nothing else would - a gesture asking
//? for the sound, or the turntable showing again, lets that go (review of 2.0.0-player.16)
let sleepOnceRunning = false

/**
 * The main-thread voice's block, in samples (2.0.0-player.40): SCRIPT_BUFFER_SMALL where the hardware renders
 * that many frames or fewer at a time, SCRIPT_BUFFER everywhere else - and wherever that can't be told
 * (scriptBlockFor). A message waits for the next block and is heard SCRIPT_LAG_BLOCKS blocks on, so the block
 * is in the record's sound's delay twice over: 512 is 21 ms less than 1024 at 48 kHz - 142.8 ms from the hand
 * to the sound in all where 1024 gives 164.2 (120 + 2 blocks + the limiter's 1.5). Smaller only where the
 * hardware asks for no more than one block at a time: where it renders 1024 frames at once, it asks for two
 * blocks of 512 together, both stamped alike, and the second plays a block before its stamp says (measured
 * with a known impulse: 512 frames early) - and 256 would save 10 ms more for blocks played twice under a load
 * that 512 and 1024 kept up with (the delay-blocks research, 2026-10-08).
 */
export const SCRIPT_BUFFER = 1024
export const SCRIPT_BUFFER_SMALL = 512
/** How many of its blocks after it is said the main-thread voice hears a take or a drive: a message
 *  waits up to one block for the next to be asked for, which plays a block after it is asked - 43 ms
 *  at 48 kHz in blocks of 1024 (21 in blocks of 512), a constant lag on the record's sound and nothing more
 *  (startScript). */
export const SCRIPT_LAG_BLOCKS = 2
/**
 * Blocks sharing one playbackTime (2.0.0-player.40): the browser asked for two blocks together. Now and then
 * that is the page late, or a stall's burst (below); but where SCRIPT_SHARED_OF of the last
 * SCRIPT_SHARED_WINDOW blocks were (a pair, or a run, counted once), the hardware renders more than one block
 * at a time - or the page can't keep up with blocks that short - and a voice in blocks of SCRIPT_BUFFER_SMALL
 * changes to SCRIPT_BUFFER at its next silent moment, and keeps it on this page. Not counted for the first
 * SCRIPT_SHARED_AFTER blocks: a context's first blocks come unevenly. And a small block written after it began
 * to play where the voice sounds (SCRIPT_HEARD_LEVEL) - the page can't keep up with blocks that short, and
 * the block two before it was heard again in its place - changes it the same way: a block of 512 has half the
 * room a block of 1024 has for whatever else the page does (in headless Chromium the work of a let-go did
 * it, 2 flicks in 5; never in blocks of 1024).
 */
export const SCRIPT_SHARED_OF = 8
export const SCRIPT_SHARED_WINDOW = 32
export const SCRIPT_SHARED_AFTER = 16
/** A block late counts against blocks of 512 only where it, or one of the two before it - the one played again
 *  in its place - is louder than this (-80 dBFS): a late block over a record held still is heard by no one. */
export const SCRIPT_HEARD_LEVEL = 1e-4
/**
 * The main-thread voice's clock is COUNTED (2.0.0-player.31): each block one block after the one before,
 * anchored on the first block's `playbackTime` - not read from each block's. WebKit stamps a block's
 * playbackTime on the MAIN thread, from the hardware clock as of whenever the main thread got to it,
 * quantised to the hardware buffer, so from block to block the stamp jitters by up to a buffer (21 ms on
 * an iPhone) - and a voice reading its path by it warbled at the block rate (James, with no block late:
 * "that digital buzz sound when scrubbing"; the lab's Chromium stamps exactly, so it never showed). Since
 * 2.0.0-player.40 its constants are in SECONDS, so they mean the same at any block size (countBlock):
 *  - SCRIPT_STAMP_TOLERANCE_S: a stamp within this of the count is the count - an exact clock (Chromium's),
 *    followed as it is.
 *  - SCRIPT_SLEW_PER_S and SCRIPT_DRIFT_EASE_S: a stamp a step away (WebKit's jitter, or the page late with
 *    one block) leaves the count holding, eased toward the stamps' lower edge - down at once to a stamp
 *    earlier than the count, up over about SCRIPT_DRIFT_EASE_S (until .40: toward their running mean, which a
 *    page late now and then eased AHEAD of the truth) - by at most SCRIPT_SLEW_PER_S a second: 0.02 ms a block
 *    of 1024 at 48 kHz, as it was - a hundredth of the step the ear could find.
 *  - SCRIPT_REANCHOR_S (64 ms: 3 blocks of 1024 at 48 kHz, as it was): a stamp this far EARLIER than the count
 *    anchors it again - at once where it is later than the stamp before; one no later than the stamp before (as
 *    it is while the count agrees with the stamps, a block being shorter than this) is first counted on as a
 *    burst's, below, and anchored at the next callback. One this far LATER is blocks the page was never asked
 *    for - WebKit drops them
 *    while the page is busy, and the hardware plays on without them - or only the page late with this one,
 *    or the first of a burst: the count goes on until the callbacks are evenly spaced again - two in a row,
 *    each stamp one block after the one before, to SCRIPT_STAMP_TOLERANCE_S (one alone came in a page late
 *    block after block, the research's 6x runs) - and is anchored then only if every stamp since stayed that
 *    far later, by the least of them: a stamp can be late, never early. So a drop is anchored two callbacks
 *    after its jump (until .40, at the jump itself), the count unproven again after it (SCRIPT_PROVE_S).
 *  - A BURST: a stamp no later than the one before. After a stall Chromium runs the callbacks queued meanwhile
 *    back to back, every one stamped alike - and each is the next block (the k-th callback is the k-th block,
 *    over every recording the research made), so the count goes on through them as it is. Until .40 the
 *    stall's stamp anchored the count and each callback of the burst then added a block, so it ran up to 3
 *    blocks (64 ms) AHEAD of the real playbackTime, eased back at 0.02 ms a block - for up to a minute, the
 *    delay and the hand's fit's look-ahead that much shorter (6 of 10 plain-http bench recordings).
 *  - SCRIPT_PROVE_S: a count not yet seen to agree with a stamp - the first, or one moved forward - is set back
 *    to any stamp earlier than it for this long (a first block asked for late anchored it late).
 */
export const SCRIPT_STAMP_TOLERANCE_S = 0.001
export const SCRIPT_REANCHOR_S = 0.064
export const SCRIPT_SLEW_PER_S = 0.0009375
export const SCRIPT_DRIFT_EASE_S = 1.0666666666666667
export const SCRIPT_PROVE_S = 1

/** Whether the page runs on Apple's engine, WebKit - every browser on an iPhone, and Safari on a Mac:
 *  `navigator.vendor` is "Apple Computer, Inc." there, or the old prefixed `webkitAudioContext` is still
 *  given (Chromium and Firefox give neither). */
export function isAppleEngine(): boolean {
  try {
    const scope = globalThis as { navigator?: { vendor?: unknown }; webkitAudioContext?: unknown }
    return scope.navigator?.vendor === 'Apple Computer, Inc.' || typeof scope.webkitAudioContext === 'function'
  } catch {
    return false
  }
}

/** The block the main-thread voice starts with on a context (2.0.0-player.40): SCRIPT_BUFFER_SMALL where the
 *  context says its hardware renders that many frames or fewer at a time - `baseLatency` times the rate, which
 *  in Chromium is exactly the hardware's 128, 512 or 1024 - and SCRIPT_BUFFER where it says more, or nothing
 *  (no baseLatency, or 0). Within 2% of 512 counts as 512 (a rate that doesn't divide it evenly).
 *  On WebKit (`apple`, isAppleEngine) always SCRIPT_BUFFER: its baseLatency is its render quantum, 128 frames
 *  whatever buffer the hardware runs (AudioDestinationResampler::framesPerBuffer() is its render bus's
 *  length), so it can't tell - and a voice that can't tell keeps 1024. */
export function scriptBlockFor(context: { baseLatency?: number; sampleRate: number }, apple: boolean = isAppleEngine()): number {
  if (apple) return SCRIPT_BUFFER
  const base = (context as { baseLatency?: unknown }).baseLatency
  if (typeof base !== 'number' || !Number.isFinite(base) || !(base > 0) || !(context.sampleRate > 0)) return SCRIPT_BUFFER
  return base * context.sampleRate <= SCRIPT_BUFFER_SMALL * 1.02 ? SCRIPT_BUFFER_SMALL : SCRIPT_BUFFER
}

//? the smallest block the main-thread voice uses on this page: SCRIPT_BUFFER once its stamps have shown the
//? hardware renders more than a small block at a time, or a small block was late where it sounded
//? (SCRIPT_SHARED_OF) - so the next context starts there
let scriptBlockFloor = SCRIPT_BUFFER_SMALL

/** The main-thread voice's counted clock (countBlock): the next block's time (null before the first), the
 *  stamps' drift from it, the stamp before and whether it was evenly spaced, the least distance of the stamps
 *  waited on as far later (null: none), and how much longer, in seconds, the count is unproven. */
export interface ScriptClock {
  counted: number | null
  drift: number
  last: number | null
  /** whether the stamp before was evenly spaced from the one before it (a block on, to the tolerance) */
  even: boolean
  hold: number | null
  unproven: number
}

export function newScriptClock(): ScriptClock {
  return { counted: null, drift: 0, last: null, even: false, hold: null, unproven: 0 }
}

/**
 * The time the main-thread voice renders a block at (2.0.0-player.31, and .40's rules - SCRIPT_REANCHOR_S
 * says them): `reported` is the block's playbackTime, `seconds` its length. Pure, and the clock moved on.
 */
export function countBlock(clock: ScriptClock, reported: number, seconds: number): number {
  const counted = clock.counted
  let at: number
  let even = false
  if (counted === null) {
    //? the first block: anchored on its stamp, unproven yet
    at = reported
    clock.drift = 0
    clock.unproven = SCRIPT_PROVE_S
  } else {
    const off = reported - counted
    const last = clock.last!
    even = Math.abs(reported - last - seconds) <= SCRIPT_STAMP_TOLERANCE_S
    if (reported <= last + SCRIPT_STAMP_TOLERANCE_S / 2) {
      //? a burst - stamped no later than the block before: the next block all the same, counted on
      at = counted
      clock.hold = null
    } else if (off < -SCRIPT_REANCHOR_S || (clock.unproven > 0 && off < -SCRIPT_STAMP_TOLERANCE_S)) {
      //? a stamp earlier than the count: a stamp is never early, so the count was ahead - anchored there
      at = reported
      clock.drift = 0
      clock.hold = null
    } else if (off > SCRIPT_REANCHOR_S) {
      //? far later than the count: blocks never asked for - or the page late, or a burst to come. Counted on,
      //? until two callbacks in a row are evenly spaced again, every stamp since as far on
      if (clock.hold !== null && even && clock.even) {
        at = counted + Math.min(clock.hold, off)
        clock.drift = 0
        clock.hold = null
        clock.unproven = SCRIPT_PROVE_S
      } else {
        at = counted
        clock.hold = clock.hold === null ? off : Math.min(clock.hold, off)
      }
    } else if (Math.abs(off) <= SCRIPT_STAMP_TOLERANCE_S) {
      //? a stamp that agrees with the count: an exact clock (Chromium's), followed as it is
      at = reported
      clock.drift = 0
      clock.hold = null
      clock.unproven = 0
    } else {
      //? a stamp a step away from the count: WebKit's jitter, or the page late with this block - the count
      //? holds, eased toward the stamps' LOWER edge (a stamp can be late, never early: down at once to one
      //? earlier than it, up over SCRIPT_DRIFT_EASE_S), by at most SCRIPT_SLEW_PER_S a second. Until
      //? 2.0.0-player.40 toward their running mean - so a page late now and then eased it ahead of the truth
      clock.hold = null
      clock.drift = off < clock.drift ? off : clock.drift + (off - clock.drift) * Math.min(1, seconds / SCRIPT_DRIFT_EASE_S)
      const slew = SCRIPT_SLEW_PER_S * seconds
      at = counted + Math.max(-slew, Math.min(slew, clock.drift))
    }
  }
  clock.last = reported
  clock.even = even
  clock.unproven -= seconds
  clock.counted = at + seconds
  return at
}

const message = (error: unknown) => (error instanceof Error ? error.message : String(error))

function audioChanged(): void {
  const context = audio.context
  if (sleepOnceRunning && context?.state === 'running') {
    sleepOnceRunning = false
    context.suspend().then(audioChanged, audioChanged)
  }
  for (const listener of [...audioListeners]) listener()
}

function contextClass(): (new (options?: AudioContextOptions) => AudioContext) | null {
  const scope = globalThis as { AudioContext?: new (options?: AudioContextOptions) => AudioContext; webkitAudioContext?: new () => AudioContext }
  return scope.AudioContext ?? scope.webkitAudioContext ?? null
}

/** The voice for a new context: the worklet where there is one - and the script voice where there
 *  isn't (a page that isn't on HTTPS), or where it couldn't be made or wouldn't load. */
function startVoice(context: AudioContext): void {
  if (!context.audioWorklet || typeof AudioWorkletNode === 'undefined') {
    const insecure = (globalThis as { isSecureContext?: boolean }).isSecureContext === false
    startScript(context, insecure ? "this page isn't on HTTPS, so the browser has no AudioWorklet" : 'this browser has no AudioWorklet')
    return
  }
  try {
    moduleUrl ??= URL.createObjectURL(new Blob([voiceWorkletSource()], { type: 'text/javascript' }))
  } catch (error) {
    startScript(context, `the AudioWorklet couldn't be made (${message(error)})`)
    return
  }
  audio.loading = true
  context.audioWorklet.addModule(moduleUrl).then(() => {
    if (audio.context !== context) return
    const node = new AudioWorkletNode(context, VOICE_PROCESSOR, { numberOfInputs: 0, numberOfOutputs: 1, outputChannelCount: [2] })
    node.port.onmessage = (event: MessageEvent) => heard(event.data as VoiceHeard)
    node.connect(context.destination)
    audio.node = node
    //? the render quantum, which a worklet renders a block of at a time
    audio.block = 128
    audio.voice = { kind: 'worklet', ready: true, post: (said, transfer) => node.port.postMessage(said, transfer), disconnect: () => node.disconnect() }
  }).catch((error: unknown) => {
    if (audio.context === context && !audio.voice) startScript(context, `the AudioWorklet wouldn't load (${message(error)})`)
  }).finally(() => {
    if (audio.context === context) audio.loading = false
    audioChanged()
  })
}

/**
 * The script voice: a ScriptProcessorNode (no inputs, two output channels, its block - SCRIPT_BUFFER_SMALL or
 * SCRIPT_BUFFER, scriptBlockFor - a block) on
 * the page's main thread, running THE SAME functions the worklet runs - lib/deckVoice.ts's
 * newVoiceState, voiceCommand, renderVoice and voiceReport, never a copy of them. Each block is
 * rendered as of the context time it will play at (its `playbackTime`, a block ahead of `currentTime`
 * as the browser asks for it - counted, countBlock), and the messages that came since the last are applied to
 * its state just before, as of that same time - as the worklet applies each on the audio clock as it comes. And
 * what each says is heard SCRIPT_LAG_BLOCKS blocks after it was said - the most a message waits for the
 * block it is first heard in - so a take and the drives after it keep the same spacing they had as they
 * were said, and the voice plays exactly what the worklet would, that much later. Applied as they came,
 * as of `currentTime`, a take started a block or two behind where the record was by the time it was
 * heard, and raced to catch it up (review of 2.0.0-player.16: up to 1.8 times the speed, for 20-80 ms,
 * on every grab and every wind-down); placed where the record had got to instead, a grab's still hand
 * then pulled it back as far. Since 2.0.0-player.24 a hand's samples and a plan's frames are each a knot
 * of the path the voice plays, so every one is held and applied, in order, each heard the same lag on -
 * none replacing another, as the worklet keeps every one (until its review a drive replaced a drive held
 * just before it, a knot the worklet kept and this didn't); only a window replaces every window before
 * it. It says where it is as often as the worklet does. Ready once it has played its first block.
 * Blocks of SCRIPT_BUFFER_SMALL whose stamps show the hardware asking for more than one at a time
 * (SCRIPT_SHARED_OF), or one of which was late where the voice sounded, are given up for a node of
 * SCRIPT_BUFFER, made as the voice next falls silent - its state, and what is held for it, carried over
 * (2.0.0-player.40).
 */
function startScript(context: AudioContext, why: string): void {
  if (typeof context.createScriptProcessor !== 'function') {
    audio.missing = 'no-voice'
    return
  }
  try {
    const state = newVoiceState()
    const held: VoiceMessage[] = []
    let block = Math.max(scriptBlockFor(context), scriptBlockFloor)
    let lag = (SCRIPT_LAG_BLOCKS * block) / context.sampleRate
    let node: ScriptProcessorNode
    const voice: Voice = {
      kind: 'script',
      ready: false,
      post: (message) => {
        const said = message.type === 'take' || message.type === 'drive' ? { ...message, time: message.time + lag, until: message.until + lag }
          : message.type === 'hand' ? { ...message, time: message.time + lag } : message
        //? a window sets nothing but the window, so only the newest counts - and a hand's sample or a
        //? plan's frame is never dropped: each is a knot of the path, as the worklet has it
        if (said.type === 'window') for (let i = held.length - 1; i >= 0; i--) if (held[i]!.type === 'window') held.splice(i, 1)
        held.push(said)
      },
      disconnect: () => {
        node.onaudioprocess = null
        held.length = 0
        node.disconnect()
      },
    }
    //? the counted clock (countBlock); and the stamps' watch (SCRIPT_SHARED_OF) - which of the last blocks
    //? shared a stamp with the one before, the first of a pair or a run only, and how many of them did
    let count = newScriptClock()
    let blocks = 0
    const sharing = new Uint8Array(SCRIPT_SHARED_WINDOW)
    let shares = 0
    let sharedBefore = false
    let bigger = false
    //? the loudest sample of the last two blocks the voice wrote
    const peaks = [0, 0]
    const onBlock = (event: AudioProcessingEvent) => {
      const out = event.outputBuffer
      const channels: Float32Array[] = []
      for (let channel = 0; channel < out.numberOfChannels; channel++) channels.push(out.getChannelData(channel))
      const reported = Number.isFinite(event.playbackTime) ? event.playbackTime : context.currentTime
      const blockSeconds = out.length / context.sampleRate
      const shared = count.last !== null && reported <= count.last + SCRIPT_STAMP_TOLERANCE_S / 2
      const at = countBlock(count, reported, blockSeconds)
      for (const said of held.splice(0)) voiceCommand(state, said, at, context.sampleRate)
      renderVoice(state, channels, out.length, context.sampleRate, at)
      const said = voiceReport(state, out.length, context.sampleRate, at, REPORTS_PER_SECOND)
      if (said) heard(said)
      //? how loud this block is, and the two before it: a block written late plays the one two before it again
      //? in its place, which is heard only where one of them sounds
      let peak = 0
      for (const data of channels) for (let i = 0; i < data.length; i++) peak = Math.max(peak, Math.abs(data[i]!))
      const heardHere = Math.max(peak, peaks[0]!, peaks[1]!) > SCRIPT_HEARD_LEVEL
      peaks[1] = peaks[0]!
      peaks[0] = peak
      //? asked for after it was due to play: the block's start, as counted, already past once it was written -
      //? the page was busy, and what was heard there had a gap or a block played twice. Until 2.0.0-player.40
      //? this compared currentTime with the stamp, which Chromium makes from currentTime as it asks - never late
      const lateBy = context.currentTime - at
      soundHealth.blocks += 1
      if (lateBy > 0) {
        soundHealth.lateBlocks += 1
        soundHealth.worstBlockMs = Math.max(soundHealth.worstBlockMs, lateBy * 1000)
        //? a small block late where the voice sounds: the page can't keep up with blocks that short
        if (block < SCRIPT_BUFFER && heardHere) bigger = true
      }
      if (!voice.ready && audio.voice === voice) {
        voice.ready = true
        audioChanged()
      }
      if (block < SCRIPT_BUFFER) {
        blocks += 1
        const slot = blocks % SCRIPT_SHARED_WINDOW
        const counts = shared && !sharedBefore && blocks > SCRIPT_SHARED_AFTER ? 1 : 0
        shares += counts - sharing[slot]!
        sharing[slot] = counts
        if (shares >= SCRIPT_SHARED_OF) bigger = true
      }
      sharedBefore = shared
      //? the hardware asks for more than one small block at a time, or the page can't keep up with them: a node
      //? of SCRIPT_BUFFER as the voice next falls silent - faded or stopped, and heard no more (a let-go of a
      //? playing record leaves it following the handover's run-out, silent), nothing held for it (the next
      //? sound is a take, which starts its path afresh at the new lag), nothing being recorded - for good on
      //? this page
      if (bigger && state.gainTarget === 0 && !(state.gain > 1e-5) && !held.length && !recording && audio.voice === voice) {
        bigger = false
        scriptBlockFloor = SCRIPT_BUFFER
        node.onaudioprocess = null
        node.disconnect()
        block = SCRIPT_BUFFER
        lag = (SCRIPT_LAG_BLOCKS * block) / context.sampleRate
        count = newScriptClock()
        node = make(block)
        audio.node = node
        audio.block = block
        audioChanged()
      }
    }
    const make = (size: number): ScriptProcessorNode => {
      const made = context.createScriptProcessor(size, 0, 2)
      made.onaudioprocess = onBlock
      made.connect(context.destination)
      return made
    }
    node = make(block)
    audio.voice = voice
    audio.node = node
    audio.block = block
    audio.why = why
  } catch (error) {
    audio.problem = `the sound's ScriptProcessorNode couldn't be made - ${message(error)}`
  }
}

/** The page's audio session made 'playback' (Safari 16.4+'s navigator.audioSession; nothing where it
 *  is absent) as the deck wakes, in the gesture: while the record's sound plays the song's element is
 *  paused, and WebKit then gives Web Audio the 'ambient' kind, which an iPhone's silent switch mutes. */
function holdAudioSession(): void {
  try {
    const session = (globalThis as { navigator?: { audioSession?: { type: string } } }).navigator?.audioSession
    if (!session || sessionBefore !== null) return
    const before = session.type
    session.type = 'playback'
    //? only a kind the deck really changed is put back
    sessionBefore = before
  } catch {
    //? a session that won't be set: the sound is as it would have been
  }
}

/** ...and put back as it was when the turntable goes. */
function releaseAudioSession(): void {
  const before = sessionBefore
  sessionBefore = null
  if (before === null) return
  try {
    const session = (globalThis as { navigator?: { audioSession?: { type: string } } }).navigator?.audioSession
    if (session) session.type = before
  } catch {
    //? nothing more to put back
  }
}

/**
 * Make the turntable's audio context, or resume it - IN AN ACTIVATING GESTURE ONLY (a click, a
 * pointerup, a keyup): the record's tap and release, the look button switching to the turntable, the
 * transport buttons. WebKit lets audio start only from one, and doesn't count a pointerdown.
 */
export function wakeDeckAudio(): void {
  try {
    if (!audio.context) {
      const Context = contextClass()
      if (!Context) {
        audio.missing = 'unsupported'
        audioChanged()
        return
      }
      holdAudioSession()
      const context = new Context({ latencyHint: 'interactive' })
      audio.context = context
      audio.problem = null
      audio.missing = null
      audio.why = null
      audio.block = null
      speakerReadings.length = 0
      resetDeckClock(clock)
      //? suspended or resumed, its clock stood still meanwhile: the mapping starts again
      context.addEventListener?.('statechange', () => resetDeckClock(clock))
      context.addEventListener?.('statechange', () => {
        if ((context.state as string) === 'interrupted') soundHealth.interruptions += 1
      })
      context.addEventListener?.('statechange', audioChanged)
      startVoice(context)
      audioChanged()
    }
    resumeDeckAudio()
  } catch (error) {
    audio.problem = `the sound couldn't start - ${message(error)}`
    audioChanged()
  }
}

/** Resume the turntable's audio context if there is one - in an activating gesture only, as above
 *  (App calls it as the mini player's tap opens the screen). Never makes one. */
export function resumeDeckAudio(): void {
  const context = audio.context
  //? a gesture asking for the sound: a hide before it no longer counts (the mini player's tap resumes
  //? it a moment before the turntable shows)
  sleepOnceRunning = false
  if (!context || context.state === 'running' || context.state === 'closed') return
  context.resume().then(audioChanged, (error: unknown) => {
    audio.problem = `the sound couldn't start - ${message(error)}`
    audioChanged()
  })
}

/* ----- a recording of the record's sound, for a bug report (2.0.0-player.32) ----- */

/**
 * What the voice said about where it is, to the deck - and to a recording under way. The worklet posts
 * it from its port, the main-thread voice says it from its block.
 */
function heard(said: VoiceHeard): void {
  recording?.heard.push(said)
  //? what the limiter did since the voice last said (2.0.0-player.35), counted for Debug
  if (said.held > 0) {
    soundHealth.peaksHeld += said.peaks
    soundHealth.samplesHeld += said.held
    healthMoved = true
  }
  if (said.lowest < 1) {
    //? read as at least DEEPEST_GAIN_SAID: the voice floors its gain at 0 (only for a window some 1e16
    //? times full scale), and -20 log10 of 0 is Infinity - of anything below it, NaN - which Debug would
    //? print (review of 2.0.0-player.35)
    const lowest = said.lowest > DEEPEST_GAIN_SAID ? said.lowest : DEEPEST_GAIN_SAID
    const deepest = -20 * Math.log10(lowest)
    //? a deeper dip than any so far is news; a gain still coming back up after one (lowest under 1, nothing
    //? new held) is not - it would have the deck report every HEALTH_REPORT_MS for the second it takes
    if (deepest > soundHealth.deepestHoldDb) {
      soundHealth.deepestHoldDb = deepest
      healthMoved = true
    }
  }
  heardListener?.(said)
}

interface DeckRecording {
  seconds: number
  since: number
  until: number
  kind: 'worklet' | 'script'
  rate: number
  /** the frames the voice renders at a time, as the recording began (2.0.0-player.40: 512 or 1024 on the main
   *  thread, which doesn't change while one runs) */
  block: number
  blocks: Float32Array[][]
  blockTimes: number[]
  /** each tapped block's loudest sample as a float, before the file's 16 bits clamp it (2.0.0-player.35) */
  blockPeaks: number[]
  messages: Record<string, unknown>[]
  heard: VoiceHeard[]
  tap: ScriptProcessorNode
  timer: ReturnType<typeof setTimeout>
  /** kept for the page as well as offered as the file (2.0.0-player.36, the test bench) */
  keep: boolean
}

/** A recording running, or the last one made: what Debug offers to save. */
export interface DeckRecorded {
  state: 'recording' | 'saved'
  seconds: number
  /** the file, once saved: its address (a blob URL), name and size */
  href?: string
  name?: string
  bytes?: number
}

let recording: DeckRecording | null = null
let recorded: DeckRecorded | null = null

/**
 * The last recording, as the page keeps it (2.0.0-player.36): the test bench at /player/lab/ replays its
 * messages through the voice's own functions and sets what the voice played beside an ideal turntable.
 * What it holds is what the saved file holds - the tapped audio (as floats here, every channel, each
 * block's playbackTime), every message the deck sent the voice, everything the voice said of where it
 * was, the clock's mapping - and the file's own text, so the page can offer the very file. Kept only
 * for a recording started with `keep` - Debug's never is - and only the last.
 */
export interface DeckRecordingData {
  voice: 'worklet' | 'script'
  sampleRate: number
  /** the frames the voice rendered at a time (2.0.0-player.40): the main-thread voice's block, 512 or 1024 -
   *  what its lag is made of - or the worklet's 128 */
  block: number
  /** the tapped audio, every channel, the blocks one after another */
  channels: Float32Array[]
  tapBlock: number
  blockTimes: number[]
  blockPeaks: number[]
  /** page ms the recording began, and ended */
  since: number
  until: number
  messages: Record<string, unknown>[]
  heard: VoiceHeard[]
  clock: { offset: number | null; step: number; count: number }
  delaySeconds: number
  scriptLagSeconds: number
  /** the saved file's text, exactly */
  file: string
}

let kept: DeckRecordingData | null = null

/** The last recording started with `keep` - null until one has finished. */
export function deckRecordingData(): DeckRecordingData | null {
  return kept
}

/** Finish the recording under way now, as its time running out would - the test bench's "Record the
 *  next motion" stops it as the motion has settled. Nothing when none is. */
export function stopDeckRecording(): void {
  finishRecording()
}
const recordingListeners = new Set<(state: DeckRecorded | null) => void>()

export function deckRecorded(): DeckRecorded | null {
  return recorded
}

export function onDeckRecorded(listener: (state: DeckRecorded | null) => void): () => void {
  recordingListeners.add(listener)
  return () => recordingListeners.delete(listener)
}

function recordedChanged(): void {
  for (const listener of [...recordingListeners]) listener(recorded)
}

/** A message the deck sent the voice, noted by a recording under way - a window by its shape only. */
function noteForRecording(message: VoiceMessage): void {
  if (!recording) return
  const t = Math.round(now() * 10) / 10
  if (message.type === 'window') recording.messages.push({ t, type: 'window', start: message.start, rate: message.rate, length: message.channels[0]?.length ?? 0 })
  else recording.messages.push({ t, ...message })
}

/**
 * RECORD THE RECORD'S SOUND for `seconds` (2.0.0-player.32): what the voice's node actually plays, tapped
 * by a ScriptProcessorNode of its own, with every message the deck sent the voice meanwhile (each hand
 * sample as it came, the takes, the drives, the fades) and everything the voice said of where it was -
 * then offered to save as one JSON file, the audio in it as 16-bit samples. James hears "a digital sound"
 * on his iPhone and his Mac that no lab recording here has shown, after three fixes each of which was
 * real and none of which was it; this is the ground truth, so the voice can be replayed here with his
 * very samples and its output held against what he heard. Since 2.0.0-player.35 (version 2) the file also
 * carries each tapped block's loudest sample as a float (`blockPeaks`) - the 16-bit audio clamps at full
 * scale, so that is what says how far over anything went - and the limiter's ceiling and lookahead; the
 * voice's own reports in it say what its limiter held down. A diagnostic, nothing the player does: the tap
 * hangs off the voice's own node and never the song's element. Starts only from a tap (Debug's button),
 * since it may make the context. Answers why it couldn't start, or null.
 */
export function recordDeckSound(seconds = 20, keep = false): string | null {
  if (recording) return 'already recording'
  wakeDeckAudio()
  const context = audio.context
  const node = audio.node
  const voice = audio.voice
  //? a voice not ready yet (the script voice before its first block, a worklet still loading) has nothing to
  //? tap: the record's sound starts from a turn, so that is what is asked for
  if (!context || !node || !voice || !voice.ready || context.state !== 'running') return audio.problem ?? 'the sound has not started - turn the record once first'
  if (typeof context.createScriptProcessor !== 'function') return 'this browser cannot tap the sound'
  try {
    const tap = context.createScriptProcessor(4096, 2, 2)
    const started: DeckRecording = {
      seconds, since: now(), until: now() + seconds * 1000, kind: voice.kind, rate: context.sampleRate,
      block: audio.block ?? (voice.kind === 'script' ? SCRIPT_BUFFER : 128), blocks: [], blockTimes: [], blockPeaks: [], messages: [], heard: [], tap,
      timer: setTimeout(() => finishRecording(), seconds * 1000), keep,
    }
    tap.onaudioprocess = (event: AudioProcessingEvent) => {
      if (recording !== started) return
      const input = event.inputBuffer
      const copies: Float32Array[] = []
      //? and the block's loudest sample as it is, a float: the 16-bit file clamps at full scale, so this
      //? is what says how far over anything went
      let loudest = 0
      for (let c = 0; c < input.numberOfChannels; c++) {
        const copy = Float32Array.from(input.getChannelData(c))
        for (let i = 0; i < copy.length; i++) {
          const size = Math.abs(copy[i]!)
          if (size > loudest) loudest = size
        }
        copies.push(copy)
      }
      started.blocks.push(copies)
      started.blockTimes.push(event.playbackTime)
      started.blockPeaks.push(loudest)
    }
    node.connect(tap)
    tap.connect(context.destination)
    if (recorded?.href) URL.revokeObjectURL(recorded.href)
    recording = started
    recorded = { state: 'recording', seconds }
    recordedChanged()
    return null
  } catch (error) {
    return `the recording couldn't start - ${message(error)}`
  }
}

function finishRecording(): void {
  const done = recording
  if (!done) return
  recording = null
  clearTimeout(done.timer)
  done.tap.onaudioprocess = null
  try {
    audio.node?.disconnect(done.tap)
  } catch {
    //? the node may be gone already
  }
  try {
    done.tap.disconnect()
  } catch {
    //? likewise
  }
  const frames = done.blocks.reduce((sum, block) => sum + (block[0]?.length ?? 0), 0)
  const channels = Math.max(1, ...done.blocks.map((block) => block.length))
  //? 16-bit, interleaved, as a WAV holds it - base64 in the JSON
  const pcm = new Int16Array(frames * channels)
  let at = 0
  for (const block of done.blocks) {
    const length = block[0]?.length ?? 0
    for (let i = 0; i < length; i++) {
      for (let c = 0; c < channels; c++) {
        const v = block[c]?.[i] ?? block[0]![i]!
        pcm[at++] = Math.max(-32768, Math.min(32767, Math.round(v * 32767)))
      }
    }
  }
  const bytes = new Uint8Array(pcm.buffer)
  //? in pieces of a multiple of THREE bytes: a piece that isn't one is padded with '=' by btoa, and
  //? padding in the middle of the text breaks the decode (the first cut's 32768-byte pieces did)
  const PIECE = 32766
  let base64 = ''
  for (let i = 0; i < bytes.length; i += PIECE) base64 += btoa(String.fromCharCode(...bytes.subarray(i, i + PIECE)))
  const payload = {
    recording: 'deadwax turntable sound', version: 3, when: new Date().toISOString(),
    userAgent: typeof navigator !== 'undefined' ? navigator.userAgent : '',
    secure: (globalThis as { isSecureContext?: boolean }).isSecureContext ?? null,
    voice: done.kind, sampleRate: done.rate, delaySeconds: HAND_DELAY_S,
    //? the block the voice rendered at a time, and the lag it makes on the main thread (2.0.0-player.40): a
    //? replay reads them here, never from the build replaying it
    block: done.block,
    scriptLagSeconds: done.kind === 'script' ? (SCRIPT_LAG_BLOCKS * done.block) / done.rate : 0,
    //? and what the device's audio adds after the voice, as its context said it
    latency: deckLatency(),
    clock: deckClockMapping(), report: lastReport, pageTimeAtStart: done.since,
    tapBlock: 4096, blockTimes: done.blockTimes, blockPeaks: done.blockPeaks,
    limiter: { ceiling: VOICE_CEILING, lookaheadSeconds: VOICE_LOOKAHEAD_S },
    audio: { format: 'int16le', channels, frames, base64 },
    messages: done.messages, heard: done.heard,
  }
  const text = JSON.stringify(payload)
  const blob = new Blob([text], { type: 'application/json' })
  const name = `deadwax-turntable-${done.kind}-${new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19)}.json`
  if (done.keep) {
    //? the test bench's (2.0.0-player.36): the same recording as floats, every channel, for the page
    const floats: Float32Array[] = []
    for (let c = 0; c < channels; c++) {
      const channel = new Float32Array(frames)
      let to = 0
      for (const block of done.blocks) {
        const data = block[c] ?? block[0]!
        channel.set(data, to)
        to += data.length
      }
      floats.push(channel)
    }
    kept = {
      voice: done.kind, sampleRate: done.rate, block: done.block, channels: floats, tapBlock: 4096, blockTimes: done.blockTimes, blockPeaks: done.blockPeaks,
      since: done.since, until: now(), messages: done.messages, heard: done.heard, clock: payload.clock,
      delaySeconds: payload.delaySeconds, scriptLagSeconds: payload.scriptLagSeconds, file: text,
    }
  }
  recorded = { state: 'saved', seconds: done.seconds, href: URL.createObjectURL(blob), name, bytes: blob.size }
  recordedChanged()
}

/* ----- what the test bench's live spectrogram reads (2.0.0-player.36) ----- */

let analyser: { node: AudioNode; analyser: AnalyserNode; silent: GainNode } | null = null

/**
 * An AnalyserNode on the record's sound - hung off the voice's own node in the deck's own context, the
 * way the recorder's tap is, and on to the speakers through a gain of 0, so a browser that only runs
 * what reaches them runs it and nothing heard changes. For the test bench's live spectrogram; nothing
 * of the app asks for it. Made again when the voice is (a new context, the script voice after a worklet
 * that wouldn't load); null while there is none. Never the song's element.
 */
export function deckSoundAnalyser(): AnalyserNode | null {
  const node = audio.node
  const context = audio.context
  if (analyser && analyser.node === node && context && analyser.analyser.context === context) return analyser.analyser
  releaseDeckSoundAnalyser()
  if (!node || !context || context.state === 'closed') return null
  try {
    const made = context.createAnalyser()
    made.fftSize = 8192
    made.smoothingTimeConstant = 0
    const silent = context.createGain()
    silent.gain.value = 0
    node.connect(made)
    made.connect(silent)
    silent.connect(context.destination)
    analyser = { node, analyser: made, silent }
    return made
  } catch {
    return null
  }
}

/** ...and let go of: the page hidden, or the bench done with it. */
export function releaseDeckSoundAnalyser(): void {
  const was = analyser
  analyser = null
  if (!was) return
  try {
    was.node.disconnect(was.analyser)
  } catch {
    //? the node may be gone with its context
  }
  try {
    was.analyser.disconnect()
    was.silent.disconnect()
  } catch {
    //? likewise
  }
}

/** Suspended - or, starting or resuming still, suspended as soon as it runs. */
function sleepDeckAudio(): void {
  const context = audio.context
  if (!context || context.state === 'closed') return
  if (context.state === 'running') context.suspend().then(audioChanged, audioChanged)
  else sleepOnceRunning = true
}

function closeDeckAudio(): void {
  const context = audio.context
  try {
    audio.voice?.disconnect()
  } catch {
    //? a node going with its context: nothing to stop
  }
  audio.context = null
  audio.voice = null
  audio.node = null
  audio.block = null
  audio.loading = false
  audio.problem = null
  audio.why = null
  sleepOnceRunning = false
  resetDeckClock(clock)
  if (context && context.state !== 'closed') context.close().catch(() => undefined)
  releaseAudioSession()
  audioChanged()
}

/** The one clock's mapping as it stands (2.0.0-player.24): the offset in use (context s less page s),
 *  the smallest step the audio's clock has been seen to move by, and how many readings it is made of. */
export function deckClockMapping(): { offset: number | null; step: number; count: number } {
  return { offset: clock.offset, step: clock.step, count: clock.count }
}

/* ----- what the device's audio adds (2.0.0-player.40) ----- */

//? the render clock's lead over what is at the speaker, read from getOutputTimestamp() as the clock is read
//? (seconds; the last few, for their median)
const speakerReadings: number[] = []
const SPEAKER_READINGS = 9

/** One reading of how far the render clock is ahead of what is at the speaker now, where the browser says -
 *  getOutputTimestamp(): the context time at the speaker as of a page time - and nothing where it doesn't
 *  (an older Safari may not), isn't running or says nonsense. */
function readSpeaker(context: AudioContext): void {
  try {
    if (context.state !== 'running' || typeof performance === 'undefined') return
    const stamp = (context as { getOutputTimestamp?: () => AudioTimestamp }).getOutputTimestamp?.()
    const at = stamp?.contextTime, page = stamp?.performanceTime
    if (typeof at !== 'number' || typeof page !== 'number' || !(at > 0) || !(page > 0) || !Number.isFinite(at) || !Number.isFinite(page)) return
    const lead = context.currentTime - (at + (performance.now() - page) / 1000)
    if (!Number.isFinite(lead) || lead < 0 || lead > 2) return
    speakerReadings.push(lead)
    if (speakerReadings.length > SPEAKER_READINGS) speakerReadings.shift()
  } catch {
    //? a browser that throws for it: nothing said
  }
}

/** A number the context gives, in seconds - or null where it gives none, or one that can't be. */
function positive(value: unknown): number | null {
  return typeof value === 'number' && Number.isFinite(value) && value > 0 ? value : null
}

/**
 * What the device's audio adds after the voice, as the context says it (2.0.0-player.40) - so a phone says
 * what a lab can't: `base` its base latency (in Chromium the hardware's render; in WebKit only its 128-frame
 * render quantum, whatever the hardware runs), `output` its output latency (from there to the speaker - a
 * Bluetooth headset's own included, where the browser knows it), `speaker` how far the render clock is ahead
 * of what is at the speaker, read from getOutputTimestamp() (the median of the last few readings) - base and
 * output together, read another way, each in seconds or null where the
 * browser doesn't say (an older Safari may have neither of the last two); and `block`, the frames the voice
 * renders at a time; and `design`, the record's sound behind the hand before any of that - HAND_DELAY_S, the
 * main-thread voice's lag and the limiter's lookahead. Null with no context.
 */
export function deckLatency(): DeckLatency | null {
  const context = audio.context
  if (!context) return null
  const sorted = [...speakerReadings].sort((a, b) => a - b)
  const block = audio.block
  const lag = audio.voice?.kind === 'script' && block ? (SCRIPT_LAG_BLOCKS * block) / context.sampleRate : 0
  return {
    base: positive((context as { baseLatency?: unknown }).baseLatency),
    output: positive((context as { outputLatency?: unknown }).outputLatency),
    speaker: sorted.length ? sorted[sorted.length >> 1]! : null,
    block,
    design: audio.voice ? HAND_DELAY_S + lag + VOICE_LOOKAHEAD_S : null,
  }
}

/** Whether the audio context runs. */
export function deckAudioRunning(): boolean {
  return audio.context?.state === 'running'
}

/** Whether the record's sound can play: the context runs and a voice - worklet or script - is ready. */
function voiceReady(): boolean {
  return deckAudioRunning() && !!audio.voice?.ready
}

/* ===== what Info > Debug reads ===== */

let lastReport: DeckReport | null = null
const reportListeners = new Set<(report: DeckReport | null) => void>()

/** The turntable's sound as it last was - null while no turntable shows. */
export function deckReport(): DeckReport | null {
  return lastReport
}

/** Be told when it changes (App, for Info). Returns the way to stop. */
export function onDeckReport(listener: (report: DeckReport | null) => void): () => void {
  reportListeners.add(listener)
  return () => reportListeners.delete(listener)
}

function publish(report: DeckReport | null): void {
  lastReport = report
  for (const listener of [...reportListeners]) listener(report)
}

/* ===== the deck ===== */

const now = () => (typeof performance !== 'undefined' ? performance.now() : Date.now())
const frame = (run: FrameRequestCallback): number => (typeof requestAnimationFrame === 'function' ? requestAnimationFrame(run) : 0)
const cancelFrame = (id: number) => {
  if (id && typeof cancelAnimationFrame === 'function') cancelAnimationFrame(id)
}

/** Where a plan goes, its lowest point and its highest - each phase moves one way, so its ends. */
function reach(plan: Plan): { low: number; high: number } {
  let low = Infinity, high = -Infinity
  for (const phase of plan.phases) {
    for (const x of [phaseAt(phase, 0).x, phaseAt(phase, phase.duration).x]) {
      low = Math.min(low, x)
      high = Math.max(high, x)
    }
  }
  return Number.isFinite(low) ? { low, high } : { low: plan.x, high: plan.x }
}

export class Deck {
  private readonly host: DeckHost
  private motion: Motion = { kind: 'still' }
  /** the face's angle while still, held still or under the hand, degrees */
  private angle = 0
  private press: Press | null = null
  /** a press the deck doesn't take has the record (holdStill): it stops under the finger */
  private stilled = false
  private holdTimer: ReturnType<typeof setTimeout> | undefined
  private planTimer: ReturnType<typeof setTimeout> | undefined
  private settleTimer: ReturnType<typeof setTimeout> | undefined
  private resumeTimer: ReturnType<typeof setTimeout> | undefined
  private handoverTimer: ReturnType<typeof setTimeout> | undefined
  private clockTimer: ReturnType<typeof setTimeout> | undefined
  //? the timer's readings since it last started afresh: quick ones, the mapping still young, only for the
  //? first CLOCK_SETTLE_TICKS of them
  private clockTicks = 0
  private handoverOff: (() => void) | null = null
  private raf = 0
  private showing = false
  private reduced = false
  private windDown = true
  private wasPlaying = false
  private positionOff: (() => void) | null = null
  private reducedQuery: MediaQueryList | null = null

  //? the record's sound
  private window: { song: string; start: number; end: number; bytes: number; decodedAt: number } | null = null
  //? the one window on its way, from the ask until it is in the voice - fetched ('fetch'), or its
  //? bytes in hand, being decoded or waiting to be ('held') - and the stretch of the song it covers
  private pending: { song: string; from: number; to: number; stage: 'fetch' | 'held' } | null = null
  private fetchedWindow: { song: string; bytes: ArrayBuffer; first: number; rate: number } | null = null
  private decodedWindow: { song: string; channels: Float32Array[]; start: number; rate: number; bytes: number } | null = null
  private readonly requests = latestOnly()
  //? only the newest decode is handed on: an older one landing last never replaces it
  private readonly decodes = latestOnly()
  //? how long this song's windows come back - shorter than WINDOW_S for a hi-res song deadwax cut short
  private span: { song: string; seconds: number } | null = null
  private refreshedAt = -Infinity
  private refused: { song: string; why: string } | null = null
  //? the song a press the deck didn't take wanted the window for, before there was a voice to put it in:
  //? asked for once there is (review of 2.0.0-player.16: the release lets go of the press first, and the
  //? ask was lost - two silent turns of a paused record, not one)
  private wanted: string | null = null
  private failed: { song: string; why: string; until: number } | null = null
  private fetched = 0
  private since = now()
  //? ms after the turntable showed that the last window landed - what Debug's cost is measured to
  private lastFetchAt = 0
  private heard: (VoiceHeard & { at: number }) | null = null
  //? the latest page time (ms) anything told the voice was stamped at: a frame no later than it has
  //? nothing to add to the path (stampedTo)
  private stampedTo = -Infinity
  //? the audio clock's step as Debug was last told it
  private reportedStep = 0
  //? when (page ms) Debug was last told anything - the limiter's late counts wait HEALTH_REPORT_MS from it
  private reportedAt = -Infinity
  //? a let-go that means the song to play: where it was sought, when (page ms) and how long the record's
  //? run back to speed is - until the song's own playback is seen moving from there (noteBack)
  private letGo: { at: number; since: number; motor: number } | null = null
  private backMs: number | null = null
  private motorMs: number | null = null
  private notBack = 0
  //? frames while a hand holds the record: the last one's time, and the count
  private heldFrame = 0
  private frames = 0
  private slowFrames = 0
  private worstFrameMs = 0
  //? the handover's test of the song's position, asked every frame as well as when the player says
  private handoverJudge: ((seconds: number) => void) | null = null
  private songId: string
  //? the player's speed (2.0.0-player.39): the motor's, in the platter's own speeds - 1 is 33 1/3 rpm
  private speed = 1

  constructor(host: DeckHost) {
    this.host = host
    this.songId = host.song()?.id ?? ''
    this.wasPlaying = host.playing()
    this.motion = this.wasPlaying ? { kind: 'turning', since: now(), from: 0 } : { kind: 'still' }
    heardListener = this.onHeard
    audioListeners.add(this.onAudio)
    if (typeof matchMedia === 'function') {
      this.reducedQuery = matchMedia('(prefers-reduced-motion: reduce)')
      this.reduced = this.reducedQuery.matches
      this.reducedQuery.addEventListener?.('change', this.onReduced)
    }
  }

  /** Gone: every timer, the frame loop, the listeners - and the audio context is closed. A song the
   *  hand had taken from playing (mid-coast back to speed, say, as the look switches to the cover)
   *  plays on from where the release sought it: the hand only scrubbed it. */
  destroy(): void {
    const resume = this.meantToPlay() || this.resumeTimer !== undefined
    this.dropPress()
    this.endHandover()
    clearTimeout(this.planTimer)
    clearTimeout(this.settleTimer)
    clearTimeout(this.resumeTimer)
    this.resumeTimer = undefined
    clearTimeout(this.clockTimer)
    this.clockTimer = undefined
    cancelFrame(this.raf)
    this.raf = 0
    this.positionOff?.()
    this.positionOff = null
    this.requests.supersede()
    this.decodes.supersede()
    this.post({ type: 'stop' })
    this.motion = { kind: 'still' }
    audioListeners.delete(this.onAudio)
    this.reducedQuery?.removeEventListener?.('change', this.onReduced)
    if (heardListener === this.onHeard) heardListener = null
    closeDeckAudio()
    publish(null)
    if (resume && this.host.song() && !this.host.playing()) this.host.resume()
  }

  /* ----- what Turntable tells it ----- */

  /**
   * Whether the press it is about to start is the deck's: the record can SOUND where it is - the audio
   * context runs, a voice (worklet or script) is ready, and a window of this song covering that point
   * is in it (2.0.0-player.16). Anything less - no voice, no window yet, a refused one, an MP3 - and
   * the press is 2.0.0-player.11's: the song plays on under the finger and is sought where it lets go.
   * Until then (.14) it was only "the context runs", so on a page with no AudioWorklet a press took the
   * record and paused the song with nothing to sound.
   *
   * Except a record the deck has coasting or coming back to speed, with a voice ready: the hand that
   * flicked it paused the song already, so there is nothing for .11's path to play on - the press
   * catches it where the platter is, as .14 did, silent until the window there arrives (handWindow
   * sounds it then). Out of the window is where a backwards flick goes, the next window still on its
   * way (review of 2.0.0-player.16: taken down .11's path, the coast ran on under the finger).
   */
  live(): boolean {
    const motion = this.motion
    if (motion.kind === 'plan' && (motion.role === 'coast' || motion.role === 'handover') && voiceReady()) return true
    return this.sounding(this.recordAt())
  }

  /** Whether the record has been taken by the press under way (the song paused under it). */
  taken(): boolean {
    return !!this.press?.taken
  }

  /** The song's position the record was taken at: what the hand's turn counts from. */
  anchor(): number {
    return this.press?.anchor ?? this.host.position()
  }

  /** The turntable shows - the screen open and the page in sight - or doesn't. Hidden, the audio
   *  context is suspended, the frame loop stops and no window is asked for. */
  setShowing(showing: boolean): void {
    if (showing === this.showing) return
    this.showing = showing
    if (showing) {
      //? a hide's suspend still waiting on a resume no longer applies: it shows (and stays suspended
      //? until a tap, if it was)
      sleepOnceRunning = false
      this.since = now()
      this.fetched = 0
      //? and how it keeps up, counted afresh too
      this.frames = this.slowFrames = this.worstFrameMs = this.notBack = 0
      this.backMs = this.motorMs = null
      soundHealth.blocks = soundHealth.lateBlocks = soundHealth.worstBlockMs = soundHealth.interruptions = 0
      soundHealth.peaksHeld = soundHealth.samplesHeld = soundHealth.deepestHoldDb = 0
      this.lastFetchAt = 0
      this.positionOff = this.host.onPosition(this.onPosition)
      this.keepHere()
      this.loop()
      this.keepClock()
    } else {
      this.positionOff?.()
      this.positionOff = null
      cancelFrame(this.raf)
      this.raf = 0
      this.keepClock()
      //? a window still being fetched is let go; one in hand (being decoded) is kept, and handed on
      if (this.pending?.stage === 'fetch') {
        this.requests.supersede()
        this.pending = null
      }
      sleepDeckAudio()
    }
    this.report()
  }

  /** You > Playback's "Pause winds the record down". */
  setWindDown(on: boolean): void {
    this.windDown = on
  }

  /**
   * The player's speed changed (2.0.0-player.39) - the fader, the chip, or the turntable mounting on a
   * speed set before. A platter turning at speed carries on from where it is at the new one; one
   * spinning up heads for the new one from where it has got to. A run back to speed after a let-go keeps
   * the speed it was let go at - the song was sought to where that lands - and turns at the new one once
   * it is there. Anything else (a hand, a coast, a wind-down) knows no motor's speed.
   */
  speedChanged(speed: number): void {
    if (!(speed > 0) || speed === this.speed) return
    const motion = this.motion
    if (motion.kind === 'turning') this.motion = { kind: 'turning', since: now(), from: this.angleNow() }
    const spinningUp = motion.kind === 'plan' && motion.role === 'spin' && motion.plan.target > 0
    const v = spinningUp ? this.speedNow() : 0
    this.speed = speed
    if (spinningUp) this.spin(motor(0, v, 0, speed), 'spin')
    this.loop()
  }

  /** The song started or stopped playing. Started: the platter spins up (unless the deck itself is
   *  bringing it to speed). Stopped by anything but the deck: it spins down - once the pause has
   *  lasted PAUSE_SETTLE_MS, since a song change pauses for a moment. */
  playingChanged(playing: boolean): void {
    if (playing === this.wasPlaying) return
    this.wasPlaying = playing
    clearTimeout(this.settleTimer)
    this.settleTimer = undefined
    if (playing) {
      if ((this.press && this.press.taken) || this.motion.kind === 'turning') return
      const motion = this.motion
      if (motion.kind === 'plan' && motion.role === 'handover') {
        //? played before the coast got back to speed (a tap on the record, the transport's play): the
        //? song is playing, so the coast is over - its sound fades, and nothing plays it again
        clearTimeout(this.planTimer)
        this.planTimer = undefined
        this.motion = { kind: 'turning', since: now(), from: this.angleNow() }
        if (motion.sounding) this.post({ type: 'fade', seconds: HANDOVER_FADE_S })
        this.host.show(null, false)
        this.loop()
        return
      }
      //? played during a coast or a wind-down: its sound stops, and the platter is pulled back up from
      //? where it is
      if (motion.kind === 'plan' && motion.sounding) this.post({ type: 'stop' })
      if (motion.kind === 'plan') this.host.show(null, false)
      this.spin(motor(0, this.speedNow(), 0, this.speed), 'spin')
      this.keepHere()
      return
    }
    if ((this.press && this.press.taken) || this.motion.kind !== 'turning') return
    this.settleTimer = setTimeout(() => {
      this.settleTimer = undefined
      if (!this.host.playing() && !this.press?.taken && this.motion.kind === 'turning') this.spin(coast(0, this.speed, 0), 'spin')
    }, PAUSE_SETTLE_MS)
  }

  /** The song changed: whatever the deck had of the one before - a press, a coast, its window - goes,
   *  and nothing is sought for it. A song the hand had taken from playing - a press, or a coast back to
   *  speed, when Next or Previous changed it - plays on: the player loads the next one paused, because
   *  the hand paused this one, and the hand only scrubbed (after SONG_CHANGE_SETTLE_MS, if nothing has
   *  played it by then). Told the same song again (the turntable mounting on it), nothing happens. */
  songChanged(id: string): void {
    if (id === this.songId) return
    this.songId = id
    const resume = this.meantToPlay() || this.resumeTimer !== undefined
    clearTimeout(this.resumeTimer)
    this.resumeTimer = undefined
    this.dropPress()
    this.stilled = false
    this.endHandover()
    clearTimeout(this.planTimer)
    this.planTimer = undefined
    this.post({ type: 'stop' })
    this.window = null
    this.fetchedWindow = null
    this.decodedWindow = null
    this.requests.supersede()
    this.decodes.supersede()
    this.pending = null
    this.failed = null
    this.wanted = null
    const angle = this.angleNow()
    this.angle = angle
    this.motion = this.host.playing() ? { kind: 'turning', since: now(), from: angle } : { kind: 'still' }
    this.host.show(null, false)
    //? the platter spins up when the play takes ('play' -> playingChanged), and not if it is refused
    if (resume && id) {
      this.resumeTimer = setTimeout(() => {
        this.resumeTimer = undefined
        if (this.songId === id && !this.host.playing() && !this.press?.taken) this.host.resume()
      }, SONG_CHANGE_SETTLE_MS)
    }
    this.keepHere()
    this.loop()
    this.report()
  }

  /** A press on the record (live). It may be a tap - the click plays or pauses, a coasting or winding
   *  down record included, which carries on meanwhile - so the record is taken only as the press moves
   *  past a tap (Turntable calls takeOver) or rests longer than one (HOLD_MS). */
  pressed(time: number): void {
    this.dropPress()
    //? a new press before the song was back: that let-go isn't timed
    this.letGo = null
    this.press = { taken: false, anchor: 0, at: 0, intent: 'pause', samples: [{ time, turned: 0 }], since: time, early: [] }
    this.holdTimer = setTimeout(() => {
      this.holdTimer = undefined
      if (this.press && !this.press.taken) {
        this.takeOver()
        this.host.grabbed()
      }
    }, HOLD_MS)
  }

  /**
   * A press the deck doesn't take - one begun before the record can sound where it is (`live()`
   * false), which Turntable handles as 2.0.0-player.11 did: the record stops under the finger, as .11's
   * spin did, and turns on from where it was held once the finger lets go (`held` false). A spin-up or
   * spin-down caught under it ends where it was held - and so does whatever else the deck had it doing
   * (review of 2.0.0-player.16: left running, its timer moved the face a long way at the release, and a
   * window landing under the still finger sounded it): a wind-down without its sound (an MP3, the
   * setting off) stops there, the song where it paused; a coast or a run back to speed it couldn't
   * catch (its context suspended by a hide since) goes quiet - nothing shown, nothing heard - and a run
   * back to speed plays the song now, .11's song playing on under the finger, from where its release
   * sought it. Pressed, the window where the record is is asked for - at once if a voice is ready to put
   * it in, else as soon as one is (`wanted`) - since a paused song has none until it is pressed, so the
   * next press there can be the deck's.
   */
  holdStill(held: boolean): void {
    if (held === this.stilled) return
    if (held) {
      this.angle = this.angleNow()
      this.stilled = true
      this.host.turnFace(this.angle)
      const motion = this.motion
      if (motion.kind === 'plan' && motion.role !== 'spin') {
        clearTimeout(this.planTimer)
        this.quieten(motion)
        //? its end, now: still where it is held - or, a run back to speed, turning and the song played
        this.planEnded(motion)
      }
      this.keep(this.recordAt())
      return
    }
    this.stilled = false
    const motion = this.motion
    if (motion.kind === 'turning') this.motion = { kind: 'turning', since: now(), from: this.angle }
    else if (motion.kind === 'plan' && motion.role === 'spin') {
      clearTimeout(this.planTimer)
      this.planTimer = undefined
      this.motion = this.host.playing() ? { kind: 'turning', since: now(), from: this.angle } : { kind: 'still' }
    }
    this.loop()
  }

  /**
   * The hand moved inside a tap's few pixels, the record not taken yet (2.0.0-player.40): at `time` (the
   * sample's own, ms) it had turned the record by `turned` since the press (radians), which moves the song by
   * `offset` (seconds). Kept, and nothing else - it may yet be a tap - so a quick grab is heard from the press.
   */
  touched(time: number, turned: number, offset: number): void {
    const press = this.press
    if (!press || press.taken) return
    const early = press.early
    const last = early[early.length - 1]
    if (time < (last?.time ?? press.since)) return
    if (last && time === last.time) early.pop()
    early.push({ time, turned, offset })
  }

  /**
   * The record taken. Turning at speed under the song: the song pauses (the player's own toggle,
   * through the host) and the record's sound starts at its position, at its own speed if it was
   * playing. Coasting, coming back to speed or winding down: caught where the platter is, its sound
   * carrying on from there, and whether the song is meant to play kept from what it was doing. Either
   * way the hand has it from here - the path the voice follows is the hand's from `time` (the pointer
   * event's own time, ms - or now, for a press that rested HOLD_MS).
   *
   * A QUICK GRAB (`quick`: the move at `time` crossed a tap's few pixels - 2.0.0-player.40) is taken from the
   * PRESS: the record where it was as the finger went down - a playing song where it was then, at its speed,
   * though it played on under the slop until now (the tap's price) and pauses only now; a coast where the
   * plan had it - with the take stamped at the press's own moment and every sample the hand made since
   * (touched) handed to the voice after it, in order, so the voice, HAND_DELAY_S behind, plays the hand from
   * the press. Its turn counts from the press (Turntable keeps the offset) and the time line follows; the face
   * carries on from where it was drawn as the slop was crossed (the platter's angle then, less the hand's turn
   * Turntable adds from now), so it doesn't jump. No further back than TAKE_BACK_S before now
   * (SCRIPT_TAKE_BACK_S on the main thread): an older press is taken from its oldest sample within it - a still
   * record at the hand's place then; a moving one (a playing song, a coast) where it had got to on its own by
   * then, the voice having perhaps already played it there, so the hand carries on from that place, and its
   * join with the song, or its path from the coast's, is as a take at the crossing's was.
   * Returns where the hand's turn counts from: the record at the press (or the take) - or, a moving record past
   * the reach, its place at that sample less the hand's turn by then.
   */
  takeOver(time: number = now(), quick = false): number {
    const press = this.press
    if (!press) return this.host.position()
    if (press.taken) return press.anchor
    clearTimeout(this.holdTimer)
    this.holdTimer = undefined
    clearTimeout(this.settleTimer)
    this.settleTimer = undefined
    const motion = this.motion
    //? a quick grab from the press; anything else from `time`, as ever
    const since = quick && press.since < time ? press.since : time
    //? the moments since then the voice can be told of: the press, and the hand's samples inside the slop - the
    //? take at the oldest within TAKE_BACK_S of now (the crossing's own at the least), the rest after it
    const moments = since < time ? [{ time: since, turned: 0, offset: 0 }, ...press.early.filter((sample) => sample.time > since && sample.time <= time)] : [{ time, turned: 0, offset: 0 }]
    //? the crossing itself among them (Turntable tells it, touched) - or, untold, as the last the hand said
    const lastMoment = moments[moments.length - 1]!
    if (lastMoment.time < time) moments.push({ ...lastMoment, time })
    const reach = now() - (audio.voice?.kind === 'script' ? SCRIPT_TAKE_BACK_S : TAKE_BACK_S) * 1000
    let first = moments.findIndex((moment) => moment.time >= reach)
    if (first < 0) first = moments.length - 1
    const from = moments[first]!
    //? the face carries on from where it is drawn now (Turntable adds the hand's turn since the press from here
    //? on, the turn it had at the crossing included), so it doesn't jump as the record is taken - a quick grab's;
    //? a press that rested HOLD_MS, at its own moment, as ever
    const angle = quick ? this.angleNow() - (lastMoment.turned * 180) / Math.PI : this.angleAt(since)
    //? where the record is at `from`, the take's moment: a still record where the hand had turned it since the
    //? press; a moving one where it got to on its own - at the press itself, within reach; past it, where it
    //? had got to by `from`, which the voice may have played already (2.0.0-player.40's review: from the press,
    //? a coast's path stepped back and a playing song's join came later), so the hand carries on from there
    let at: number
    let rate: number
    let taking: boolean
    if (motion.kind === 'plan' && motion.role !== 'spin') {
      clearTimeout(this.planTimer)
      this.planTimer = undefined
      this.endHandover()
      const { v } = planAt(motion.plan, (from.time - motion.since) / 1000)
      at = this.planHasRecord(motion) ? this.recordAt(from.time) : this.recordAt(since) + from.offset
      press.intent = motion.role === 'handover' ? 'play' : 'pause'
      rate = motion.quiet ? 0 : voiceRate(v)
      taking = !motion.sounding
    } else {
      const playing = this.host.playing()
      //? a song changed under the hand a moment ago, about to be played (songChanged): meant to play
      const pending = this.resumeTimer !== undefined
      clearTimeout(this.resumeTimer)
      this.resumeTimer = undefined
      //? a song playing on under the press: where it was at `from` (the press, within reach), at its speed - the
      //? very line a take now would have it heard on, so the record's sound joins the song as it did
      const position = this.host.position()
      at = playing ? Math.max(0, position - (this.speed * Math.max(0, time - from.time)) / 1000) : position + from.offset
      if (playing) this.host.hold()
      press.intent = playing || pending ? 'play' : 'pause'
      rate = playing ? this.speed : 0
      taking = true
    }
    //? where the hand's turn counts from (Turntable's `anchor() + offset`): the take's place less its turn by then
    const anchor = at - from.offset
    if (taking && this.sounding(at)) this.take(at, rate, from.time)
    press.taken = true
    press.anchor = anchor
    press.at = at
    //? and the hand's samples since the press are the hand's - its speed as it lets go counts them too
    if (since < time) press.samples = [{ time: since, turned: 0 }, ...moments.slice(1).map(({ time: when, turned }) => ({ time: when, turned }))]
    this.angle = angle
    this.motion = { kind: 'hand' }
    //? the hand has the record here, then: the path's first sample of it (a hand that rests sends no more,
    //? and the record stops there) - and each sample since, but the one at `time`, which the hand's own
    //? call that follows sends (hand)
    this.post({ type: 'hand', at, time: this.stamp(from.time) })
    for (let i = first + 1; i < moments.length; i++) {
      const moment = moments[i]!
      if (moment.time >= time) break
      press.at = anchor + moment.offset
      this.post({ type: 'hand', at: press.at, time: this.stamp(moment.time) })
    }
    this.keep(press.at)
    this.loop()
    return anchor
  }

  /**
   * The hand moved: at `time` - the pointer sample's own (its event's timeStamp, or one of its coalesced
   * events', in ms: when the finger was there, not when the handler ran) - it had turned the record by
   * `turned` since the press (radians, as lib/turntable counts it), which puts the song at `at` (seconds).
   * Each sample goes to the voice as it comes, a knot of the path it plays (2.0.0-player.24) - never one
   * drive a frame. A sample older than the last is dropped; one of the same moment replaces it.
   */
  hand(time: number, turned: number, at: number): void {
    const press = this.press
    if (!press?.taken) return
    const last = press.samples[press.samples.length - 1]
    if (last && time < last.time) return
    if (last && time === last.time) press.samples.pop()
    press.samples.push({ time, turned })
    //? only the last moment of the hand counts: the release's speed
    while (press.samples.length > 2 && time - press.samples[0]!.time > 4 * VELOCITY_WINDOW_MS) press.samples.shift()
    press.at = at
    this.post({ type: 'hand', at, time: this.stamp(time) })
    if (!this.covers(at, 0)) this.keep(at)
    this.loop()
  }

  /**
   * The hand let go ('up') or the system took the touch ('cancel'). Let go of a record it took: the
   * platter carries on at the hand's speed - back to speed under the motor for a song that was
   * playing, to a stop under friction for one that wasn't - and Turntable seeks the song NOW to where
   * that ends (`seek`), and plays it at once (`play`) when there is no coast to wait for. A cancel
   * seeks nowhere; a song it paused plays on.
   */
  release(time: number, how: 'up' | 'cancel'): Released {
    const press = this.press
    clearTimeout(this.holdTimer)
    this.holdTimer = undefined
    this.press = null
    if (!press || !press.taken) return { seek: null, play: false }
    //? what the hold was like (its frames, the main thread's blocks) is told as it ends
    this.report()
    const song = this.host.song()
    const length = song?.length ?? 0
    if (how === 'cancel') {
      this.post({ type: 'stop' })
      if (press.intent === 'play') {
        this.host.resume()
        this.spin(motor(0, 0, 0, this.speed), 'spin')
      } else {
        this.motion = { kind: 'still' }
      }
      this.host.show(null, false)
      return { seek: null, play: false }
    }
    //? the hand's speed up to its last sample, by the samples' own times - unless it rested before letting go
    const speed = releaseSpeed(press.samples, time)
    //? and the plan from the moment of that sample, where it had the record: a lift up to RELEASE_TAIL_MS
    //? after it is the hand still moving at that speed - from the release's own time, the plan would have
    //? the record stand still for the gap, and the sound dropped almost to nothing as it let go (review of
    //? 2.0.0-player.24: to 0.07x on a flick released a frame after its last move). After a rest, from the
    //? release: the record was held still meanwhile
    const last = press.samples[press.samples.length - 1]!.time
    const since = time - last <= RELEASE_TAIL_MS ? Math.min(time, last) : time
    if (press.intent === 'play') {
      const plan = motor(press.at, speed, length, this.speed)
      if (this.reduced || plan.duration <= RESUME_IN_GESTURE_S) {
        //? nothing to wait for (or nothing to animate): played from there in this very gesture
        this.post({ type: 'stop' })
        this.motion = { kind: 'turning', since: now(), from: this.angleNow() }
        this.host.show(null, false)
        this.loop()
        this.letGo = { at: plan.x, since: now(), motor: 0 }
        return { seek: plan.x, play: true }
      }
      this.letGo = { at: plan.x, since: now(), motor: plan.duration * 1000 }
      this.startPlan(plan, 'handover', press.at, this.sounding(press.at), since)
      this.keepPath(plan)
      return { seek: plan.x, play: false }
    }
    const plan = coast(press.at, speed, length)
    if (this.reduced || plan.duration === 0) {
      this.post({ type: 'stop' })
      this.motion = { kind: 'still' }
      this.host.show(null, false)
      return { seek: plan.x, play: false }
    }
    this.startPlan(plan, 'coast', press.at, this.sounding(press.at), since)
    this.keepPath(plan)
    return { seek: plan.x, play: false }
  }

  /**
   * A pause asked for on the turntable - the record's tap, the transport's pause on this look - made
   * in the tap, just before the player's own pause. The platter spins down; and with "Pause winds the
   * record down" on, the window covering it and the sound running, the record's sound starts where
   * the song is - at the song's own speed, which is what was being heard, whatever the platter's
   * spin-up had reached - and winds down with it. Returns where the wind-down stops, which the caller
   * seeks the song to after pausing it - or null for a plain pause, which seeks nothing.
   */
  pausing(): number | null {
    clearTimeout(this.settleTimer)
    this.settleTimer = undefined
    clearTimeout(this.resumeTimer)
    this.resumeTimer = undefined
    this.wasPlaying = false
    if (this.press?.taken) return null
    const song = this.host.song()
    const at = this.host.position()
    if (this.reduced) {
      this.angle = this.angleNow()
      this.motion = { kind: 'still' }
      return null
    }
    const plan = coast(at, this.speed, song?.length ?? 0)
    if (plan.duration === 0) {
      //? at the very end of the song: nothing left to wind down into
      this.angle = this.angleNow()
      this.motion = { kind: 'still' }
      return null
    }
    const sounding = this.windDown && this.sounding(at) && this.covers(at, plan.x - at)
    if (sounding) this.take(at, this.speed)
    this.startPlan(plan, 'winddown', at, sounding)
    return sounding ? plan.x : null
  }

  /**
   * A play asked for on the turntable - the record's tap, the transport's play - made in the tap, just
   * before the player's own play: where the record is now when it is coasting, coming back to speed, or
   * winding down with its sound, which the caller seeks the song to first - so the song carries on
   * from what was heard, not from where the coast was sought to land. Null otherwise (seek nothing).
   */
  resuming(): number | null {
    //? the tap plays it: a song change's own play, still to come, is the tap's now
    clearTimeout(this.resumeTimer)
    this.resumeTimer = undefined
    const motion = this.motion
    if (motion.kind !== 'plan' || motion.quiet || motion.role === 'spin') return null
    if (motion.role === 'winddown' && !motion.sounding) return null
    const x = this.heardNow() ?? planAt(motion.plan, (now() - motion.since) / 1000).x
    //? the seek it asks for is the deck's own, not something else moving the song
    motion.sought = x
    return x
  }

  /** The arm was taken: the record's sound stops, and the deck stops showing where the platter is - the
   *  arm shows where the finger has it; a coast back to speed still plays the song when it gets there,
   *  from wherever the arm puts it. */
  armTaken(): void {
    const motion = this.motion
    if (motion.kind === 'plan' && motion.role !== 'spin') this.quieten(motion)
  }

  /* ----- the platter ----- */

  /** Where the record is in the song: where a coast or a run back to speed has the platter - a
   *  wind-down too, when it sounds - or the song's own position. A wind-down that made no sound left
   *  the song where it paused, not where the platter got to; and a plan something else sought (quiet)
   *  is where that put it. */
  private recordAt(time: number = now()): number {
    const motion = this.motion
    if (motion.kind === 'plan' && this.planHasRecord(motion)) return planAt(motion.plan, (time - motion.since) / 1000).x
    return this.host.position()
  }

  /** Whether a plan has the record where it has the platter (recordAt): not a spin, nor quiet, nor a wind-down
   *  that made no sound. */
  private planHasRecord(motion: PlanMotion): boolean {
    return motion.role !== 'spin' && !motion.quiet && (motion.sounding || motion.role !== 'winddown')
  }

  /** Whether the song is meant to be playing when the deck lets go of it: the hand took it from
   *  playing, and hasn't given it back yet. */
  private meantToPlay(): boolean {
    const motion = this.motion
    return (!!this.press?.taken && this.press.intent === 'play') || (motion.kind === 'plan' && motion.role === 'handover')
  }

  private speedNow(): number {
    const motion = this.motion
    if (motion.kind === 'turning') return this.speed
    if (motion.kind === 'plan') return planAt(motion.plan, (now() - motion.since) / 1000).v
    return 0
  }

  private angleNow(): number {
    return this.angleAt(now())
  }

  /** The face's angle at page time `time` (ms) - now, or a quick grab's press (2.0.0-player.40). */
  private angleAt(time: number): number {
    const motion = this.motion
    if (this.reduced || this.stilled) return this.angle
    if (motion.kind === 'turning') return motion.from + (DEGREES_PER_SECOND * this.speed * (time - motion.since)) / 1000
    if (motion.kind === 'plan') return motion.from + degreesFor(planAt(motion.plan, (time - motion.since) / 1000).x - motion.x0)
    return this.angle
  }

  /** A visual movement only - the spin-up of a play, the spin-down of a pause from elsewhere. */
  private spin(plan: Plan, role: 'spin'): void {
    if (this.reduced) {
      this.motion = role === 'spin' && plan.target > 0 ? { kind: 'turning', since: now(), from: this.angle } : { kind: 'still' }
      return
    }
    this.startPlan(plan, role, plan.phases[0] ? planAt(plan, 0).x : 0, false)
  }

  /** A plan from page time `since` (ms - the hand's last sample for a release moments after it, the
   *  release's own after a rest, or now): sounding, its start is the voice's path from that moment, as
   *  well as each frame's place on it - and the timer for its end is shortened by however long ago that
   *  was. */
  private startPlan(plan: Plan, role: Role, x0: number, sounding: boolean, since: number = now()): void {
    const from = this.angleNow()
    clearTimeout(this.planTimer)
    //? a wind-down without its sound leaves the song where it paused: nothing seeks it to the end
    const sought = role === 'winddown' && !sounding ? x0 : plan.x
    this.motion = { kind: 'plan', role, plan, since, from, x0, sounding, sought, quiet: false }
    const motion = this.motion
    if (sounding) this.drive(motion, since)
    //? the plan's end on a timer, not the frame loop: a hidden page draws nothing, but a coast back to
    //? speed must still play the song when it gets there
    this.planTimer = setTimeout(() => this.planEnded(motion), Math.max(0, plan.duration * 1000 - (now() - since)))
    this.loop()
  }

  /** The voice told where a sounding plan has the record at page time `time` (ms) - and how fast, and
   *  how that is changing, so it follows the curve between frames - stamped by the one clock. */
  private drive(motion: PlanMotion, time: number): void {
    const t = (time - motion.since) / 1000
    const { x, v } = planAt(motion.plan, t)
    const accel = t < motion.plan.duration ? acceleration(v, motion.role === 'handover' || (motion.role === 'spin' && motion.plan.target > 0), motion.plan.target) : 0
    const stamped = this.stamp(time)
    this.post({ type: 'drive', at: x, rate: voiceRate(v), accel: voiceRate(accel), time: stamped, until: stamped + DRIVE_FOR_S })
  }

  private planEnded(motion: Motion): void {
    this.planTimer = undefined
    if (this.motion !== motion || motion.kind !== 'plan') return
    const angle = this.angleNow()
    if (motion.role === 'handover') {
      //? at speed: the song plays - after the tap; the record's sound holds its speed until it does -
      //? unless the song was sought somewhere else meanwhile (quiet: there is nothing to hold for)
      this.motion = { kind: 'turning', since: now(), from: angle }
      this.host.show(null, false)
      this.handOver(motion.plan.x, motion.sounding && !motion.quiet, motion.since + motion.plan.duration * 1000)
      this.host.resume()
      //? a play iOS refuses ("Tap play to start") leaves the song paused: the platter spins down
      //? rather than turning on beside it. A play that takes clears this (playingChanged)
      clearTimeout(this.settleTimer)
      this.settleTimer = setTimeout(() => {
        this.settleTimer = undefined
        if (!this.host.playing() && !this.press?.taken && this.motion.kind === 'turning') this.spin(coast(0, this.speed, 0), 'spin')
      }, HANDOVER_MAX_S * 1000)
    } else if (motion.role === 'spin' && motion.plan.target > 0) {
      this.motion = this.host.playing() ? { kind: 'turning', since: now(), from: angle } : { kind: 'still' }
      this.angle = angle
    } else {
      this.angle = angle
      this.motion = { kind: 'still' }
      if (motion.sounding) this.post({ type: 'stop' })
      this.host.show(null, false)
    }
    this.loop()
  }

  /** The record's sound holds the song's own speed (the player's, 2.0.0-player.39) from `at` - where the
   *  plan ended, at page time `time` (ms) - until the song is really playing - its position past `at` -
   *  then fades; HANDOVER_MAX_S at most. A position nowhere near `at` (the song sought elsewhere as it
   *  started) ends it as well: there is nothing to hand over to. */
  private handOver(at: number, sounding: boolean, time: number): void {
    this.endHandover()
    if (!sounding) return
    const stamped = this.stamp(time)
    this.post({ type: 'drive', at, rate: voiceRate(this.speed), time: stamped, until: stamped + HANDOVER_MAX_S })
    const done = () => {
      this.endHandover()
      this.post({ type: 'fade', seconds: HANDOVER_FADE_S })
    }
    //? asked as the player reports its position (about four times a second) AND every frame the platter
    //? turns (onFrame): on the report alone the record's sound played on up to a quarter of a second over
    //? the song it had handed back to, the delay behind it - an echo after every let-go (2.0.0-player.28)
    const judge = (seconds: number) => {
      if (Math.abs(seconds - at) > SOUGHT_ELSEWHERE_S || (this.host.playing() && seconds > at + 0.02)) done()
    }
    this.handoverJudge = judge
    this.handoverOff = this.host.onPosition(judge)
    this.handoverTimer = setTimeout(done, HANDOVER_MAX_S * 1000)
  }

  private endHandover(): void {
    this.handoverOff?.()
    this.handoverOff = null
    this.handoverJudge = null
    clearTimeout(this.handoverTimer)
    this.handoverTimer = undefined
  }

  /** The rest of a coast, a run back to speed or a wind-down without its sound, and without showing
   *  where the platter is: the arm took it, or something else sought the song. Its end still comes. */
  private quieten(motion: PlanMotion): void {
    motion.quiet = true
    if (motion.sounding) {
      //? in place: the plan's end still comes, by the timer that knows it
      motion.sounding = false
      this.post({ type: 'stop' })
    }
    this.host.show(null, false)
  }

  private dropPress(): void {
    clearTimeout(this.holdTimer)
    this.holdTimer = undefined
    this.press = null
  }

  /** The frame loop: running while something moves, the turntable shows and motion is allowed. */
  private loop(): void {
    if (this.raf || !this.showing) return
    if (!this.moving()) {
      this.host.turnFace(this.angleNow())
      return
    }
    this.raf = frame(this.onFrame)
  }

  private moving(): boolean {
    if (this.press?.taken) return true
    if (this.reduced || this.stilled) return false
    return this.motion.kind === 'turning' || this.motion.kind === 'plan'
  }

  private readonly onFrame = (time: number) => {
    this.raf = 0
    if (!this.showing) return
    this.host.turnFace(this.angleNow())
    const press = this.press
    const motion = this.motion
    //? the clock read once a frame while anything moves - and on the deck's own timer whatever the record
    //? does (keepClock): a still record runs no frames, and its grab must find the mapping settled too
    this.readClock()
    //? the song's own position, read once a frame while a handover or a let-go waits on it
    if (this.handoverJudge || this.letGo) {
      const seconds = this.host.position()
      this.handoverJudge?.(seconds)
      this.noteBack(seconds)
    }
    if (press?.taken) {
      if (this.heldFrame) {
        const gap = time - this.heldFrame
        this.frames += 1
        if (gap > SLOW_FRAME_MS) this.slowFrames += 1
        if (gap > this.worstFrameMs) this.worstFrameMs = gap
      }
      this.heldFrame = time
    } else this.heldFrame = 0
    if (press?.taken) {
      //? the hand's samples went to the voice as they came (hand): only what it is heard playing to show
      this.host.show(this.heardNow() ?? press.at, true)
    } else if (motion.kind === 'plan') {
      const t = (time - motion.since) / 1000
      const { x } = planAt(motion.plan, t)
      //? where the plan has the record at this frame's own time - its place, speed and acceleration - once
      //? that is later than anything the voice was told: a frame's time is when it began, and the release
      //? (or the tap) it follows may have come after that - driven, it would erase the plan's own start and
      //? set it at a moment the plan hadn't begun (review of 2.0.0-player.24)
      if (motion.sounding && time > this.stampedTo) this.drive(motion, time)
      //? a coast running out of the window - sounding or not: the next asked for (asked at the release
      //? already, as a rule - keepPath), and it sounds from where it has got to as it arrives
      if (!motion.quiet && (motion.role === 'coast' || motion.role === 'handover') && !this.covers(x, 0)) this.keep(x)
      if (!motion.quiet) {
        if (motion.role === 'coast' || motion.role === 'handover') this.host.show(this.heardNow() ?? x, true)
        else if (motion.role === 'winddown' && motion.sounding) this.host.show(this.heardNow() ?? x, false)
      }
      if (t >= motion.plan.duration) this.planEnded(motion)
    }
    if (this.moving()) this.raf = frame(this.onFrame)
  }

  /* ----- the record's sound ----- */

  /** What the voice says it is playing, extrapolated by its rate - while it is sounding, and what it
   *  said is fresh. */
  private heardNow(): number | null {
    const heard = this.heard
    if (!heard || heard.gain < 0.5) return null
    const age = now() - heard.at
    if (age > HEARD_FRESH_MS) return null
    return heard.pos + (heard.rate * age) / 1000
  }

  private post(message: VoiceMessage, transfer: Transferable[] = []): void {
    noteForRecording(message)
    try {
      audio.voice?.post(message, transfer)
    } catch {
      //? a node going away mid-message: nothing to play it on anyway
    }
  }

  /** The voice takes up the record at `at`, moving at `rate`, as of page time `time` (ms). */
  private take(at: number, rate: number, time: number = now()): void {
    const stamped = this.stamp(time)
    this.post({ type: 'take', at, rate, time: stamped, until: stamped + DRIVE_FOR_S })
  }

  /** Whether the voice is following a path of the deck's - a hand, a sounding plan, the handover: the
   *  clock's mapping is held steady meanwhile. */
  private steering(): boolean {
    const motion = this.motion
    return !!this.press?.taken || (motion.kind === 'plan' && motion.sounding) || this.handoverOff !== null
  }

  /**
   * The clock read on the deck's own timer while the turntable shows and its context runs - whatever the
   * record does: every CLOCK_SETTLE_MS while the mapping is young (a context just made or resumed - each
   * state change starts it again; for CLOCK_SETTLE_TICKS readings at most), every CLOCK_TICK_MS once
   * settled - so a press finds it settled, and its readings never go stale through a long rest. Started
   * afresh, or stopped, as either changes: shown or hidden (a real suspend settles later, and the timer
   * stops at the hide), the context's state - and stopped as the deck goes (its timer reading on, with
   * this deck's `steering()`, would let go of a mapping the next turntable's hand holds).
   */
  private keepClock(): void {
    this.clockTicks = 0
    this.armClock()
  }

  private armClock(): void {
    clearTimeout(this.clockTimer)
    this.clockTimer = undefined
    if (!this.showing || !deckAudioRunning()) return
    const settling = !clockSettled(clock) && this.clockTicks < CLOCK_SETTLE_TICKS
    this.clockTimer = setTimeout(this.onClockTick, settling ? CLOCK_SETTLE_MS : CLOCK_TICK_MS)
  }

  private readonly onClockTick = () => {
    this.clockTimer = undefined
    this.readClock()
    this.clockTicks += 1
    this.armClock()
  }

  /** A reading of the audio context's clock against the page's, for the one mapping - and Debug told
   *  when the step it moves by is first seen, or changes. */
  private readClock(): void {
    const context = audio.context
    if (!context) return
    clockReading(clock, now(), context.currentTime, this.steering())
    readSpeaker(context)
    if (Math.abs(clock.step - this.reportedStep) > 1e-4) this.report()
  }

  /** Page time `time` (ms) as the audio context's clock has it (seconds), by the one mapping - never a
   *  `currentTime` read for the message (its steps were the warble). */
  private stamp(time: number): number {
    this.readClock()
    if (time > this.stampedTo) this.stampedTo = time
    return contextTimeAt(clock, time) ?? time / 1000
  }

  /** Whether the record can sound at `at`: the context runs, a voice is ready, and its window covers
   *  that point of this song. */
  private sounding(at: number): boolean {
    return voiceReady() && this.covers(at, 0)
  }

  /** Whether the window in the voice covers `at` and `ahead` seconds after it, for this song. */
  private covers(at: number, ahead: number): boolean {
    const song = this.host.song()
    const window = this.window
    return !!song && !!window && window.song === song.id && at >= window.start && at + Math.max(0, ahead) <= window.end
  }

  /** The song's own playback seen moving again after a let-go: how long that took, for Debug - or that
   *  it never did within the handover's wait. */
  private noteBack(seconds: number): void {
    const letGo = this.letGo
    if (!letGo) return
    const waited = now() - letGo.since
    //? the song moves at the player's speed from there (2.0.0-player.39)
    if (this.host.playing() && seconds > letGo.at + 0.02 && Math.abs(seconds - letGo.at) < SOUGHT_ELSEWHERE_S + (this.speed * waited) / 1000) {
      this.backMs = waited
      this.motorMs = letGo.motor
    } else if (waited > letGo.motor + HANDOVER_MAX_S * 1000) this.notBack += 1
    else return
    this.letGo = null
    this.report()
  }

  private readonly onPosition = (seconds: number) => {
    this.noteBack(seconds)
    const motion = this.motion
    //? the song sought somewhere the deck didn't put it, while a coast, a run back to speed or a
    //? wind-down has the record: Previous restarting it, a key on the arm - the record's sound has
    //? nothing to follow, and the song plays (or waits) from there
    if (motion.kind === 'plan' && motion.role !== 'spin' && !motion.quiet && (this.host.song()?.length ?? 0) > 0
        && Math.abs(seconds - motion.sought) > SOUGHT_ELSEWHERE_S) this.quieten(motion)
    if (this.host.playing() && !this.press) this.keep(seconds)
  }

  /** The window kept for wherever the record is now: the hand's place, the plan's, or the song's. */
  private keepHere(): void {
    const press = this.press
    const motion = this.motion
    if (press?.taken) this.keep(press.at)
    else if (motion.kind === 'plan' && motion.role !== 'spin' && !motion.quiet) this.keep(planAt(motion.plan, (now() - motion.since) / 1000).x)
    else this.keep()
  }

  /** A coast or a run back to speed let go of: the window should cover ALL of where it will go - a
   *  backwards flick runs back past where the window starts - so one that does is asked for now, at
   *  the release, with the whole coast to arrive in, not when the record gets there. */
  private keepPath(plan: Plan): void {
    const { low, high } = reach(plan)
    if (!this.covers(low, high - low)) this.keep(low, high - low)
  }

  /**
   * The window kept ready: while the turntable shows and the song plays - or a hand or a coast has
   * the record, or a press the deck didn't take holds it or wanted it (`wanted`) - one covering `at` (the song's position by
   * default) and, for the playing song, REFRESH_AHEAD_S after it (`span` seconds after it, for
   * keepPath) is asked for when there isn't one - unless one is on its way that will (`pending`), this
   * song has none (not a FLAC, refused, couldn't be decoded), there is nothing yet to decode it with and
   * play it on (no audio context, or no voice ready - the worklet still loading, the script voice yet
   * to play its first block, or neither there: onAudio asks once one is), or the last ask failed under
   * RETRY_MS ago. A refresh ahead of a playhead the window still covers moves on from it,
   * and comes no more often than REFRESH_MIN_MS.
   */
  private keep(at?: number, span?: number): void {
    const song = this.host.song()
    if (!this.showing || !song) return
    const busy = !!this.press || this.stilled || this.wanted === song.id || (this.motion.kind === 'plan' && this.motion.role !== 'spin')
    //? a paused song gets its FIRST window - the one for where it is - as the turntable shows, or as it is
    //? sought somewhere the window doesn't reach, and nothing more (no refreshing ahead: it isn't
    //? going anywhere). Until 2.0.0-player.30 nothing was fetched for a paused song until the record was
    //? turned, so its first turn was always silent (James: "the scrubbing audio doesn't seem to load
    //? ever until after the first scrub")
    const where = at ?? this.host.position()
    const unmet = !this.covers(where, 0)
    if (!this.host.playing() && !busy && !unmet) return
    if (!song.flac) {
      if (this.refused?.song !== song.id) {
        this.refused = { song: song.id, why: `it isn't a FLAC file (it is ${song.kind || 'something else'})` }
        this.report()
      }
      return
    }
    if (this.refused?.song === song.id) return
    if (!audio.voice?.ready || !audio.context || audio.context.state === 'closed') {
      //? a press the deck didn't take, with nothing yet to put its window in - the first turn of a paused
      //? song before any tap: asked for as soon as there is (onAudio), whatever the record does meanwhile
      if (this.stilled) this.wanted = song.id
      return
    }
    this.wanted = null
    if (this.failed?.song === song.id && now() < this.failed.until) return
    const { back, ahead } = windowMargins(this.span?.song === song.id ? this.span.seconds : WINDOW_S)
    const refreshing = span === undefined && this.host.playing() && !busy
    const room = song.length > 0 ? Math.max(0, song.length - where - 0.5) : Infinity
    //? the margin ahead is time for a fetch and a decode, so faster than 1x it is that many more seconds
    //? of the song: at 2x the next window is asked 12 s of it - still 6 s of listening - before the end of
    //? this one, never 3 (review of 2.0.0-player.39); slower, the margin is as it was
    const need = Math.max(0, span ?? (refreshing ? Math.min(ahead * Math.max(1, this.speed), room) : 0))
    if (this.covers(where, need)) return
    const pending = this.pending
    if (pending && pending.song === song.id && where >= pending.from && where + need <= pending.to) return
    const from = Math.max(0, Math.floor((where - back) / WINDOW_GRID_S) * WINDOW_GRID_S)
    if (refreshing && this.covers(where, 0)) {
      if (from <= this.window!.start || now() - this.refreshedAt < REFRESH_MIN_MS) return
      this.refreshedAt = now()
    }
    void this.fetchWindow(song, from)
  }

  private async fetchWindow(song: DeckSong, from: number): Promise<void> {
    const id = song.id
    const request = this.requests.begin()
    //? one window on its way at a time: one still being decoded, or waiting to be, gives way to this
    this.decodes.supersede()
    this.fetchedWindow = null
    this.decodedWindow = null
    this.pending = { song: id, from, to: from + WINDOW_S, stage: 'fetch' }
    this.report()
    try {
      //? the test bench's own windows where it gives them (2.0.0-player.36); deadwax's otherwise
      const got = this.host.window
        ? await this.host.window(song, from, WINDOW_S, request.signal)
        : await scrubWindow(id, from, WINDOW_S, request.signal, song.maxRate ?? null)
      if (!request.current()) return
      const start = got.first / got.rate
      const end = (got.first + got.samples) / got.rate
      this.fetched += got.bytes.byteLength
      this.lastFetchAt = now() - this.since
      //? cut short by deadwax's budget (a hi-res song's) rather than by the song's end: the margins
      //? shrink to suit it (windowMargins)
      const short = end < from + WINDOW_S - 0.01 && !(song.length > 0 && end >= song.length - 0.5)
      this.span = { song: id, seconds: short ? end - start : WINDOW_S }
      this.pending = { song: id, from: start, to: end, stage: 'held' }
      this.fetchedWindow = { song: id, bytes: got.bytes, first: got.first, rate: got.rate }
      this.decode()
    } catch (reason) {
      if (!request.current() || isAbort(reason)) return
      this.pending = null
      if (reason instanceof ApiError && reason.status === 415) {
        this.refused = { song: id, why: reason.detail ?? "deadwax can't make it a window" }
      } else if (reason instanceof ApiError && reason.status === 416) {
        this.failed = { song: id, why: 'deadwax said that is past the end of the song', until: now() + RETRY_MS }
      } else {
        this.failed = { song: id, why: `deadwax didn't send it - ${message(reason)}`, until: now() + RETRY_MS }
      }
    }
    this.report()
  }

  /** A fetched window decoded - once there is an audio context to decode it with - and handed to the
   *  voice once one is ready to hand it to. Only the newest decode counts. */
  private decode(): void {
    const fetched = this.fetchedWindow
    const context = audio.context
    if (!fetched || !context || context.state === 'closed') return
    this.fetchedWindow = null
    const ticket = this.decodes.begin()
    const bytes = fetched.bytes.byteLength
    const done = (buffer: AudioBuffer) => {
      if (!ticket.current()) return
      const song = this.host.song()
      if (!song || song.id !== fetched.song) return
      const channels: Float32Array[] = []
      for (let channel = 0; channel < buffer.numberOfChannels; channel++) channels.push(buffer.getChannelData(channel).slice())
      this.decodedWindow = { song: fetched.song, channels, start: fetched.first / fetched.rate, rate: buffer.sampleRate, bytes }
      this.handWindow()
    }
    const failed = (error: unknown) => {
      if (!ticket.current()) return
      //? the browser can't decode deadwax's window: no sound for this song - said in Debug, in its own
      //? words (WebKit has been known to give none: null)
      this.pending = null
      const words = error ? message(error) : ''
      this.refused = { song: fetched.song, why: `this browser couldn't decode its window - ${words || 'it gave no reason'}` }
      this.report()
    }
    try {
      //? the callback form: older WebKit has no promise from it
      const promise = context.decodeAudioData(fetched.bytes, done, failed) as Promise<AudioBuffer> | undefined
      promise?.catch?.(() => undefined)
    } catch (error) {
      failed(error)
    }
  }

  private handWindow(): void {
    const decoded = this.decodedWindow
    if (!decoded || !audio.voice?.ready) return
    this.decodedWindow = null
    if (this.pending?.song === decoded.song) this.pending = null
    const length = decoded.channels[0]?.length ?? 0
    this.post({ type: 'window', channels: decoded.channels, start: decoded.start, rate: decoded.rate }, decoded.channels.map((channel) => channel.buffer))
    this.window = { song: decoded.song, start: decoded.start, end: decoded.start + length / decoded.rate, bytes: decoded.bytes, decodedAt: decoded.rate }
    //? arrived with the record already in a hand or coasting, silent for want of it: it sounds from here
    const press = this.press
    const motion = this.motion
    if (press?.taken && this.heardNow() === null && this.sounding(press.at)) {
      //? held still from here, where the hand has it - as of its last sample, which put it there, so the
      //? samples on their way since go on from it rather than being older than it
      const time = press.samples[press.samples.length - 1]?.time ?? now()
      this.take(press.at, 0, time)
      this.post({ type: 'hand', at: press.at, time: this.stamp(time) })
    } else if (motion.kind === 'plan' && !motion.sounding && !motion.quiet && (motion.role === 'coast' || motion.role === 'handover')) {
      const { x, v } = planAt(motion.plan, (now() - motion.since) / 1000)
      if (this.sounding(x)) {
        this.take(x, voiceRate(v))
        //? the same motion, changed in place: its end's timer knows it by identity
        motion.sounding = true
      }
    }
    this.report()
  }

  private readonly onHeard = (heard: VoiceHeard) => {
    const at = now()
    this.heard = { ...heard, at }
    //? what the limiter held since the last report, come in after it - a hold's last moments, a coast:
    //? told once the deck no longer steers the sound, at most every HEALTH_REPORT_MS (review of
    //? 2.0.0-player.35). Never while it steers: a report re-renders the page, and under a hand on the
    //? main thread that is the voice's own time
    if (healthMoved && !this.steering() && at - this.reportedAt >= HEALTH_REPORT_MS) this.report()
  }

  private readonly onAudio = () => {
    //? a context made, resumed, suspended; a voice ready: what was waiting goes on - and the
    //? window is asked for now, if none was for want of somewhere to put it; the clock read on the
    //? deck's timer while it runs (its mapping started again by the state change: quickly, to settle)
    this.decode()
    this.handWindow()
    this.keepHere()
    this.keepClock()
    this.report()
  }

  private readonly onReduced = () => {
    this.reduced = !!this.reducedQuery?.matches
    this.loop()
  }

  /* ----- for Info > Debug ----- */

  private health(): DeckHealth {
    return {
      ...soundHealth,
      frames: this.frames, slowFrames: this.slowFrames, worstFrameMs: this.worstFrameMs,
      backMs: this.backMs, motorMs: this.motorMs, notBack: this.notBack,
    }
  }

  private report(): void {
    const song = this.host.song()
    const context = audio.context
    const state: DeckReport['context'] = audio.missing ?? (audio.problem ? 'failed'
      : !context || context.state !== 'running' ? 'none' : audio.loading || !audio.voice?.ready ? 'starting' : 'running')
    const window = this.window && song && this.window.song === song.id ? this.window : null
    publish({
      context: state,
      problem: audio.problem,
      voice: audio.voice?.kind ?? null,
      voiceWhy: audio.voice?.kind === 'script' ? audio.why : null,
      window: window ? { start: window.start, end: window.end, kind: song?.kind || 'FLAC', decodedAt: window.decodedAt, bytes: window.bytes } : null,
      loading: !!this.pending,
      refused: this.refused && song && this.refused.song === song.id ? this.refused.why : null,
      failed: this.failed && song && this.failed.song === song.id ? this.failed.why : null,
      fetched: this.fetched,
      lastFetchAt: this.lastFetchAt,
      clockStep: clock.step,
      health: this.health(),
      latency: deckLatency(),
    })
    this.reportedStep = clock.step
    this.reportedAt = now()
    healthMoved = false
  }
}

/** How often the voice reports, for the docs and the sim. */
export const HEARD_PER_SECOND = REPORTS_PER_SECOND
