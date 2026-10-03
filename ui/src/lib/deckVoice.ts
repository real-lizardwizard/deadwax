/**
 * The record's own sound (2.0.0-player.14): what the turntable plays while a hand turns the record,
 * while a flick coasts, and while a pause winds it down - pure, so ui/test/deck.sim.cjs runs it as it
 * runs in the browser.
 *
 * A SEPARATE sound path. The player's own audio element is never connected to Web Audio - a
 * createMediaElementSource is what breaks locked playback on an iPhone - so normal playback is
 * exactly what it was, bit for bit. This sound is a stretch of the song round the playhead, decoded
 * from a FLAC window deadwax cuts (src/flac_window.py), and read here at a SIGNED, fractional rate: 1
 * is the song, 0 is silence - a record held still makes no sound - and negative runs it backwards.
 * Outside the window it is silent. What runs these functions is an AudioWorklet, on an audio thread of
 * its own, wherever the page can have one - or, where it can't (a page that isn't on HTTPS: the browser
 * gives AudioWorklet to secure pages only), a ScriptProcessorNode on the page's main thread
 * (player/deck.ts, 2.0.0-player.16). One DSP, two hosts: nothing about the sound differs but where it
 * runs - and, on the main thread, a constant 43 ms later (SCRIPT_LAG_BLOCKS, deck.ts's startScript).
 *
 *  - The worklet is driven by a position and a rate (`drive`): where the record is now in the song,
 *    and how fast it is going - the hand's, the coast's, the wind-down's, from player/deck.ts each
 *    frame - and for a coast how fast that is changing, so it follows a curve between frames, not a
 *    line. It reads at that rate and steers towards that position (FOLLOW_S), so what is heard
 *    never drifts from what the platter shows, and a drive that stops coming (a page stalled, a tab
 *    hidden) runs out by itself (`until`) rather than leaving the record whirring.
 *  - The rate it reads at is smoothed, a one-pole filter of SMOOTH_S (10 ms) a sample, so a change of
 *    speed never steps; and the position is a running sum of it, so nothing ever jumps.
 *  - Its loudness fades in and out (`take`, `fade`, `stop`) rather than switching, and fades at the
 *    window's two edges (EDGE_S).
 *  - A DC blocker (10 Hz) on the way out: a record held still reads one sample over and over, a
 *    constant, which this takes down to silence - and anything a slow turn pitches down below
 *    hearing goes with it.
 *  - Read with four-point (Catmull-Rom) interpolation, so the song at speed 1 - the handover after a
 *    coast, the start of a wind-down - sounds as the song does, not dulled.
 *
 * The four functions the worklet runs - newVoiceState, voiceCommand, renderVoice and voiceReport - are
 * written SELF-CONTAINED (no imports, no module constants, no helpers outside themselves, nor one
 * another), because the worklet's module is made from their own source text (voiceWorkletSource): an
 * AudioWorklet runs in a scope of its own, and the page's bundle can't be imported into it. The
 * main-thread voice calls the very same four.
 */

/** The worklet's name, as registerProcessor() and new AudioWorkletNode() say it. */
export const VOICE_PROCESSOR = 'deadwax-deck-voice'

/** How many times a second the voice says where it is - either host (voiceReport). */
export const REPORTS_PER_SECOND = 30

/** A stretch of the song, decoded: its channels at `rate` samples a second, from `start` (song s). */
export interface VoiceWindow {
  channels: Float32Array[]
  start: number
  rate: number
  length: number
}

export interface VoiceState {
  /** where the read head is, in seconds of the song - what is heard */
  pos: number
  /** how fast it reads, smoothed: 1 the song's own pace, negative backwards */
  rate: number
  /** how loud, smoothed, 0 to 1 - and where it is heading, how fast (per sample) */
  gain: number
  gainTarget: number
  gainAlpha: number
  /** what it steers towards: a position and a rate as of a context time, good until another */
  driving: boolean
  driveAt: number
  driveRate: number
  driveAccel: number
  driveTime: number
  driveUntil: number
  window: VoiceWindow | null
  /** the DC blocker's last input and output, per channel */
  lastIn: number[]
  lastOut: number[]
  /** samples played since it last said where it is (voiceReport) */
  counted: number
}

export type VoiceMessage =
  /** a new stretch of the song; the read head stays where it is in the song */
  | { type: 'window'; channels: Float32Array[]; start: number; rate: number }
  /** start sounding where the record is - at `at` as of context time `time`, moving at `rate` (1 for
   *  a song that was playing) - already at that rate, faded in */
  | { type: 'take'; at: number; rate: number; time: number; until: number }
  /** steer towards `at`, moving at `rate` and changing it by `accel` a second (a coast's friction, the
   *  motor's pull), as of context time `time`, until `until` */
  | { type: 'drive'; at: number; rate: number; accel?: number; time: number; until: number }
  /** fade out over `seconds`, then rest */
  | { type: 'fade'; seconds: number }
  /** silence now (a few ms), and rest */
  | { type: 'stop' }

