/**
 * The sound the desktop visualizer sees (2.0.0-player.20): a SILENT, separately decoded copy of the
 * stretch of the song playing - never the player's own audio element.
 *
 * WHY A COPY. The element is never connected to Web Audio, anywhere in the app: a
 * createMediaElementSource reroutes the song through Web Audio, which breaks locked playback on an
 * iPhone and puts processing between the file and the speakers - and James's rule is audio fidelity
 * first, "the tap must be measured to change nothing" (ui/test/app-rules.sim.cjs holds every file to
 * never calling it). So the copy is the turntable's FLAC window (GET /deadwax/navidrome/scrub/{id},
 * player/api.ts scrubWindow - cut by deadwax from the very copy the page plays, max_rate and all),
 * decoded by decodeAudioData, played by an AudioBufferSourceNode into an AnalyserNode and on into a
 * GainNode at 0 - connected to the destination only because a node nobody pulls is never run. Nothing
 * of it is heard. lib/vizSync.ts decides, each frame, when it starts, stops, re-syncs and asks for the
 * next window - and for the next song's first window, in this one's last seconds, so a song change
 * carries straight on; this does what it says.
 *
 * WHAT A WINDOW COSTS deadwax: it is cut from the MP4 of the song the player's cache keeps, where
 * there is one - Safari and the gapless stream have that copy made already, as has a resampled song.
 * A page playing the FLAC as it is (Chrome, Firefox or Edge with Gapless off - the default) has none,
 * and since 2.0.0-player.23 its windows are cut straight from the FLAC on Navidrome by byte ranges -
 * the song's head once, then about each window's own size - with nothing made or kept in the cache
 * (src/flac_ranges.py; docs/player.md "What it listens to"). Until then the first window of each song
 * had deadwax fetch the whole song again and keep its MP4, against PLAYER_CACHE_MB.
 *
 * NOTHING HERE NEEDS A SECURE PAGE (James opens deadwax over plain http): an AudioContext,
 * decodeAudioData and an AnalyserNode are all there without one; no AudioWorklet is used.
 *
 * THE AUDIO CONTEXT is made only in wakeVisualizerAudio(), from the click that opens the visualizer
 * (App's openVisualizer - app-rules pins both), so the browser lets it run. Suspended while the page
 * is hidden, resumed as it shows (and from a click or key in the visualizer, where a browser wants a
 * gesture for that), and closed as the visualizer closes.
 */

import { ApiError } from '../api/http'
import { isAbort, latestOnly } from '../lib/latest'
import { FFT_SIZE, MAX_DB, MIN_DB, bandLayout, bandsFromBins, waveFromSamples, type BandSpan } from '../lib/visualizer'
import { VIZ_RETRY_MS, VIZ_WINDOW_S, copyAt, planSync, reanchor, takeAhead, type CopyAnchor, type HeldWindow, type Seeing, type SyncSong } from '../lib/vizSync'
import { scrubWindow } from './api'

type ContextClass = new () => AudioContext

/** The page's one context for the visualizer, while it is open. */
const audio: { context: AudioContext | null; problem: string | null } = { context: null, problem: null }

function contextClass(): ContextClass | null {
  const scope = (typeof window === 'undefined' ? {} : window) as { AudioContext?: ContextClass; webkitAudioContext?: ContextClass }
  return scope.AudioContext ?? scope.webkitAudioContext ?? null
}

/**
 * Makes the visualizer's audio context (once) and starts it - called only from the click that opens
 * the visualizer, a gesture every browser lets a context run from.
 */
export function wakeVisualizerAudio(): void {
  if (audio.context && audio.context.state !== 'closed') {
    resumeVisualizerAudio()
    return
  }
  const Context = contextClass()
  if (!Context) {
    audio.problem = 'no Web Audio'
    return
  }
  try {
    audio.context = new Context()
    audio.problem = null
  } catch (error) {
    audio.context = null
    audio.problem = error instanceof Error ? error.message : String(error)
    return
  }
  resumeVisualizerAudio()
}

/** Starts a suspended context again - from a gesture in the visualizer, or as the page shows. Never
 *  makes one. */
export function resumeVisualizerAudio(): void {
  const context = audio.context
  if (context && context.state === 'suspended') context.resume().catch(() => undefined)
}

/** The page hidden: nothing of it runs. */
export function suspendVisualizerAudio(): void {
  const context = audio.context
  if (context && context.state === 'running') context.suspend().catch(() => undefined)
}

/** The visualizer closed: the context goes. */
export function closeVisualizerAudio(): void {
  const context = audio.context
  audio.context = null
  if (context && context.state !== 'closed') context.close().catch(() => undefined)
}

interface Held extends HeldWindow {
  buffer: AudioBuffer
}

/** How many songs' refusals, failures and window lengths are remembered - the few round the playhead. */
const REMEMBERED = 8

