/**
 * The test bench's songs (2.0.0-player.36): simple signals the turntable can be turned over, each a pure,
 * deterministic function of time defined ONCE here - the song the bench's own <audio> plays, the windows
 * the deck decodes (signalWindow), and what the ideal turntable reads (lib/../analysis.ts readExactly)
 * all come from the same definition. James: "I want to be able to use the turntable on a few different
 * samples. maybe a regular sine wave, a square wave, and maybe a few variations or combinations, just as
 * a sanity check".
 *
 * Each signal is made at a SOURCE rate - 44.1 kHz (a CD rip, the default), 48 kHz or 96 kHz (a hi-res
 * song) - SONG_SECONDS long, -12 dBFS at its peak unless it says otherwise (so the voice's limiter, whose
 * ceiling is -0.5 dBFS, never acts but where it should), and written as a 24-bit PCM WAV: decodeAudioData
 * takes that in Chromium, Firefox and WebKit (CoreAudio reads 24-bit integer WAV), and its quantization is
 * about -149 dBFS RMS (an LSB of 2^-23 over the root of 12) - some 130 dB under a -12 dBFS tone, and far
 * below anything the bench measures (the voice's own reading kernel leaks about 70 dB down).
 *
 * A periodic signal's samples repeat exactly every `period` samples (its frequencies are whole numbers of
 * Hz, so a whole number of cycles fits a whole number of samples): one stretch is worked out and copied.
 *
 * `exact(t, cutoff)` is the signal at song time t (seconds, any real number), with nothing in it at or
 * above `cutoff` Hz of the SONG's own frequencies: the ideal reader asks for what lands below the output's
 * Nyquist frequency at the speed it reads at - an ideal digital turntable is an ideal (brick-wall)
 * resampler, and can't put out more without folding it back down as an alias. A partial is kept whole
 * below the cutoff and left out at it, so at the song's own speed and rate every partial it has is there
 * (the top one a hair under Nyquist); a partial crossing the cutoff as the speed changes comes or goes at
 * the output's Nyquist frequency, far above hearing. For a sampled signal (pink noise, the aliased
 * square, a file) it is a long windowed sinc over the samples - the samples ARE the signal then - its
 * cutoff lowered with the ideal reader's.
 */

import { ApiError } from '../api/http'

/** Every signal the bench offers. */
export type SignalId =
  | 'sine440' | 'sine1k' | 'sine100' | 'sine5k' | 'fifth' | 'square' | 'saw' | 'triangle' | 'chord'
  | 'bursts' | 'clicks' | 'sweep' | 'pink' | 'silence' | 'sineFull' | 'squareAliased' | 'file'

/** The source rates a song can be made at. */
export const SOURCE_RATES = [44100, 48000, 96000] as const
export type SourceRate = (typeof SOURCE_RATES)[number]

/** How long a song is, seconds. */
export const SONG_SECONDS = 120

/** -12 dBFS, as a peak. */
export const LEVEL = Math.pow(10, -12 / 20)

/** Pink noise's level: -20 dBFS RMS. */
export const PINK_RMS = 0.1

/** The 24-bit WAV's full scale: a sample is a whole number of these. */
const FULL = 8388608

export interface SignalInfo {
  id: SignalId
  name: string
  /** what it shows, in one line */
  shows: string
  /** a reference of something wrong, never deadwax's */
  reference?: boolean
}

