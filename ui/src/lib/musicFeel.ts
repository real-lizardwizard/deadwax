/**
 * The music's feel (2.0.0-player.20), for the desktop visualizer - a port of the musicFeel() block of
 * the canvas board DesktopVisualizer.dc.html, which was written "self-contained ... so the real player
 * can call it unchanged". PURE: no audio, no DOM - ui/test/musicfeel.sim.cjs drives it with the board's
 * own three synthetic songs and a click track.
 *
 * It works only from what an AnalyserNode gives each frame (player/vizAudio.ts makes these from the
 * silent copy of the song it analyses): `spectrum` = 64 bands, 0-1, log-spaced from 30 Hz to 16 kHz
 * and compressed like getByteFrequencyData / 255; `waveform` = the time-domain samples, -1..1. Its
 * readings are slow on purpose, so the feel drifts as a song goes on instead of flickering:
 *
 *   aggr   0 smooth .. 1 aggressive, a blend of onsets per second (peaks in spectral flux),
 *          brightness (the spectral centroid, and the share of energy above about 2 kHz),
 *          noisiness (spectral flatness in the mids and highs - distorted guitars are noisy, pads
 *          are tonal) and transient sharpness (the waveform's crest factor), each followed over
 *          about 5 s
 *   bpm    from autocorrelating an onset-strength envelope over the last 8 s, 60-200 bpm; conf says
 *          how sure it is, and while it is unsure the speeds keep a neutral pace
 *   tempo  a speed factor for the flowing styles (0.65-1.5)
 *   beats  beats per second for the Mandala's phrase clock, halved or doubled into 0.9-2.2
 *
 * It holds everything during silence or a pause, so a stop never reads as "smooth". The visualizer
 * reads the feel to shape what it draws (James: metal pointy and aggressive, "Comfortably Numb" smooth
 * and flowy) and the tempo to set how fast it moves - never to flash on a beat.
 */

/** How many bands the spectrum has. */
export const BANDS = 64
/** The onset-strength envelope: samples a second, and how many are kept (8 s). */
export const ENVELOPE_RATE = 60
export const ENVELOPE_LENGTH = 480

export interface Feel {
  /** last frame's spectrum, for the flux */
  prev: Float32Array
  env: Float32Array
  envAt: number
  envT: number
  envAcc: number
  acfBuf: Float32Array
  acf: Float32Array
  /** seconds until the tempo is looked for again */
  acfIn: number
  rms: Float32Array
  rmsAt: number
  onsets: number[]
  lastOnset: number
  above: boolean
  fMean: number
  fDev: number
  /** seconds of music heard (silence doesn't count) */
  clock: number
  density: number
  centroid: number
  high: number
  flat: number
  crest: number
  aggr: number
  bpm: number
  bpmRaw: number
  conf: number
  confRaw: number
  beats: number
  tempo: number
}

/** A feel before any music: in between, a neutral 110 bpm, unsure. */
export function newFeel(): Feel {
  return {
    prev: new Float32Array(BANDS), env: new Float32Array(ENVELOPE_LENGTH), envAt: 0, envT: 0, envAcc: 0,
    acfBuf: new Float32Array(ENVELOPE_LENGTH), acf: new Float32Array(128), acfIn: 0,
    rms: new Float32Array(30), rmsAt: 0, onsets: [], lastOnset: -1, above: false, fMean: 0, fDev: 0.01,
    clock: 0, density: 3, centroid: 0.4, high: 0.15, flat: 0.5, crest: 2,
    aggr: 0.45, bpm: 110, bpmRaw: 110, conf: 0, confRaw: 0, beats: 1.83, tempo: 1,
  }
}

/** Hermite smoothstep from a to b. */
export function smooth(a: number, b: number, x: number): number {
  const t = Math.max(0, Math.min(1, (x - a) / (b - a)))
  return t * t * (3 - 2 * t)
}

