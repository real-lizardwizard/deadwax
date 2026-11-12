/**
 * The deck's harness (moved out of ui/test/deck.sim.cjs for the iPhone's port): a clock, timers and frames the
 * test moves on, a fake audio context with its worklet node and script processor, deadwax's window route, the
 * deck's host - everything player/deck.ts reaches outside itself, faked as deck.sim has always faked it. deck.sim
 * requires it, and so does ios/scripts/export-deck-vectors.cjs, which drives the real Deck through it to write the
 * traces the Swift port (ios/DeadwaxKit/Sources/DeadwaxCore/DeckRules.swift) is replayed against - so the traces
 * are made by the very harness the web's own tests trust.
 *
 *   const harness = require('./deckHarness.cjs').install(OUT)
 *
 * `OUT` is where deck.sim (or the exporter) compiled ui/src with tsc: lib/platter.ts, lib/deckVoice.ts and
 * player/deck.ts at least. install() puts the page's globals in place (performance, the timers, frames,
 * matchMedia, AudioContext, AudioWorkletNode, fetch), requires the compiled deck, and returns the harness: its
 * functions, and its state as properties (`harness.clock`, `harness.decodeMode`...) - the names deck.sim's checks
 * read and set, which it puts on globalThis as accessors (`HARNESS_STATE`) so its checks read as they always did.
 *
 * Two switches deck.sim never sets, for the exporter: `contextFollowsClock` - a context made while it is on reads
 * the harness's clock as its currentTime (seconds), so the deck's one clock maps page time onto context time as
 * the identity, and every stamp is the page's time over 1000 - and `decodeWith(bytes, done, failed)`, a decoder in
 * place of the fake one (the exporter's windows hold its own recipe's samples).
 */

'use strict'

const path = require('path')

/** The harness's state that the checks read and set - deck.sim makes each a global accessor. */
const HARNESS_STATE = [
  'clock', 'timers', 'frames', 'nextId', 'reduced', 'contexts', 'portMessages', 'decodeMode', 'decodesHeld', 'decodes',
  'workletFails', 'workletHeld', 'noWorklet', 'noScript', 'baseLatency', 'outputTimestampLead', 'outputLatency',
  'resumesHeld', 'suspendsHeld', 'decodeTone', 'scripts', 'asked', 'answer', 'windowSeconds', 'clockReads',
]

