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
 *    finger rests. A press on a coasting record takes it at once.
 *  - Let go, the hand's speed over its last ~90 ms becomes the platter's (lib/platter). A song that was
 *    playing: the motor takes the platter back to speed - stopping it first, from a backwards flick -
 *    and the song is sought AT THE RELEASE to where the platter will be at speed (the physics is exact,
 *    so that is known then, and the element has the whole coast to buffer); at speed the song plays
 *    (`resume`, after the tap - iOS allows it on an element a tap started; if it refuses, the player's
 *    own "Tap play to start" says so, and the platter spins down rather than turning beside a paused
 *    song), and the record's sound holds speed 1 until the song is really playing, then fades out
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
 * THE WINDOW is kept ready while the turntable shows and the song plays - once a tap has started the
 * sound, so there is something to decode it with and play it on: WINDOW_S of it, from a little before
 * the playhead, asked again as the playhead nears its end, and on demand when a hand or a coast goes
 * outside it. One is on its way at a time, from the ask until it is in the voice (`pending`), so
 * nothing asks for it again meanwhile. A hi-res song's windows come back shorter (deadwax's budget), and
 * the margins shrink with them (windowMargins), so each still moves on by most of its length. Its cost
 * - bytes fetched since the turntable showed - is in Info > Debug.
 */

import { isAbort, latestOnly } from '../lib/latest'
import {
  REPORTS_PER_SECOND, VOICE_PROCESSOR, newVoiceState, renderVoice, voiceCommand, voiceReport, voiceWorkletSource,
  type DeckReport, type VoiceHeard, type VoiceMessage,
} from '../lib/deckVoice'
import {
  DEGREES_PER_SECOND, VELOCITY_WINDOW_MS, acceleration, coast, degreesFor, handSpeed, motor, phaseAt, planAt, voiceRate,
  type HandSample, type Plan,
} from '../lib/platter'
import { ApiError } from '../api/http'
import { scrubWindow } from './api'

/** A press resting longer than a tap takes the record (and pauses a playing song), in ms. */
export const HOLD_MS = 250
/** How much of the song a window holds, how far before the playhead it starts, on what grid. A
 *  window is asked again whole, so what that costs over the song's own stream is WINDOW_S over the
 *  stretch the playhead crosses before the next (WINDOW_S - WINDOW_BACK_S - REFRESH_AHEAD_S): 40 over
 *  30, a third more than the song itself while the turntable shows and the song plays. */
export const WINDOW_S = 40
export const WINDOW_BACK_S = 4
export const WINDOW_GRID_S = 2
/** The window is asked again once the playhead is this close to its end, in seconds. */
export const REFRESH_AHEAD_S = 6
/** Asked again ahead of a playhead the window still covers no more often than this, in ms - a floor
 *  under the refresh, whatever length of window deadwax sends. */
export const REFRESH_MIN_MS = 3000
/** A window that couldn't be had is asked again after this long, in ms. */
export const RETRY_MS = 10_000
/** The hand's speed for the sound, measured over this much of its last movement, in ms - shorter
 *  than a release's, so the sound answers the hand quickly. */
export const HAND_SPEED_MS = 40
/** How long one frame's drive holds, in seconds: a drive that stops coming runs out by itself. */
export const DRIVE_FOR_S = 0.12
/** The handover: the record's sound holds speed 1 for at most this long waiting for the song to play,
 *  then fades out over HANDOVER_FADE_S. A play that hasn't started by then was refused, and the
 *  platter spins down. */
export const HANDOVER_MAX_S = 3
export const HANDOVER_FADE_S = 0.04
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
 * still moves on by about three quarters of its length, rather than re-fetching what it had.
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
  /** the song's position the record was taken at, seconds */
  anchor: number
  /** where the hand has the record now, seconds */
  at: number
  intent: 'play' | 'pause'
  samples: HandSample[]
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
  loading: boolean
  problem: string | null
  missing: 'unsupported' | 'no-voice' | null
  /** why the script voice plays it, not the worklet - for Debug */
  why: string | null
}