/**
 * The silent copy for one opening of the visualizer: its analyser, the window in hand, the next song's
 * first window fetched ahead, the one on its way, and the source node playing it. `tick` each frame
 * with what the element is doing; `read` the spectrum and waveform; `destroy` as it closes.
 */
export class VizListener {
  private analyser: AnalyserNode | null = null
  private silent: GainNode | null = null
  private madeFor: AudioContext | null = null
  private layout: BandSpan[] = []
  private bins = new Uint8Array(0)
  private samples = new Float32Array(0)
  private node: AudioBufferSourceNode | null = null
  //? the copy playing: its song and window, and where it was started, when, at what rate (the player's
  //? speed, 2.0.0-player.39) - copyAt says where it has got to
  private source: { song: string; key: number; anchor: CopyAnchor } | null = null
  //? the player's speed at the last look: what a copy is started at
  private rate = 1
  private held: Held | null = null
  /** the next song's first window, fetched in this one's last seconds (lib/vizSync.ts prefetch) */
  private ahead: Held | null = null
  /** the song playing at the last look: a window decoded for it is held, for another one ahead */
  private current: string | null = null
  private pending: { song: string; from: number; to: number } | null = null
  //? each song's own: a refusal or a failure for the next song must never stand for this one's
  private readonly refused = new Map<string, string>()
  private readonly failed = new Map<string, { why: string; until: number }>()
  private readonly spans = new Map<string, number>()
  private keys = 0
  private readonly requests = latestOnly()
  private readonly decodes = latestOnly()
  private readonly agc = { peak: 0.3 }
  private seeing: Seeing = 'nothing'
  private why: string | null = null

  constructor(private readonly onSeeing: (seeing: Seeing, why: string | null) => void) {}

  /** One look: what the element is doing and the song after it, and the copy made to follow it
   *  (lib/vizSync.ts) - at `rate`, the player's speed (2.0.0-player.39). */
  tick(song: SyncSong | null, following: SyncSong | null, running: boolean, position: number, rate = 1): void {
    const context = audio.context
    const state = !context ? 'none' : context.state === 'running' && this.graph(context) ? 'running' : context.state === 'closed' ? 'none' : 'starting'
    this.current = song?.id ?? null
    //? the speed changed: the copy running carries on from where it has got to, at the new rate
    this.rate = rate
    if (this.node && this.source && context && this.source.anchor.rate !== rate) {
      this.source.anchor = reanchor(this.source.anchor, context.currentTime, rate)
      this.node.playbackRate.value = rate
    }
    //? the song changed to the one fetched ahead: its first window is the one held now
    const taken = takeAhead(this.held, this.ahead, this.current, following?.id ?? null)
    this.held = taken.held
    this.ahead = taken.ahead
    const source = this.source && context ? { song: this.source.song, key: this.source.key, at: copyAt(this.source.anchor, context.currentTime) } : null
    const ids = [song?.id, following?.id]
    const plan = planSync({
      song, following, running, position, now: Date.now(), audio: state,
      held: this.held, ahead: this.ahead, pending: this.pending, source,
      refused: [...this.refused].filter(([id]) => ids.includes(id)).map(([id, why]) => ({ song: id, why })),
      failed: [...this.failed].filter(([id]) => ids.includes(id)).map(([id, failure]) => ({ song: id, ...failure })),
      span: song && this.spans.has(song.id) ? { song: song.id, seconds: this.spans.get(song.id)! } : null,
    })
    if (plan.stop || plan.start !== null) this.stopNode()
    if (plan.start !== null) this.startNode(plan.start)
    if (plan.fetch !== null && song) void this.fetchWindow(song, plan.fetch)
    else if (plan.prefetch !== null && following) void this.fetchWindow(following, plan.prefetch)
    if (plan.seeing !== this.seeing || plan.why !== this.why) {
      this.seeing = plan.seeing
      this.why = plan.why
      this.onSeeing(plan.seeing, plan.why)
    }
  }

  /** Whether the copy is being analysed now. */
  hearing(): boolean {
    return this.node !== null
  }

  /**
   * The spectrum (64 bands, 0-1) and the waveform (lib/visualizer.ts's shape) of what the copy is
   * playing now; false - nothing written - while it isn't playing.
   */
  read(spectrum: Float32Array, wave: Float32Array, level: number, dt: number): boolean {
    const analyser = this.analyser
    const context = this.madeFor
    if (!this.node || !analyser || !context) return false
    analyser.getByteFrequencyData(this.bins)
    bandsFromBins(this.bins, this.layout, spectrum)
    if (typeof analyser.getFloatTimeDomainData === 'function') {
      analyser.getFloatTimeDomainData(this.samples)
    } else {
      //? an older WebKit: the bytes, centred on 128
      const bytes = new Uint8Array(this.samples.length)
      analyser.getByteTimeDomainData(bytes)
      for (let k = 0; k < bytes.length; k++) this.samples[k] = (bytes[k]! - 128) / 128
    }
    waveFromSamples(this.samples, context.sampleRate, this.agc, level, dt, wave)
    return true
  }