export const SIGNALS: readonly SignalInfo[] = [
  { id: 'sine440', name: 'Sine 440 Hz', shows: 'The reference: turned at any steady speed it must sound like one pure tone.' },
  { id: 'sine1k', name: 'Sine 1 kHz', shows: 'Where a wobble in the speed is easiest to hear.' },
  { id: 'sine100', name: 'Sine 100 Hz', shows: 'Low.' },
  { id: 'sine5k', name: 'Sine 5 kHz', shows: 'High - near the top when sped up.' },
  { id: 'fifth', name: 'Two sines, 440 + 660 Hz', shows: 'A fifth: two lines that must stay two lines.' },
  { id: 'square', name: 'Square 220 Hz', shows: 'Band-limited: odd harmonics only, up to the song\'s Nyquist frequency.' },
  { id: 'saw', name: 'Sawtooth 220 Hz', shows: 'Band-limited, every harmonic.' },
  { id: 'triangle', name: 'Triangle 220 Hz', shows: 'Band-limited.' },
  { id: 'chord', name: 'Chord: A major (220, 277.18, 329.63, 440 Hz)', shows: 'Something like an organ.' },
  { id: 'bursts', name: 'Tone bursts: 1 kHz, 50 ms on, 450 ms off', shows: 'Transients, and silence between.' },
  { id: 'clicks', name: 'Clicks: one every 0.5 s', shows: 'Band-limited clicks - a slowed record makes thumps, a sped one ticks.' },
  { id: 'sweep', name: 'Sweep 50 Hz to 10 kHz', shows: 'Logarithmic over the song: where you are is the pitch you hear.' },
  { id: 'pink', name: 'Pink noise, -20 dBFS RMS', shows: 'Broadband.' },
  { id: 'silence', name: 'Silence', shows: 'Anything heard while turning it is the bench\'s or deadwax\'s own.' },
  { id: 'sineFull', name: 'Sine 440 Hz at full scale', shows: 'Exercises the limiter (its ceiling is -0.5 dBFS).' },
  {
    id: 'squareAliased', name: 'Square 220 Hz, aliased on purpose', reference: true,
    shows: 'Reference only: a naive square, the way a cheap generator makes it - its aliases are in the song itself, so it sounds harsh and out of tune with itself, and they move with the speed like everything else in it.',
  },
  { id: 'file', name: 'Your own file', shows: 'A file picked on this device (anything the browser decodes): its first 2 minutes.' },
]

export interface Partial {
  hz: number
  amp: number
}

/** A song the bench made. */
export interface Signal {
  id: SignalId
  name: string
  /** the source rate, and how many samples a channel holds */
  rate: number
  length: number
  /** the song - one channel for a generated signal, as many as the file had (two at most) */
  channels: Float32Array[]
  /** the signal at song time `t` (s), nothing above `cutoff` Hz in it - see the module's note */
  exact: (t: number, cutoff: number) => number
  /** worked out from a definition (true) or read from samples (false) */
  analytic: boolean
  /** its partials as defined, for the sim's check that nothing band-limited goes past Nyquist - null
   *  where it isn't a sum of partials (clicks, sweep, noise, a file) */
  partials: Partial[] | null
  /** made with aliases on purpose */
  aliased: boolean
  /** whether "the sound that isn't the signal" can be measured on it: a tone or tones, not broadband */
  tonal: boolean
  /** its peak, as made (for the sim) */
  peak: number
}

/* ===== the pieces of the definitions ===== */

const TAU = 2 * Math.PI

/** Whether a partial at `hz` is kept under `cutoff`: whole below it, not at all at or above it - the
 *  ideal (brick-wall) resampler's rule. */
export function kept(hz: number, cutoff: number): number {
  return hz < cutoff ? 1 : 0
}

/** The fraction of the way round a cycle of `hz` at time `t` - kept small, so a sine of it is exact. */
function cycle(hz: number, t: number): number {
  const turns = hz * t
  return turns - Math.floor(turns)
}

/** Σ a_k w_k sin(k θ), k from 1 to the coefficients' length, by Clenshaw's recurrence: one sine and
 *  one cosine whatever the number of harmonics. */
function sineSeries(coefficients: Float64Array, theta: number, weightAt: ((k: number) => number) | null, top: number): number {
  const c2 = 2 * Math.cos(theta)
  let b1 = 0, b2 = 0
  for (let k = top; k >= 1; k--) {
    const a = coefficients[k - 1]! * (weightAt ? weightAt(k) : 1)
    const b0 = a + c2 * b1 - b2
    b2 = b1
    b1 = b0
  }
  return b1 * Math.sin(theta)
}