/** One frame of the music, `dt` seconds after the last: the feel, moved on (in place) and returned. */
export function musicFeel(F: Feel, spectrum: ArrayLike<number>, waveform: ArrayLike<number>, dt: number): Feel {
  let sum = 0, sum2 = 0, cen = 0, hi2 = 0, flux = 0
  for (let i = 0; i < BANDS; i++) {
    const s = spectrum[i] ?? 0
    sum += s
    sum2 += s * s
    cen += i * s
    if (i >= 43) hi2 += s * s
    flux += Math.max(0, s - F.prev[i]!)
    F.prev[i] = s
  }
  //? silence, or a pause: hold everything
  if (sum / BANDS < 0.03) return F
  F.clock += dt
  //? the onset-strength envelope, 60 samples a second, the last 8 s kept
  F.envAcc += flux
  F.envT += dt
  if (F.envT >= 1 / ENVELOPE_RATE) {
    const n = Math.floor(F.envT * ENVELOPE_RATE)
    for (let k = 0; k < n; k++) {
      F.env[F.envAt] = F.envAcc / n
      F.envAt = (F.envAt + 1) % F.env.length
    }
    F.envT -= n / ENVELOPE_RATE
    F.envAcc = 0
  }
  //? onsets: the flux rising through a threshold that follows the music's own level
  const a1 = 1 - Math.exp(-dt / 1.0)
  const on = flux > F.fMean + 1.5 * F.fDev + 0.02
  if (on && !F.above && F.clock - F.lastOnset > 0.06) {
    F.onsets.push(F.clock)
    F.lastOnset = F.clock
  }
  F.above = on
  F.fMean += (flux - F.fMean) * a1
  F.fDev += (Math.abs(flux - F.fMean) - F.fDev) * a1
  while (F.onsets.length && F.onsets[0]! < F.clock - 4) F.onsets.shift()
  const density = F.onsets.length / Math.min(4, Math.max(1, F.clock))
  //? brightness, noisiness and transients
  const centroid = cen / sum / 63
  const high = hi2 / Math.max(sum2, 1e-6)
  let lg = 0, ar = 0
  for (let i = 20; i < BANDS; i++) {
    const s = spectrum[i] ?? 0
    const p = s * s + 1e-4
    lg += Math.log(p)
    ar += p
  }
  const flat = Math.exp(lg / 44) / (ar / 44)
  let pk = 0, ms = 0
  const samples = waveform.length || 1
  for (let j = 0; j < waveform.length; j++) {
    const v = waveform[j]!
    pk = Math.max(pk, Math.abs(v))
    ms += v * v
  }
  const rms = Math.sqrt(ms / samples)
  F.rms[F.rmsAt] = rms
  F.rmsAt = (F.rmsAt + 1) % F.rms.length
  let rMax = 0, rSum = 0
  for (let k = 0; k < F.rms.length; k++) {
    rMax = Math.max(rMax, F.rms[k]!)
    rSum += F.rms[k]!
  }
  const crest = 0.5 * pk / Math.max(rms, 1e-4) + 0.5 * rMax / Math.max(rSum / F.rms.length, 1e-4)
  const a5 = 1 - Math.exp(-dt / 5)
  F.density += (density - F.density) * a5
  F.centroid += (centroid - F.centroid) * a5
  F.high += (high - F.high) * a5
  F.flat += (flat - F.flat) * a5
  F.crest += (crest - F.crest) * a5
  const score = 0.3 * smooth(1.5, 8, F.density)
    + 0.15 * smooth(0.3, 0.55, F.centroid)
    + 0.15 * smooth(0.06, 0.3, F.high)
    + 0.25 * smooth(0.3, 0.75, F.flat)
    + 0.15 * smooth(1.6, 2.6, F.crest)
  F.aggr += (score - F.aggr) * (1 - Math.exp(-dt / 2))
  //? the tempo, looked for four times a second
  F.acfIn -= dt
  if (F.acfIn <= 0 && F.clock > 3) {
    F.acfIn = 0.25
    tempoFromOnsets(F)
  }
  F.conf += (F.confRaw - F.conf) * (1 - Math.exp(-dt / 2))
  if (F.confRaw > 0.2) {
    const lb = Math.log2(F.bpm)
    F.bpm = Math.pow(2, lb + (Math.log2(F.bpmRaw) - lb) * (1 - Math.exp(-dt / 1.5)))
  }
  const eff = 110 + (F.bpm - 110) * smooth(0.2, 0.6, F.conf)
  let beats = eff / 60
  while (beats > 2.2) beats /= 2
  while (beats < 0.9) beats *= 2
  F.beats += (beats - F.beats) * (1 - Math.exp(-dt / 2))
  const tempo = Math.max(0.65, Math.min(1.5, eff / 115))
  F.tempo += (tempo - F.tempo) * (1 - Math.exp(-dt / 2))
  return F
}