function install(OUT) {
  const H = {
    //? a clock, timers and frames the test moves on
    clock: 1000,
    timers: [],
    frames: [],
    nextId: 1,
    reduced: false,
    //? an audio context that records what is asked of it
    contexts: [],
    portMessages: [],
    //? how the fake browser decodes: at once ('now'), 300 ms later ('slow'), when the test says ('held' - the
    //? callbacks kept in `decodesHeld`), or refusing: the callback with null, with an Error, or by throwing
    decodeMode: 'now',
    decodesHeld: [],
    decodes: 0,
    //? whether the worklet's module refuses to load - or is held (its settlers kept here) as a slow one is
    workletFails: false,
    workletHeld: null,
    //? a context with no AudioWorklet (a page that isn't on HTTPS), or with no ScriptProcessorNode either - and
    //? the base latency a context says (2.0.0-player.40: its hardware's render), none unless a check sets one
    noWorklet: false,
    noScript: false,
    baseLatency: undefined,
    //? and, where it is set, a getOutputTimestamp() saying the render clock is that far ahead of the speaker - and
    //? an outputLatency (none unless a check sets one)
    outputTimestampLead: null,
    outputLatency: undefined,
    //? resumes that settle only when the test says (their settlers kept here), not at once - and suspends
    resumesHeld: null,
    suspendsHeld: null,
    //? decoded windows that hold a tone rather than silence, so what a voice plays can be compared - or, set
    //? to 'loud', a full-scale square wave
    decodeTone: false,
    //? the ScriptProcessorNodes made, and what is asked of them
    scripts: [],
    //? deadwax, answering the window route - windows of `windowSeconds` (40, or less for a hi-res song cut
    //? short by deadwax's budget), from where they were asked
    asked: [],
    answer: 'window',
    windowSeconds: 40,
    //? the clock's readings, counted where deck.js reaches them - when, and whether the mapping was held
    clockReads: [],
    //? the exporter's two switches (see the header): never set by deck.sim
    contextFollowsClock: false,
    decodeWith: null,
  }

  H.advance = (ms) => {
    const until = H.clock + ms
    for (;;) {
      H.timers.sort((a, b) => a.at - b.at)
      const due = H.timers.find((timer) => timer.at <= until)
      if (!due) break
      H.clock = due.at
      H.timers = H.timers.filter((timer) => timer !== due)
      due.run()
    }
    H.clock = until
  }
  H.runFrames = (count = 1) => {
    for (let i = 0; i < count; i++) {
      H.clock += 16
      H.advanceTimersOnly()
      const now = H.frames
      H.frames = []
      for (const frame of now) frame.run(H.clock)
    }
  }
  H.advanceTimersOnly = function advanceTimersOnly() {
    for (;;) {
      H.timers.sort((a, b) => a.at - b.at)
      const due = H.timers.find((timer) => timer.at <= H.clock)
      if (!due) break
      H.timers = H.timers.filter((timer) => timer !== due)
      due.run()
    }
  }
  globalThis.performance = { now: () => H.clock }
  globalThis.setTimeout = (run, ms = 0) => { const id = H.nextId++; H.timers.push({ id, at: H.clock + ms, run }); return id }
  globalThis.clearTimeout = (id) => { H.timers = H.timers.filter((timer) => timer.id !== id) }
  globalThis.requestAnimationFrame = (run) => { const id = H.nextId++; H.frames.push({ id, run }); return id }
  globalThis.cancelAnimationFrame = (id) => { H.frames = H.frames.filter((frame) => frame.id !== id) }
  globalThis.matchMedia = () => ({ get matches() { return H.reduced }, addEventListener() {}, removeEventListener() {} })
  globalThis.URL.createObjectURL = () => 'blob:deck-voice'

  class FakeNode {
    constructor() { this.port = { postMessage: (message) => H.portMessages.push(message), onmessage: null }; this.connections = [] }
    connect(to) { this.connections.push(to) }
    disconnect(from) { this.connections = from === undefined ? [] : this.connections.filter((to) => to !== from) }
  }
  class FakeScript {
    constructor(context, args) { this.context = context; this.args = args; this.connected = false; this.disconnected = false; this.onaudioprocess = null; this.connections = []; H.scripts.push(this) }
    connect(to) { this.connections.push(to); if (to === this.context.destination) this.connected = true }
    disconnect(from) { if (from === undefined) { this.disconnected = true; this.connections = [] } else this.connections = this.connections.filter((to) => to !== from) }
  }
  //? the browser asking a script voice for `blocks` blocks of its size (1024, or 512 since 2.0.0-player.40), each
  //? to play two blocks ahead of the context's clock, as a ScriptProcessorNode's are; what each was filled with
  //? comes back
  H.fill = (script, playbackTime) => {
    const size = script.args[0]
    const channels = [new Float32Array(size), new Float32Array(size)]
    script.onaudioprocess?.({ outputBuffer: { numberOfChannels: 2, length: size, getChannelData: (channel) => channels[channel] }, playbackTime })
    return { channels, playbackTime }
  }
  H.pump = (script, blocks = 1) => {
    const filled = []
    for (let block = 0; block < blocks; block++) {
      const context = script.context
      filled.push(H.fill(script, context.currentTime + (2 * script.args[0]) / 48000))
      context.currentTime += script.args[0] / 48000
    }
    return filled
  }
  //? the browser asking for blocks, with nothing compared - the script voice made ready
  H.playBlocksQuietly = (script, blocks) => void H.pump(script, blocks)
  //? a window's bytes say how long it is (100 kB a second), so the decode gives back that much audio
  const BYTES_A_SECOND = 100_000
  H.BYTES_A_SECOND = BYTES_A_SECOND
  class FakeContext {
    constructor() {
      this.state = 'suspended'
      this.currentTime = 0
      //? the exporter's: the context's clock is the page's, so the deck's mapping is the identity
      if (H.contextFollowsClock) Object.defineProperty(this, 'currentTime', { get: () => H.clock / 1000, set: () => undefined })
      this.calls = []
      this.sampleRate = 48000
      this.destination = { speakers: true }
      this.audioWorklet = H.noWorklet ? undefined : {
        addModule: () => (H.workletHeld ? new Promise((resolve, reject) => H.workletHeld.push({ resolve, reject }))
          : H.workletFails ? Promise.reject(new Error('SyntaxError: Unexpected token')) : Promise.resolve()),
      }
      if (H.noScript) this.createScriptProcessor = undefined
      if (H.baseLatency !== undefined) this.baseLatency = H.baseLatency
      if (H.outputLatency !== undefined) this.outputLatency = H.outputLatency
      if (H.outputTimestampLead !== null) {
        const lead = H.outputTimestampLead
        this.getOutputTimestamp = () => ({ contextTime: this.currentTime - lead, performanceTime: performance.now() })
      }
      H.contexts.push(this)
    }
    createScriptProcessor(size, inputs, outputs) { return new FakeScript(this, [size, inputs, outputs]) }
    addEventListener() {}
    resume() {
      this.calls.push('resume')
      //? a resume the test settles (`resumesHeld`), as a real one settles a moment after it is asked
      if (H.resumesHeld) return new Promise((resolve) => H.resumesHeld.push(() => { this.state = 'running'; resolve() }))
      this.state = 'running'
      return Promise.resolve()
    }
    suspend() {
      this.calls.push('suspend')
      if (H.suspendsHeld) return new Promise((resolve) => H.suspendsHeld.push(() => { this.state = 'suspended'; resolve() }))
      this.state = 'suspended'
      return Promise.resolve()
    }
    close() { this.calls.push('close'); this.state = 'closed'; return Promise.resolve() }
    decodeAudioData(bytes, done, failed) {
      H.decodes++
      //? the exporter's own windows
      if (H.decodeWith) return H.decodeWith(bytes, done, failed)
      const length = Math.round((bytes.byteLength / BYTES_A_SECOND) * 48000)
      const tone = () => Float32Array.from({ length }, (_, i) => 0.5 * Math.sin((2 * Math.PI * 440 * i) / 48000))
      //? 'loud' (2.0.0-player.35): a full-scale square wave, which the voice reads over full scale
      const square = () => Float32Array.from({ length }, (_, i) => (Math.floor((i * 880) / 48000) % 2 ? -1 : 1))
      const buffer = { numberOfChannels: 2, sampleRate: 48000, length, getChannelData: () => (H.decodeTone === 'loud' ? square() : H.decodeTone ? tone() : new Float32Array(length)) }
      if (H.decodeMode === 'null') return failed(null)
      if (H.decodeMode === 'error') return failed(new Error('EncodingError: Decoding failed'))
      if (H.decodeMode === 'throw') throw new TypeError('Not enough arguments')
      if (H.decodeMode === 'slow') return void setTimeout(() => done(buffer), 300)
      if (H.decodeMode === 'held') return void H.decodesHeld.push(() => done(buffer))
      done(buffer)
    }
  }
  globalThis.AudioContext = FakeContext
  globalThis.AudioWorkletNode = FakeNode
  H.FakeNode = FakeNode
  H.FakeScript = FakeScript
  H.FakeContext = FakeContext

  globalThis.fetch = async (url) => {
    H.asked.push(String(url))
    if (H.answer === 'not flac') return { ok: false, status: 415, headers: { get: () => null }, json: async () => ({ detail: "it isn't a FLAC file" }) }
    if (H.answer === 'down') return { ok: false, status: 503, headers: { get: () => null }, json: async () => ({ detail: 'its MP4 couldn\'t be made just now', scope: 'song' }) }
    const at = Number(new URL(String(url), 'http://x').searchParams.get('at'))
    const seconds = H.windowSeconds
    return { ok: true, status: 200, headers: { get: (name) => (name === 'x-deadwax-window' ? `${Math.round(at * 44100)}/${Math.round(seconds * 44100)}/44100` : null) }, arrayBuffer: async () => new ArrayBuffer(seconds * BYTES_A_SECOND) }
  }
  H.settle = () => new Promise((resolve) => setImmediate(resolve))

  H.deckModule = require(path.join(OUT, 'player/deck.js'))
  H.Deck = H.deckModule.Deck
  H.wakeDeckAudio = H.deckModule.wakeDeckAudio
  H.deckReport = H.deckModule.deckReport
  H.windowMargins = H.deckModule.windowMargins
  H.clockLib = require(path.join(OUT, 'lib/deckClock.js'))
  const realClockReading = H.clockLib.clockReading
  H.realClockReading = realClockReading
  H.clockLib.clockReading = (...args) => {
    H.clockReads.push({ at: args[1], held: args[3] })
    return realClockReading(...args)
  }
  H.readsBetween = (from, to) => H.clockReads.filter((read) => read.at > from && read.at <= to)
  const { SECONDS_PER_TURN } = require(path.join(OUT, 'lib/turntable.js'))

  H.fakeHost = function fakeHost(overrides = {}) {
    const host = {
      calls: [], shown: [], angle: 0, at: 60, isPlaying: true, listeners: new Set(),
      song: () => ({ id: 'time', length: 425, flac: true, kind: 'FLAC' }),
      playing() { return this.isPlaying },
      position() { return this.at },
      onPosition(listener) { this.listeners.add(listener); return () => this.listeners.delete(listener) },
      hold() { this.calls.push('hold'); this.isPlaying = false },
      resume() { this.calls.push('resume'); this.isPlaying = true },
      turnFace(degrees) { this.angle = degrees },
      show(at, scrubbing) { this.shown.push(at === null ? null : [Math.round(at * 100) / 100, scrubbing]) },
      grabbed() { this.calls.push('grabbed') },
      moveTo(seconds) { this.at = seconds; for (const listener of [...this.listeners]) listener(seconds) },
      ...overrides,
    }
    for (const name of ['playing', 'position', 'onPosition', 'hold', 'resume', 'turnFace', 'show', 'grabbed', 'moveTo']) host[name] = host[name].bind(host)
    return host
  }
  H.posted = (type) => H.portMessages.filter((message) => message.type === type)
  //? the song playing on: its position told every `every` ms, as the element's timeupdate tells it
  H.play = async (host, seconds, every = 250) => {
    for (let t = 0; t < seconds * 1000; t += every) {
      H.advance(every)
      host.moveTo(host.at + every / 1000)
      await H.settle()
    }
  }
  //? a flick of the hand backwards, a turn a second for its last 100 ms, from the song at `from`
  H.flickBack = (deck, from = 60) => {
    for (let ms = 0; ms <= 100; ms += 10) deck.hand(H.clock + ms, -(ms / 1000) * 2 * Math.PI, from - (ms / 1000) * SECONDS_PER_TURN)
    H.clock += 100
  }
  return H
}

module.exports = { install, HARNESS_STATE }