/** The modified Bessel function of the first kind, order 0 - for the Kaiser windows. */
export function besselI0(x: number): number {
  let sum = 1, term = 1
  for (let k = 1; k < 64; k++) {
    term *= (x / (2 * k)) * (x / (2 * k))
    sum += term
    if (term < 1e-17 * sum) break
  }
  return sum
}

const sinc = (x: number) => (x === 0 ? 1 : Math.sin(Math.PI * x) / (Math.PI * x))

/** The largest |f| over one period of a periodic function, by looking densely - deterministic. */
function peakOver(period: number, f: (t: number) => number, points = 16384): number {
  let peak = 0
  for (let i = 0; i < points; i++) peak = Math.max(peak, Math.abs(f((i / points) * period)))
  return peak
}

/* ----- a band-limited waveform of harmonics: square, sawtooth, triangle ----- */

function harmonics(kind: 'square' | 'saw' | 'triangle', fundamental: number, rate: number): Float64Array {
  //? every harmonic strictly below the source's Nyquist frequency, and no further
  const top = Math.ceil(rate / 2 / fundamental) - 1
  const out = new Float64Array(Math.max(0, top))
  for (let k = 1; k <= top; k++) {
    if (kind === 'square') out[k - 1] = k % 2 ? 4 / (Math.PI * k) : 0
    else if (kind === 'saw') out[k - 1] = ((k % 2 ? 1 : -1) * 2) / (Math.PI * k)
    else out[k - 1] = k % 2 ? ((((k - 1) / 2) % 2 ? -1 : 1) * 8) / (Math.PI * Math.PI * k * k) : 0
  }
  return out
}

function harmonicSignal(kind: 'square' | 'saw' | 'triangle', fundamental: number, rate: number) {
  const coefficients = harmonics(kind, fundamental, rate)
  const top = coefficients.length
  const raw = (t: number, cutoff: number) => {
    const theta = TAU * cycle(fundamental, t)
    if (!(cutoff < Infinity) || cutoff > top * fundamental) return sineSeries(coefficients, theta, null, top)
    //? every harmonic under the cutoff, and none from it on
    const last = Math.min(top, Math.ceil(cutoff / fundamental) - 1)
    return sineSeries(coefficients, theta, null, last)
  }
  const scale = LEVEL / peakOver(1 / fundamental, (t) => raw(t, Infinity))
  const partials: Partial[] = []
  coefficients.forEach((a, i) => { if (a) partials.push({ hz: (i + 1) * fundamental, amp: Math.abs(a) * scale }) })
  return { exact: (t: number, cutoff: number) => scale * raw(t, cutoff), partials }
}

/* ----- clicks: a band-limited impulse every half second ----- */

/** The clicks' kernel: a sinc whose cutoff is CLICK_CUTOFF of the source rate, under a Kaiser window
 *  CLICK_HALF samples either side (beta CLICK_BETA: about 80 dB down past it) - so nothing of a click
 *  reaches the source's Nyquist frequency. */
export const CLICK_CUTOFF = 0.46
export const CLICK_HALF = 32
const CLICK_BETA = 8
const CLICK_PERIOD = 0.5
const CLICK_FIRST = 0.25

function clickSignal(rate: number) {
  const fc = CLICK_CUTOFF * rate
  const halfS = CLICK_HALF / rate
  const norm = besselI0(CLICK_BETA)
  const exact = (t: number, cutoff: number) => {
    //? band-limited further for the ideal reader: the kernel stretched, its height scaled so its low
    //? frequencies are what they were
    const c = Math.min(fc, cutoff)
    const stretch = fc / c
    const j = Math.round((t - CLICK_FIRST) / CLICK_PERIOD)
    const tau = t - (CLICK_FIRST + j * CLICK_PERIOD)
    const half = halfS * stretch
    if (Math.abs(tau) >= half) return 0
    const edge = tau / half
    const window = besselI0(CLICK_BETA * Math.sqrt(Math.max(0, 1 - edge * edge))) / norm
    return LEVEL * (c / fc) * sinc(2 * c * tau) * window
  }
  return { exact }
}