/**
 * The strongest repeat in the onset envelope between 60 and 200 bpm. Each lag's autocorrelation is
 * weighed by a broad preference for 100-130 bpm (so an ambiguous choice lands near there); when the
 * tempo twice as fast is strong enough (see below), the faster reading wins; the peak is then refined
 * between samples. Confidence is how tall that peak stands.
 *
 * The envelope is first smoothed over about 80 ms (five samples): that removes the pulse of fast
 * subdivisions such as double-kick 16ths, which otherwise repeat at every multiple of a 16th and make
 * 120 look as likely as 180, and leaves the beats and backbeats to count.
 */
export function tempoFromOnsets(F: Feel): void {
  const N = F.env.length, x = F.acfBuf, acf = F.acf
  let mean = 0
  for (let k = 0; k < N; k++) {
    let s = 0
    for (let j = -2; j <= 2; j++) s += F.env[(F.envAt + k + j + N) % N]!
    x[k] = s / 5
    mean += x[k]!
  }
  mean /= N
  let a0 = 0
  for (let k = 0; k < N; k++) {
    x[k] = x[k]! - mean
    a0 += x[k]! * x[k]!
  }
  if (a0 < 1e-9) return
  a0 /= N
  for (let L = 16; L <= 124; L++) {
    let s = 0
    for (let k = 0; k + L < N; k++) s += x[k]! * x[k + L]!
    acf[L] = s / (N - L) / a0
  }
  let best = 0, bestL = 0
  for (let L = 18; L <= 60; L++) {
    if (acf[L]! < acf[L - 1]! || acf[L]! < acf[L + 1]!) continue
    const lb = Math.log2(3600 / L / 115) / 1.3
    const sc = acf[L]! * Math.exp(-0.5 * lb * lb)
    if (sc > best) {
      best = sc
      bestL = L
    }
  }
  if (!bestL) {
    F.confRaw = 0
    return
  }
  //? the faster reading needs 75% of the slower one's strength in sparse music, easing to 40% when
  //? onsets are dense (4-8 a second), because busy music is felt at its fast pulse: metal at 180 with a
  //? backbeat every other beat otherwise reads as its half-time 90
  let L = bestL
  const half = Math.round(L / 2)
  const need = 0.75 - 0.35 * smooth(4, 8, F.density)
  if (half >= 18 && Math.max(acf[half - 1]!, acf[half]!, acf[half + 1]!) >= need * acf[L]!) {
    L = acf[half - 1]! > acf[half]! ? half - 1 : acf[half + 1]! > acf[half]! ? half + 1 : half
  }
  const y0 = acf[L - 1]!, y1 = acf[L]!, y2 = acf[L + 1]!, den = y0 - 2 * y1 + y2
  const Lp = L + (Math.abs(den) > 1e-6 ? Math.max(-0.5, Math.min(0.5, 0.5 * (y0 - y2) / den)) : 0)
  F.bpmRaw = 3600 / Lp
  F.confRaw = Math.max(0, Math.min(1, (y1 - 0.08) / 0.3))
}

/** What the visualizer shows under its style list: how it hears the music right now. */
export function feelWords(F: Feel): string {
  const feel = F.aggr < 0.34 ? 'smooth' : F.aggr < 0.67 ? 'in between' : 'aggressive'
  return `${feel} · ${F.conf > 0.35 ? `${Math.round(F.bpm)} bpm` : 'finding the tempo'}`
}