const audio: DeckAudio = { context: null, voice: null, loading: false, problem: null, missing: null, why: null }
let moduleUrl: string | null = null
const audioListeners = new Set<() => void>()
let heardListener: ((heard: VoiceHeard) => void) | null = null
//? the page's audio session kind before the deck set it to 'playback', while the deck lives; null when
//? the deck hasn't set it
let sessionBefore: string | null = null
//? the turntable was hidden while its context was still starting or resuming (a tap's, and the page
//? hidden before it settled): suspended as soon as it runs, since nothing else would - a gesture asking
//? for the sound, or the turntable showing again, lets that go (review of 2.0.0-player.16)
let sleepOnceRunning = false

/** The main-thread voice's block, in samples: about 21 ms at 48 kHz (unmeasured on a phone). */
export const SCRIPT_BUFFER = 1024
/** How many of its blocks after it is said the main-thread voice hears a take or a drive: a message
 *  waits up to one block for the next to be asked for, which plays a block after it is asked - 43 ms
 *  at 48 kHz, a constant lag on the record's sound and nothing more (startScript). */
export const SCRIPT_LAG_BLOCKS = 2

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
    node.port.onmessage = (event: MessageEvent) => heardListener?.(event.data as VoiceHeard)
    node.connect(context.destination)
    audio.voice = { kind: 'worklet', ready: true, post: (said, transfer) => node.port.postMessage(said, transfer), disconnect: () => node.disconnect() }
  }).catch((error: unknown) => {
    if (audio.context === context && !audio.voice) startScript(context, `the AudioWorklet wouldn't load (${message(error)})`)
  }).finally(() => {
    if (audio.context === context) audio.loading = false
    audioChanged()
  })
}

/**
 * The script voice: a ScriptProcessorNode (no inputs, two output channels, SCRIPT_BUFFER a block) on
 * the page's main thread, running THE SAME functions the worklet runs - lib/deckVoice.ts's
 * newVoiceState, voiceCommand, renderVoice and voiceReport, never a copy of them. Each block is
 * rendered as of the context time it will play at (its `playbackTime`, a block ahead of `currentTime`
 * as the browser asks for it), and the messages that came since the last are applied to its state just
 * before, as of that same time - as the worklet applies each on the audio clock as it comes. And what
 * each says is heard SCRIPT_LAG_BLOCKS blocks after it was said - the most a message waits for the
 * block it is first heard in - so a take and the drives after it keep the same spacing they had as they
 * were said, and the voice plays exactly what the worklet would, that much later. Applied as they came,
 * as of `currentTime`, a take started a block or two behind where the record was by the time it was
 * heard, and raced to catch it up (review of 2.0.0-player.16: up to 1.8 times the speed, for 20-80 ms,
 * on every grab and every wind-down); placed where the record had got to instead, a grab's still hand
 * then pulled it back as far. Only what changes the voice is held: a drive replaces the drive before
 * it, and a window every window before it. It says where it is as often as the worklet does. Ready once
 * it has played its first block.
 */