/* ----- the sweep ----- */

const SWEEP_FROM = 50
const SWEEP_TO = 10000

function sweepAt(t: number): { phase: number; hz: number } {
  const L = Math.log(SWEEP_TO / SWEEP_FROM)
  const T = SONG_SECONDS
  const grow = Math.exp((L * t) / T)
  //? the phase in turns, kept to its fraction
  const turns = (SWEEP_FROM * T * (grow - 1)) / L
  return { phase: TAU * (turns - Math.floor(turns)), hz: SWEEP_FROM * grow }
}

/* ----- tone bursts ----- */

const BURST_HZ = 1000
const BURST_ON = 0.05
const BURST_PERIOD = 0.5
/** each burst's edges: a raised cosine this long, so a burst has no splatter of its own */
const BURST_RAMP = 0.0025

function burstEnvelope(t: number): number {
  const u = t - Math.floor(t / BURST_PERIOD) * BURST_PERIOD
  if (u >= BURST_ON) return 0
  if (u < BURST_RAMP) return 0.5 * (1 - Math.cos((Math.PI * u) / BURST_RAMP))
  if (u > BURST_ON - BURST_RAMP) return 0.5 * (1 - Math.cos((Math.PI * (BURST_ON - u)) / BURST_RAMP))
  return 1
}

/* ----- pink noise, the aliased square, and a reader of samples ----- */