  /** The visualizer closed: the copy stops, every ask is let go, and the nodes are let go. */
  destroy(): void {
    this.requests.supersede()
    this.decodes.supersede()
    this.stopNode()
    try {
      this.analyser?.disconnect()
      this.silent?.disconnect()
    } catch {
      // already gone with its context
    }
    this.analyser = null
    this.silent = null
    this.madeFor = null
    this.held = null
    this.ahead = null
    this.pending = null
  }

  /** The analyser and the silent gain, made once per context. */
  private graph(context: AudioContext): boolean {
    if (this.madeFor === context && this.analyser) return true
    try {
      const analyser = context.createAnalyser()
      analyser.fftSize = FFT_SIZE
      analyser.smoothingTimeConstant = 0
      analyser.minDecibels = MIN_DB
      analyser.maxDecibels = MAX_DB
      const silent = context.createGain()
      silent.gain.value = 0
      analyser.connect(silent)
      silent.connect(context.destination)
      this.analyser = analyser
      this.silent = silent
      this.madeFor = context
      this.layout = bandLayout(FFT_SIZE, context.sampleRate)
      this.bins = new Uint8Array(analyser.frequencyBinCount)
      this.samples = new Float32Array(FFT_SIZE)
      return true
    } catch {
      return false
    }
  }

  private startNode(at: number): void {
    const held = this.held
    const context = this.madeFor
    if (!held || !context || !this.analyser) return
    const node = context.createBufferSource()
    node.buffer = held.buffer
    //? at the player's speed, as the song plays (2.0.0-player.39)
    node.playbackRate.value = this.rate
    node.connect(this.analyser)
    node.onended = () => {
      if (this.node !== node) return
      this.node = null
      this.source = null
    }
    node.start(0, Math.max(0, at - held.start))
    this.node = node
    this.source = { song: held.song, key: held.key, anchor: { at, time: context.currentTime, rate: this.rate } }
  }

  private stopNode(): void {
    const node = this.node
    this.node = null
    this.source = null
    if (!node) return
    node.onended = null
    try {
      node.stop()
      node.disconnect()
    } catch {
      // already stopped
    }
  }

  private async fetchWindow(song: SyncSong, from: number): Promise<void> {
    const request = this.requests.begin()
    //? one window on its way at a time: one still being decoded gives way to this
    this.decodes.supersede()
    this.pending = { song: song.id, from, to: from + VIZ_WINDOW_S }
    try {
      const got = await scrubWindow(song.id, from, VIZ_WINDOW_S, request.signal, song.maxRate)
      if (!request.current()) return
      const start = got.first / got.rate
      const end = (got.first + got.samples) / got.rate
      //? cut short by deadwax's budget (a hi-res song's) rather than by the song's end: the margins
      //? shrink to suit it (vizMargins)
      const short = end < from + VIZ_WINDOW_S - 0.01 && !(song.length > 0 && end >= song.length - 0.5)
      remember(this.spans, song.id, short ? end - start : VIZ_WINDOW_S)
      this.failed.delete(song.id)
      this.pending = { song: song.id, from: start, to: end }
      this.decode(song.id, got.bytes, start)
    } catch (reason) {
      if (!request.current() || isAbort(reason)) return
      this.pending = null
      if (reason instanceof ApiError && reason.status === 415) {
        remember(this.refused, song.id, reason.detail ?? "deadwax can't cut a window of it")
      } else {
        remember(this.failed, song.id, { why: "deadwax couldn't send its sound", until: Date.now() + VIZ_RETRY_MS })
      }
    }
  }

  /** A window decoded, and taken as the one held - or, the next song's, as the one ahead - only the
   *  newest decode counts. */
  private decode(song: string, bytes: ArrayBuffer, start: number): void {
    const context = audio.context
    if (!context || context.state === 'closed') {
      this.pending = null
      return
    }
    const ticket = this.decodes.begin()
    const done = (buffer: AudioBuffer) => {
      if (!ticket.current()) return
      this.keys += 1
      const decoded = { song, start, end: start + buffer.duration, key: this.keys, buffer }
      //? the song playing's window is the one held; the next song's, fetched ahead, waits for it
      if (song === this.current) this.held = decoded
      else this.ahead = decoded
      if (this.pending?.song === song) this.pending = null
    }
    const failed = () => {
      if (!ticket.current()) return
      this.pending = null
      remember(this.refused, song, "this browser couldn't read its sound")
    }
    try {
      //? the callback form: older WebKit has no promise from it
      const promise = context.decodeAudioData(bytes, done, failed) as Promise<AudioBuffer> | undefined
      promise?.catch?.(() => undefined)
    } catch {
      failed()
    }
  }
}

/** A song's entry kept, the oldest let go past REMEMBERED. */
function remember<V>(map: Map<string, V>, song: string, value: V): void {
  map.delete(song)
  map.set(song, value)
  for (const oldest of map.keys()) {
    if (map.size <= REMEMBERED) break
    map.delete(oldest)
  }
}