function startScript(context: AudioContext, why: string): void {
  if (typeof context.createScriptProcessor !== 'function') {
    audio.missing = 'no-voice'
    return
  }
  try {
    const node = context.createScriptProcessor(SCRIPT_BUFFER, 0, 2)
    const state = newVoiceState()
    const held: VoiceMessage[] = []
    const lag = (SCRIPT_LAG_BLOCKS * SCRIPT_BUFFER) / context.sampleRate
    const voice: Voice = {
      kind: 'script',
      ready: false,
      post: (message) => {
        const said = message.type === 'take' || message.type === 'drive' ? { ...message, time: message.time + lag, until: message.until + lag } : message
        //? a drive sets every field the one before it set; a window sets nothing but the window
        if (said.type === 'drive' && held[held.length - 1]?.type === 'drive') held.pop()
        if (said.type === 'window') for (let i = held.length - 1; i >= 0; i--) if (held[i]!.type === 'window') held.splice(i, 1)
        held.push(said)
      },
      disconnect: () => {
        node.onaudioprocess = null
        held.length = 0
        node.disconnect()
      },
    }
    node.onaudioprocess = (event: AudioProcessingEvent) => {
      const out = event.outputBuffer
      const channels: Float32Array[] = []
      for (let channel = 0; channel < out.numberOfChannels; channel++) channels.push(out.getChannelData(channel))
      const at = Number.isFinite(event.playbackTime) ? event.playbackTime : context.currentTime
      for (const said of held.splice(0)) voiceCommand(state, said, at, context.sampleRate)
      renderVoice(state, channels, out.length, context.sampleRate, at)
      const heard = voiceReport(state, out.length, context.sampleRate, at, REPORTS_PER_SECOND)
      if (heard) heardListener?.(heard)
      if (!voice.ready && audio.voice === voice) {
        voice.ready = true
        audioChanged()
      }
    }
    node.connect(context.destination)
    audio.voice = voice
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
  audio.loading = false
  audio.problem = null
  audio.why = null
  sleepOnceRunning = false
  if (context && context.state !== 'closed') context.close().catch(() => undefined)
  releaseAudioSession()
  audioChanged()
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
  private songId: string

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
      this.lastFetchAt = 0
      this.positionOff = this.host.onPosition(this.onPosition)
      this.keepHere()
      this.loop()
    } else {
      this.positionOff?.()
      this.positionOff = null
      cancelFrame(this.raf)
      this.raf = 0
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
      this.spin(motor(0, this.speedNow(), 0), 'spin')
      this.keepHere()
      return
    }
    if ((this.press && this.press.taken) || this.motion.kind !== 'turning') return
    this.settleTimer = setTimeout(() => {
      this.settleTimer = undefined
      if (!this.host.playing() && !this.press?.taken && this.motion.kind === 'turning') this.spin(coast(0, 1, 0), 'spin')
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
    this.press = { taken: false, anchor: 0, at: 0, intent: 'pause', samples: [{ time, turned: 0 }] }
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
   * The record taken. Turning at speed under the song: the song pauses (the player's own toggle,
   * through the host) and the record's sound starts at its position, at its own speed if it was
   * playing. Coasting, coming back to speed or winding down: caught where the platter is, its sound
   * carrying on from there, and whether the song is meant to play kept from what it was doing. Either
   * way the hand has it from here. Returns where it was taken.
   */
  takeOver(): number {
    const press = this.press
    if (!press) return this.host.position()
    if (press.taken) return press.anchor
    clearTimeout(this.holdTimer)
    this.holdTimer = undefined
    clearTimeout(this.settleTimer)
    this.settleTimer = undefined
    const motion = this.motion
    let at: number
    if (motion.kind === 'plan' && motion.role !== 'spin') {
      clearTimeout(this.planTimer)
      this.planTimer = undefined
      this.endHandover()
      const { v } = planAt(motion.plan, (now() - motion.since) / 1000)
      at = this.recordAt()
      press.intent = motion.role === 'handover' ? 'play' : 'pause'
      if (!motion.sounding && this.sounding(at)) this.take(at, motion.quiet ? 0 : voiceRate(v))
    } else {
      const playing = this.host.playing()
      //? a song changed under the hand a moment ago, about to be played (songChanged): meant to play
      const pending = this.resumeTimer !== undefined
      clearTimeout(this.resumeTimer)
      this.resumeTimer = undefined
      at = this.host.position()
      if (playing) this.host.hold()
      press.intent = playing || pending ? 'play' : 'pause'
      if (this.sounding(at)) this.take(at, playing ? 1 : 0)
    }
    press.taken = true
    press.anchor = at
    press.at = at
    this.angle = this.angleNow()
    this.motion = { kind: 'hand' }
    this.keep(at)
    this.loop()
    return at
  }

  /** The hand moved: how far it has turned the record since the press (radians, as lib/turntable
   *  counts it) and where that puts the song (seconds). */
  hand(time: number, turned: number, at: number): void {
    const press = this.press
    if (!press?.taken) return
    press.samples.push({ time, turned })
    //? only the last moment of the hand counts: the release's speed, and the sound's
    while (press.samples.length > 2 && time - press.samples[0]!.time > 4 * VELOCITY_WINDOW_MS) press.samples.shift()
    press.at = at
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
    const song = this.host.song()
    const length = song?.length ?? 0
    if (how === 'cancel') {
      this.post({ type: 'stop' })
      if (press.intent === 'play') {
        this.host.resume()
        this.spin(motor(0, 0, 0), 'spin')
      } else {
        this.motion = { kind: 'still' }
      }
      this.host.show(null, false)
      return { seek: null, play: false }
    }
    const speed = handSpeed(press.samples, time, VELOCITY_WINDOW_MS)
    if (press.intent === 'play') {
      const plan = motor(press.at, speed, length)
      if (this.reduced || plan.duration <= RESUME_IN_GESTURE_S) {
        //? nothing to wait for (or nothing to animate): played from there in this very gesture
        this.post({ type: 'stop' })
        this.motion = { kind: 'turning', since: now(), from: this.angleNow() }
        this.host.show(null, false)
        this.loop()
        return { seek: plan.x, play: true }
      }
      this.startPlan(plan, 'handover', press.at, this.sounding(press.at))
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
    this.startPlan(plan, 'coast', press.at, this.sounding(press.at))
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
    const plan = coast(at, 1, song?.length ?? 0)
    if (plan.duration === 0) {
      //? at the very end of the song: nothing left to wind down into
      this.angle = this.angleNow()
      this.motion = { kind: 'still' }
      return null
    }
    const sounding = this.windDown && this.sounding(at) && this.covers(at, plan.x - at)
    if (sounding) this.take(at, 1)
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
  private recordAt(): number {
    const motion = this.motion
    if (motion.kind === 'plan' && motion.role !== 'spin' && !motion.quiet && (motion.sounding || motion.role !== 'winddown')) {
      return planAt(motion.plan, (now() - motion.since) / 1000).x
    }
    return this.host.position()
  }

  /** Whether the song is meant to be playing when the deck lets go of it: the hand took it from
   *  playing, and hasn't given it back yet. */
  private meantToPlay(): boolean {
    const motion = this.motion
    return (!!this.press?.taken && this.press.intent === 'play') || (motion.kind === 'plan' && motion.role === 'handover')
  }

  private speedNow(): number {
    const motion = this.motion
    if (motion.kind === 'turning') return 1
    if (motion.kind === 'plan') return planAt(motion.plan, (now() - motion.since) / 1000).v
    return 0
  }

  private angleNow(): number {
    const motion = this.motion
    if (this.reduced || this.stilled) return this.angle
    if (motion.kind === 'turning') return motion.from + (DEGREES_PER_SECOND * (now() - motion.since)) / 1000
    if (motion.kind === 'plan') return motion.from + degreesFor(planAt(motion.plan, (now() - motion.since) / 1000).x - motion.x0)
    return this.angle
  }

  /** A visual movement only - the spin-up of a play, the spin-down of a pause from elsewhere. */
  private spin(plan: Plan, role: 'spin'): void {
    if (this.reduced) {
      this.motion = role === 'spin' && plan.v >= 1 ? { kind: 'turning', since: now(), from: this.angle } : { kind: 'still' }
      return
    }
    this.startPlan(plan, role, plan.phases[0] ? planAt(plan, 0).x : 0, false)
  }

  private startPlan(plan: Plan, role: Role, x0: number, sounding: boolean): void {
    const from = this.angleNow()
    clearTimeout(this.planTimer)
    //? a wind-down without its sound leaves the song where it paused: nothing seeks it to the end
    const sought = role === 'winddown' && !sounding ? x0 : plan.x
    this.motion = { kind: 'plan', role, plan, since: now(), from, x0, sounding, sought, quiet: false }
    const motion = this.motion
    //? the plan's end on a timer, not the frame loop: a hidden page draws nothing, but a coast back to
    //? speed must still play the song when it gets there
    this.planTimer = setTimeout(() => this.planEnded(motion), plan.duration * 1000)
    this.loop()
  }

  private planEnded(motion: Motion): void {
    this.planTimer = undefined
    if (this.motion !== motion || motion.kind !== 'plan') return
    const angle = this.angleNow()
    if (motion.role === 'handover') {
      //? at speed: the song plays - after the tap; the record's sound holds speed 1 until it does -
      //? unless the song was sought somewhere else meanwhile (quiet: there is nothing to hold for)
      this.motion = { kind: 'turning', since: now(), from: angle }
      this.host.show(null, false)
      this.handOver(motion.plan.x, motion.sounding && !motion.quiet)
      this.host.resume()
      //? a play iOS refuses ("Tap play to start") leaves the song paused: the platter spins down
      //? rather than turning on beside it. A play that takes clears this (playingChanged)
      clearTimeout(this.settleTimer)
      this.settleTimer = setTimeout(() => {
        this.settleTimer = undefined
        if (!this.host.playing() && !this.press?.taken && this.motion.kind === 'turning') this.spin(coast(0, 1, 0), 'spin')
      }, HANDOVER_MAX_S * 1000)
    } else if (motion.role === 'spin' && motion.plan.v >= 1) {
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

  /** The record's sound holds speed 1 from `at` until the song is really playing - its position past
   *  `at` - then fades; HANDOVER_MAX_S at most. A position nowhere near `at` (the song sought elsewhere
   *  as it started) ends it as well: there is nothing to hand over to. */
  private handOver(at: number, sounding: boolean): void {
    this.endHandover()
    if (!sounding) return
    const context = audio.context
    const time = context?.currentTime ?? 0
    this.post({ type: 'drive', at, rate: 1, time, until: time + HANDOVER_MAX_S })
    const done = () => {
      this.endHandover()
      this.post({ type: 'fade', seconds: HANDOVER_FADE_S })
    }
    this.handoverOff = this.host.onPosition((seconds) => {
      if (Math.abs(seconds - at) > SOUGHT_ELSEWHERE_S || (this.host.playing() && seconds > at + 0.02)) done()
    })
    this.handoverTimer = setTimeout(done, HANDOVER_MAX_S * 1000)
  }

  private endHandover(): void {
    this.handoverOff?.()
    this.handoverOff = null
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
    const context = audio.context
    const contextTime = context?.currentTime ?? 0
    if (press?.taken) {
      const rate = handSpeed(press.samples, Math.max(time, press.samples[press.samples.length - 1]!.time), HAND_SPEED_MS)
      this.post({ type: 'drive', at: press.at, rate: voiceRate(rate), time: contextTime, until: contextTime + DRIVE_FOR_S })
      this.host.show(this.heardNow() ?? press.at, true)
    } else if (motion.kind === 'plan') {
      const t = (time - motion.since) / 1000
      const { x, v } = planAt(motion.plan, t)
      //? the plan's own acceleration too, so the voice follows the curve between frames
      const accel = t < motion.plan.duration ? acceleration(v, motion.role === 'handover' || (motion.role === 'spin' && motion.plan.v >= 1)) : 0
      if (motion.sounding) this.post({ type: 'drive', at: x, rate: voiceRate(v), accel: voiceRate(accel), time: contextTime, until: contextTime + DRIVE_FOR_S })
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
    try {
      audio.voice?.post(message, transfer)
    } catch {
      //? a node going away mid-message: nothing to play it on anyway
    }
  }

  private take(at: number, rate: number): void {
    const time = audio.context?.currentTime ?? 0
    this.post({ type: 'take', at, rate, time, until: time + DRIVE_FOR_S })
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

  private readonly onPosition = (seconds: number) => {
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
    if (!this.host.playing() && !busy) return
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
    const where = at ?? this.host.position()
    const { back, ahead } = windowMargins(this.span?.song === song.id ? this.span.seconds : WINDOW_S)
    const refreshing = span === undefined && this.host.playing() && !busy
    const room = song.length > 0 ? Math.max(0, song.length - where - 0.5) : Infinity
    const need = Math.max(0, span ?? (refreshing ? Math.min(ahead, room) : 0))
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
      const got = await scrubWindow(id, from, WINDOW_S, request.signal, song.maxRate ?? null)
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
    if (press?.taken && this.heardNow() === null && this.sounding(press.at)) this.take(press.at, 0)
    else if (motion.kind === 'plan' && !motion.sounding && !motion.quiet && (motion.role === 'coast' || motion.role === 'handover')) {
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
    this.heard = { ...heard, at: now() }
  }

  private readonly onAudio = () => {
    //? a context made, resumed, suspended; a voice ready: what was waiting goes on - and the
    //? window is asked for now, if none was for want of somewhere to put it
    this.decode()
    this.handWindow()
    this.keepHere()
    this.report()
  }

  private readonly onReduced = () => {
    this.reduced = !!this.reducedQuery?.matches
    this.loop()
  }

  /* ----- for Info > Debug ----- */

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
    })
  }
}

/** How often the voice reports, for the docs and the sim. */
export const HEARD_PER_SECOND = REPORTS_PER_SECOND