/** A small seeded random source (mulberry32): the same numbers every time. */
export function seeded(seed: number): () => number {
  let a = seed >>> 0
  return () => {
    a = (a + 0x6d2b79f5) >>> 0
    let t = a
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

/** The windowed sinc the ideal reader reads samples through: SINC_ZEROS zero crossings either side,
 *  under a Kaiser window (beta 9: about 90 dB down), tabled SINC_STEPS a crossing and read between. */
const SINC_ZEROS = 48
const SINC_STEPS = 2048
const SINC_BETA = 9
let sincTable: Float64Array | null = null

function sincKernel(): Float64Array {
  if (sincTable) return sincTable
  const table = new Float64Array(SINC_ZEROS * SINC_STEPS + 2)
  const norm = besselI0(SINC_BETA)
  for (let i = 0; i <= SINC_ZEROS * SINC_STEPS; i++) {
    const x = i / SINC_STEPS
    const edge = x / SINC_ZEROS
    table[i] = sinc(x) * (besselI0(SINC_BETA * Math.sqrt(Math.max(0, 1 - edge * edge))) / norm)
  }
  sincTable = table
  return table
}

/** The signal held in `samples` (at `rate`) at song time t, band-limited to `cutoff` Hz: a long windowed
 *  sinc, stretched (its cutoff lowered) where the cutoff is under the samples' own Nyquist frequency. */
export function sampledReader(samples: Float32Array, rate: number): (t: number, cutoff: number) => number {
  const table = sincKernel()
  const nyquist = rate / 2
  return (t, cutoff) => {
    const scale = Math.min(1, cutoff / nyquist)
    if (!(scale > 0)) return 0
    const at = t * rate
    const reach = SINC_ZEROS / scale
    const first = Math.max(0, Math.ceil(at - reach))
    const last = Math.min(samples.length - 1, Math.floor(at + reach))
    const steps = scale * SINC_STEPS
    let sum = 0
    for (let n = first; n <= last; n++) {
      const u = Math.abs(at - n) * steps
      const whole = Math.floor(u)
      const weight = table[whole]! + (table[whole + 1]! - table[whole]!) * (u - whole)
      sum += samples[n]! * weight
    }
    return sum * scale
  }
}

/* ===== making a song ===== */

export interface MakeOptions {
  /** seconds of it (SONG_SECONDS); the sim makes shorter ones */
  seconds?: number
  /** a file's decoded channels at `rate`, for 'file' */
  file?: { name: string; channels: Float32Array[] } | null
  /** let the page breathe now and then while a long song is made */
  pause?: () => Promise<void>
}

/** A whole number's greatest common divisor. */
function gcd(a: number, b: number): number {
  while (b) [a, b] = [b, a % b]
  return a
}

/**
 * The song for `id` at the source `rate`: its samples, and its exact definition. Periodic signals are
 * worked out over one stretch that repeats exactly and copied; the rest sample by sample.
 */
export async function makeSignal(id: SignalId, rate: number, options: MakeOptions = {}): Promise<Signal> {
  const seconds = options.seconds ?? SONG_SECONDS
  const info = SIGNALS.find((one) => one.id === id)!
  const length = Math.round(seconds * rate)
  const pause = options.pause ?? (() => Promise.resolve())
  const out = new Float32Array(length)

  //? `exact` for every analytic signal, and the stretch it repeats over (samples), if it does
  let exact: (t: number, cutoff: number) => number
  let period = 0
  let partials: Partial[] | null = null
  let tonal = true
  let aliased = false

  const sine = (hz: number, amp: number) => {
    period = rate / gcd(rate, hz)
    partials = [{ hz, amp }]
    exact = (t, cutoff) => amp * kept(hz, cutoff) * Math.sin(TAU * cycle(hz, t))
  }

  switch (id) {
    case 'sine440': sine(440, LEVEL); break
    case 'sine1k': sine(1000, LEVEL); break
    case 'sine100': sine(100, LEVEL); break
    case 'sine5k': sine(5000, LEVEL); break
    case 'sineFull': sine(440, 1); break
    case 'fifth': {
      const unit = (t: number) => Math.sin(TAU * cycle(440, t)) + Math.sin(TAU * cycle(660, t))
      const amp = LEVEL / peakOver(1 / 220, unit)
      period = rate / gcd(rate, 220)
      partials = [{ hz: 440, amp }, { hz: 660, amp }]
      exact = (t, cutoff) => amp * (kept(440, cutoff) * Math.sin(TAU * cycle(440, t)) + kept(660, cutoff) * Math.sin(TAU * cycle(660, t)))
      break
    }
    case 'square':
    case 'saw':
    case 'triangle': {
      const made = harmonicSignal(id, 220, rate)
      exact = made.exact
      partials = made.partials
      period = rate / gcd(rate, 220)
      break
    }
    case 'chord': {
      //? four equal sines whose frequencies share no whole period: each a quarter of the level, so the
      //? peak never passes it (they come close to lining up, now and then, over two minutes)
      const notes = [220, 277.18, 329.63, 440]
      const amp = LEVEL / notes.length
      partials = notes.map((hz) => ({ hz, amp }))
      exact = (t, cutoff) => {
        let sum = 0
        for (const hz of notes) sum += kept(hz, cutoff) * Math.sin(TAU * cycle(hz, t))
        return amp * sum
      }
      break
    }
    case 'bursts':
      period = Math.round(BURST_PERIOD * rate)
      partials = [{ hz: BURST_HZ, amp: LEVEL }]
      exact = (t, cutoff) => LEVEL * kept(BURST_HZ, cutoff) * burstEnvelope(t) * Math.sin(TAU * cycle(BURST_HZ, t))
      break
    case 'clicks':
      period = Math.round(CLICK_PERIOD * rate)
      tonal = false
      exact = clickSignal(rate).exact
      break
    case 'sweep':
      exact = (t, cutoff) => {
        if (t < 0 || t > SONG_SECONDS) return 0
        const { phase, hz } = sweepAt(t)
        return LEVEL * kept(hz, cutoff) * Math.sin(phase)
      }
      break
    case 'silence':
      tonal = false
      period = 1
      exact = () => 0
      break
    case 'pink': {
      tonal = false
      //? white noise from a fixed seed through Paul Kellet's pink filter, then scaled to PINK_RMS
      const random = seeded(0x1d6e7)
      let b0 = 0, b1 = 0, b2 = 0, b3 = 0, b4 = 0, b5 = 0, b6 = 0
      for (let n = 0; n < length; n++) {
        const white = random() * 2 - 1
        b0 = 0.99886 * b0 + white * 0.0555179
        b1 = 0.99332 * b1 + white * 0.0750759
        b2 = 0.969 * b2 + white * 0.153852
        b3 = 0.8665 * b3 + white * 0.3104856
        b4 = 0.55 * b4 + white * 0.5329522
        b5 = -0.7616 * b5 - white * 0.016898
        out[n] = b0 + b1 + b2 + b3 + b4 + b5 + b6 + white * 0.5362
        b6 = white * 0.115926
        if (n % 1048576 === 1048575) await pause()
      }
      let mean = 0
      for (let n = 0; n < length; n++) mean += out[n]!
      mean /= length || 1
      let energy = 0
      for (let n = 0; n < length; n++) {
        out[n] = out[n]! - mean
        energy += out[n]! * out[n]!
      }
      const scale = PINK_RMS / Math.sqrt(energy / (length || 1) || 1)
      for (let n = 0; n < length; n++) out[n] = out[n]! * scale
      exact = sampledReader(out, rate)
      break
    }
    case 'squareAliased': {
      //? a naive square, sampled: +level for the first half of each cycle, -level for the second, 0 on
      //? the edges - its harmonics run on past Nyquist and fold back down as aliases
      aliased = true
      for (let n = 0; n < length; n++) {
        const m = (220 * n) % rate
        out[n] = m === 0 || 2 * m === rate ? 0 : m < rate / 2 ? LEVEL : -LEVEL
      }
      const list: Partial[] = []
      for (let k = 1; k * 220 < 4 * rate; k += 2) list.push({ hz: k * 220, amp: (4 * LEVEL) / (Math.PI * k) })
      partials = list
      exact = sampledReader(out, rate)
      break
    }
    case 'file': {
      const file = options.file
      if (!file || !file.channels.length) throw new Error('no file chosen')
      tonal = false
      const channels = file.channels.slice(0, 2).map((channel) => Float32Array.from(channel.subarray(0, Math.min(channel.length, length))))
      const peak = channels.reduce((most, channel) => channel.reduce((m, v) => Math.max(m, Math.abs(v)), most), 0)
      return {
        id, name: file.name || info.name, rate, length: channels[0]!.length, channels, exact: sampledReader(channels[0]!, rate),
        analytic: false, partials: null, aliased: false, tonal, peak,
      }
    }
  }

  const analytic = id !== 'pink' && id !== 'squareAliased'
  if (analytic) {
    if (period > 0 && period <= length) {
      const tile = new Float32Array(period)
      for (let n = 0; n < period; n++) tile[n] = exact!(n / rate, Infinity)
      for (let at = 0; at < length; at += period) out.set(at + period <= length ? tile : tile.subarray(0, length - at), at)
    } else {
      for (let n = 0; n < length; n++) {
        out[n] = exact!(n / rate, Infinity)
        if (n % 262144 === 262143) await pause()
      }
    }
  }
  let peak = 0
  for (let n = 0; n < length; n++) peak = Math.max(peak, Math.abs(out[n]!))
  return { id, name: info.name, rate, length, channels: [out], exact: exact!, analytic, partials, aliased, tonal, peak }
}

/* ===== the WAV ===== */

/**
 * A 24-bit PCM WAV of `channels` at `rate`, samples [from, to). Each sample rounded to the nearest of
 * 2^23 steps a side and held to [-1, 1 - 2^-23] - so a WAV read back gives every sample to within half a
 * step (2^-24), and +1.0 is the largest value 24 bits hold.
 */
export function wavBytes(channels: Float32Array[], rate: number, from = 0, to = channels[0]?.length ?? 0): ArrayBuffer {
  const count = channels.length
  const frames = Math.max(0, to - from)
  const bytes = frames * count * 3
  const buffer = new ArrayBuffer(44 + bytes)
  const view = new DataView(buffer)
  const text = (at: number, word: string) => { for (let i = 0; i < word.length; i++) view.setUint8(at + i, word.charCodeAt(i)) }
  text(0, 'RIFF')
  view.setUint32(4, 36 + bytes, true)
  text(8, 'WAVE')
  text(12, 'fmt ')
  view.setUint32(16, 16, true)
  view.setUint16(20, 1, true)
  view.setUint16(22, count, true)
  view.setUint32(24, rate, true)
  view.setUint32(28, rate * count * 3, true)
  view.setUint16(32, count * 3, true)
  view.setUint16(34, 24, true)
  text(36, 'data')
  view.setUint32(40, bytes, true)
  const out = new Uint8Array(buffer, 44)
  let at = 0
  for (let n = from; n < to; n++) {
    for (let c = 0; c < count; c++) {
      let q = Math.round(channels[c]![n]! * FULL)
      if (q > FULL - 1) q = FULL - 1
      else if (q < -FULL) q = -FULL
      if (q < 0) q += 0x1000000
      out[at++] = q & 0xff
      out[at++] = (q >> 8) & 0xff
      out[at++] = (q >> 16) & 0xff
    }
  }
  return buffer
}

/** A WAV read back - 16-, 24- or 32-bit integer PCM, or 32-bit float - as channels of floats. */
export function readWav(buffer: ArrayBuffer): { rate: number; channels: Float32Array[] } {
  const view = new DataView(buffer)
  const text = (at: number) => String.fromCharCode(view.getUint8(at), view.getUint8(at + 1), view.getUint8(at + 2), view.getUint8(at + 3))
  if (text(0) !== 'RIFF' || text(8) !== 'WAVE') throw new Error('not a WAV')
  let at = 12
  let format = 0, count = 0, rate = 0, bits = 0
  while (at + 8 <= buffer.byteLength) {
    const id = text(at)
    const size = view.getUint32(at + 4, true)
    if (id === 'fmt ') {
      format = view.getUint16(at + 8, true)
      count = view.getUint16(at + 10, true)
      rate = view.getUint32(at + 12, true)
      bits = view.getUint16(at + 22, true)
    } else if (id === 'data') {
      const width = bits / 8
      const frames = Math.floor(size / (width * count))
      const channels = Array.from({ length: count }, () => new Float32Array(frames))
      let p = at + 8
      for (let n = 0; n < frames; n++) {
        for (let c = 0; c < count; c++) {
          let v: number
          if (format === 3) v = view.getFloat32(p, true)
          else if (bits === 16) v = view.getInt16(p, true) / 32768
          else if (bits === 24) {
            let q = view.getUint8(p) | (view.getUint8(p + 1) << 8) | (view.getUint8(p + 2) << 16)
            if (q & 0x800000) q -= 0x1000000
            v = q / FULL
          } else v = view.getInt32(p, true) / 2147483648
          channels[c]![n] = v
          p += width
        }
      }
      return { rate, channels }
    }
    at += 8 + size + (size % 2)
  }
  throw new Error('a WAV with no data')
}

/* ===== the windows the deck decodes ===== */

/** What scrubWindow answers, and the bench's window source too. */
export interface BenchWindow {
  bytes: ArrayBuffer
  first: number
  samples: number
  rate: number
}

/**
 * The deck's window of the song: `seconds` of it from `from` - exactly the song's samples
 * [first, first + samples), first the sample nearest `from`, cut short at the song's end - as a 24-bit
 * WAV the deck decodes with decodeAudioData exactly as it decodes deadwax's FLAC. Past the end, a 416,
 * as deadwax says it.
 */
export function signalWindow(signal: Signal, from: number, seconds: number): BenchWindow {
  const first = Math.max(0, Math.round(from * signal.rate))
  if (first >= signal.length) throw new ApiError(416, 'that is past the end of the song', 'past the end')
  const end = Math.min(signal.length, first + Math.round(seconds * signal.rate))
  return { bytes: wavBytes(signal.channels, signal.rate, first, end), first, samples: end - first, rate: signal.rate }
}