/** What the voice says ~30 times a second. */
export interface VoiceHeard {
  type: 'heard'
  pos: number
  rate: number
  gain: number
  time: number
}

/** A voice at rest: silent, nowhere in particular, nothing to play. */
export function newVoiceState(): VoiceState {
  return {
    pos: 0, rate: 0, gain: 0, gainTarget: 0, gainAlpha: 0.01,
    driving: false, driveAt: 0, driveRate: 0, driveAccel: 0, driveTime: 0, driveUntil: 0,
    window: null, lastIn: [0, 0], lastOut: [0, 0], counted: 0,
  }
}

/** A message from the page, applied as of context time `now`. */
export function voiceCommand(state: VoiceState, message: VoiceMessage, now: number, sampleRate: number): void {
  //? a one-pole filter's step for a time constant, per sample
  const alpha = (seconds: number) => 1 - Math.exp(-1 / (Math.max(seconds, 1e-4) * sampleRate))
  //? a fade in or a stop: a few milliseconds, so it never clicks
  const QUICK_S = 0.003
  if (message.type === 'window') {
    const channels = message.channels.filter((channel) => channel && channel.length)
    state.window = channels.length ? { channels, start: message.start, rate: message.rate, length: channels[0]!.length } : null
  } else if (message.type === 'take') {
    //? where the record is by `now`: it was at `at` as of context time `time`, moving at `rate` - and a
    //? host may apply it later than that (the main-thread voice holds it to its next block, which plays
    //? a block or two on). Started there, it has nothing to catch up; started at `at`, the steering would
    //? race it to where the record had got to - a chirp, half an octave up (review of 2.0.0-player.16)
    state.pos = message.at + message.rate * (now - message.time)
    state.rate = message.rate
    state.gain = 0
    state.gainTarget = 1
    state.gainAlpha = alpha(QUICK_S)
    state.driving = true
    state.driveAt = message.at
    state.driveRate = message.rate
    state.driveAccel = 0
    state.driveTime = message.time
    state.driveUntil = message.until
  } else if (message.type === 'drive') {
    state.driving = true
    state.driveAt = message.at
    state.driveRate = message.rate
    state.driveAccel = message.accel ?? 0
    state.driveTime = message.time
    state.driveUntil = message.until
  } else if (message.type === 'fade') {
    //? an exponential fade: four time constants in `seconds`, about 35 dB down by then
    state.gainTarget = 0
    state.gainAlpha = alpha(message.seconds / 4)
  } else if (message.type === 'stop') {
    state.driving = false
    state.gainTarget = 0
    state.gainAlpha = alpha(QUICK_S)
  }
}

/**
 * `frames` samples of the record's sound into `outputs` (one Float32Array a channel), from context
 * time `now`. Each sample: the rate steered towards the drive and smoothed, the read head moved by
 * it, the window read there with four-point interpolation (silence outside it, faded at its edges),
 * the gain smoothed, and the DC blocker.
 */
export function renderVoice(state: VoiceState, outputs: Float32Array[], frames: number, sampleRate: number, now: number): void {
  //? the rate's smoothing, and the drive's steering - critically damped together (FOLLOW = 4 SMOOTH)
  const SMOOTH_S = 0.01
  const FOLLOW_S = 0.04
  //? the fastest it reads, either way, in the song's own speeds
  const MAX_RATE = 24
  //? the fade at the window's edges, and the DC blocker's corner
  const EDGE_S = 0.004
  const DC_HZ = 10
  //? below this loudness nothing is read: silence
  const QUIET = 1e-5
  const rateAlpha = 1 - Math.exp(-1 / (SMOOTH_S * sampleRate))
  const pole = Math.exp((-2 * Math.PI * DC_HZ) / sampleRate)
  const dt = 1 / sampleRate
  const win = state.window
  const count = outputs.length
  for (let i = 0; i < frames; i++) {
    const t = now + i * dt
    let desired = 0
    if (state.driving && t <= state.driveUntil) {
      const since = t - state.driveTime
      const target = state.driveAt + state.driveRate * since + 0.5 * state.driveAccel * since * since
      desired = state.driveRate + state.driveAccel * since + (target - state.pos) / FOLLOW_S
      if (desired > MAX_RATE) desired = MAX_RATE
      else if (desired < -MAX_RATE) desired = -MAX_RATE
    }
    state.rate += (desired - state.rate) * rateAlpha
    state.pos += state.rate * dt
    state.gain += (state.gainTarget - state.gain) * state.gainAlpha
    let shape = 0
    let index = 0
    if (win && state.gain > QUIET) {
      index = (state.pos - win.start) * win.rate
      const last = win.length - 1
      const edge = Math.min(index, last - index) / (EDGE_S * win.rate)
      shape = edge <= 0 ? 0 : edge >= 1 ? 1 : edge
    }
    for (let c = 0; c < count; c++) {
      let value = 0
      if (shape > 0 && win) {
        const data = win.channels[c % win.channels.length]!
        const last = win.length - 1
        const at = Math.floor(index)
        const f = index - at
        const y0 = data[at - 1 < 0 ? 0 : at - 1]!
        const y1 = data[at < 0 ? 0 : at > last ? last : at]!
        const y2 = data[at + 1 > last ? last : at + 1]!
        const y3 = data[at + 2 > last ? last : at + 2]!
        const c1 = 0.5 * (y2 - y0)
        const c2 = y0 - 2.5 * y1 + 2 * y2 - 0.5 * y3
        const c3 = 0.5 * (y3 - y0) + 1.5 * (y1 - y2)
        value = (((c3 * f + c2) * f + c1) * f + y1) * shape * state.gain
      }
      //? the DC blocker: y = x - x[-1] + pole y[-1]
      const out = value - (state.lastIn[c] ?? 0) + pole * (state.lastOut[c] ?? 0)
      state.lastIn[c] = value
      state.lastOut[c] = out
      outputs[c]![i] = out
    }
  }
}

/**
 * After `frames` samples played from context time `now`: what the voice says of where it is, when
 * `perSecond` times a second come round (exactly - the count carries its remainder), or null. Both
 * hosts call it after renderVoice, so the worklet and the main-thread voice say it alike.
 */
export function voiceReport(state: VoiceState, frames: number, sampleRate: number, now: number, perSecond: number): VoiceHeard | null {
  state.counted += frames
  const every = sampleRate / perSecond
  if (state.counted < every) return null
  state.counted -= every
  return { type: 'heard', pos: state.pos, rate: state.rate, gain: state.gain, time: now }
}

/**
 * The worklet's module, made from the four functions' own source - so what the browser runs is
 * exactly what the sim runs, the page's build or not. Loaded through a Blob URL (player/deck.ts).
 */
export function voiceWorkletSource(): string {
  return [
    `const newVoiceState = ${newVoiceState.toString()};`,
    `const voiceCommand = ${voiceCommand.toString()};`,
    `const renderVoice = ${renderVoice.toString()};`,
    `const voiceReport = ${voiceReport.toString()};`,
    `class DeckVoice extends AudioWorkletProcessor {`,
    `  constructor() {`,
    `    super();`,
    `    this.state = newVoiceState();`,
    `    this.port.onmessage = (event) => voiceCommand(this.state, event.data, currentTime, sampleRate);`,
    `  }`,
    `  process(inputs, outputs) {`,
    `    const out = outputs[0];`,
    `    if (out && out.length) {`,
    `      renderVoice(this.state, out, out[0].length, sampleRate, currentTime);`,
    `      const heard = voiceReport(this.state, out[0].length, sampleRate, currentTime, ${REPORTS_PER_SECOND});`,
    `      if (heard) this.port.postMessage(heard);`,
    `    }`,
    `    return true;`,
    `  }`,
    `}`,
    `registerProcessor(${JSON.stringify(VOICE_PROCESSOR)}, DeckVoice);`,
  ].join('\n')
}

/* ===== what Info > Debug says of it ===== */

/** Where the turntable's sound is, for Info > Debug's "Turntable sound" row (lib/debugRows.ts). */
export interface DeckReport {
  /**
   * The audio context: 'none' - no tap has started it yet, or it is suspended (the turntable hidden,
   * the screen closed, the page in the background) - 'starting' (running, its voice not yet playing),
   * 'running'; or why there is none: 'unsupported' (no Web Audio), 'no-voice' (neither an AudioWorklet
   * nor a ScriptProcessorNode to play it on), 'failed' (`problem` says why).
   */
  context: 'none' | 'starting' | 'running' | 'unsupported' | 'no-voice' | 'failed'
  /** the browser's own words, for 'failed' */
  problem: string | null
  /**
   * What plays it (2.0.0-player.16): 'worklet' - an AudioWorklet, on an audio thread of its own - or
   * 'script' - a ScriptProcessorNode on the page's main thread, where the page has no AudioWorklet or
   * it wouldn't load; null while there is neither.
   */
  voice: 'worklet' | 'script' | null
  /** why the main thread, for 'script': "this page isn't on HTTPS, so the browser has no AudioWorklet" */
  voiceWhy: string | null
  /** the window decoded and in the voice: the stretch of the song (s), its kind, the rate it was
   *  decoded at, and its size as fetched */
  window: { start: number; end: number; kind: string; decodedAt: number; bytes: number } | null
  /** a window on its way (fetched, or waiting to be decoded) */
  loading: boolean
  /** why this song has no sound: deadwax's words (a 415) or the page's (not a FLAC) */
  refused: string | null
  /** a window that couldn't be fetched or decoded: the reason, the browser's own for a decode */
  failed: string | null
  /** what fetching windows has cost since the turntable showed: bytes - and how many ms after it
   *  showed the last of them landed, which is what that is measured to (the report is made as things
   *  change, not as time passes) */
  fetched: number
  lastFetchAt: number
}
