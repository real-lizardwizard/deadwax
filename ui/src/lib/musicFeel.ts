/**
 * The music's feel (2.0.0-player.20), for the desktop visualizer - a port of the musicFeel() block of
 * the canvas board DesktopVisualizer.dc.html, which was written "self-contained ... so the real player
 * can call it unchanged". PURE: no audio, no DOM - ui/test/musicfeel.sim.cjs drives it with the board's
 * own three synthetic songs and a click track, and holds its tuning to readings taken from real music.
 *
 * It works only from what an AnalyserNode gives each frame (player/vizAudio.ts makes it from the
 * silent copy of the song it analyses): `spectrum` = 64 bands, 0-1, log-spaced from 30 Hz to 16 kHz
 * and scaled like getByteFrequencyData / 255 - so a band's value is its level in dB, -90 dB at 0 and
 * -22 dB at 1. Its readings are slow on purpose, so the feel drifts as a song goes on instead of
 * flickering:
 *
 *   aggr   0 smooth .. 1 aggressive, a blend of three readings, each followed over about 5 s
 *          (FEEL_SCORE): onsets per second (peaks in spectral flux, counted on a grid of 60 a second,
 *          so a faster screen counts no more - a slower one sees fewer, below); the share of the sound
 *          above about 2 kHz; and noisiness (spectral flatness in the mids and highs - distorted
 *          guitars and cymbals are noisy, pads and pianos are tonal). The last two are read in a
 *          window LEVEL_WINDOW deep below the loudest band, so how loud a record was mastered hardly
 *          moves them (LEVEL_WINDOW says how far that holds)
 *   bpm    from autocorrelating an onset-strength envelope over the last 8 s, 60-200 bpm; conf says
 *          how sure it is, and while it is unsure the speeds keep a neutral pace
 *   tempo  a speed factor for the flowing styles (0.65-1.5)
 *   beats  beats per second for the Mandala's phrase clock, halved or doubled into 0.9-2.2
 *
 * TUNED ON REAL MUSIC (2.0.0-player.34; James: "the feel seems to always say 'in between'"). The
 * board's weights and ranges were set on its three synthetic songs, and on real spectra 98% of the
 * score sat between 0.03 and 0.76: heavy music read "aggressive" only 28% of the time. FEEL_SCORE's
 * ranges now run from what calm music gives to what heavy music gives, measured through this same
 * pipeline on real tracks (tests/fixtures/feel/real-tracks.json holds the numbers, and the sim holds
 * the tuning to them). Gone with the retuning: the waveform's crest factor (a 28 ms, gain-controlled,
 * limited waveform told calm from heavy not at all) and the spectral centroid (it said nothing the
 * share above 2 kHz didn't). The tuning was measured at 60 frames a second; the onsets are counted on
 * that grid at any frame rate above it, but below it the analyser is read less often and an onset
 * between two reads is lost in their flux. At 30 (a battery saver can halve a page's frame rate:
 * Chrome's Energy Saver does) about a third of the onsets go unseen on a typical real track, from a
 * tenth to a half, and the word moves a long way: heavy music, 87% aggressive on average at 60, is 59%
 * aggressive at 30 (Burn The World Waltz 99% to 26%, Metalmania 55% to none), between music drifts
 * smooth (Happy Alley 89% in between to all smooth), calm music stays smooth. Not compensated - the
 * variant tried (a late frame's whole flux tested in its first sample) brought heavy music back but read
 * between music more aggressive than at 60 - and the guide says what 30 does.
 *
 * It holds everything during silence or a pause, so a stop never reads as "smooth". The visualizer
 * reads the feel to shape what it draws (James: metal pointy and aggressive, "Comfortably Numb" smooth
 * and flowy) and the tempo to set how fast it moves - never to flash on a beat.
 */

/** How many bands the spectrum has. */
export const BANDS = 64
/** A band this close to the analyser's floor (2 dB of its 68) is nothing: brightness and noisiness never
 *  count it, however quiet the music round it. */
export const LIFT_FLOOR = 0.03
/**
 * How deep a window below the loudest band brightness and noisiness are read in, as a share of the
 * analyser's 68 dB (0.7: about 48 dB): a band counts by how far it stands above the window's bottom,
 * so a record mastered louder or quieter reads much the same - the bottom moves with the loudest band.
 * Two places it can't: where the loudest band is quieter than about -40 dB (very quiet music, or a
 * quiet passage of it) the bottom stops at LIFT_FLOOR, and the music reads a little smoother; and where
 * a loud record's loudest bands pass the analyser's -22 dB top they read as -22, the window sits too
 * low, and it reads a little more aggressive. Measured on 27 real tracks: 3 dB either way moves the
 * middle of aggr 0.01 on average (0.04 at most); 6 dB either way 0.025 on average, 0.11 at most
 * (Metalmania 6 dB louder, at the analyser's top - 0.09 at most 6 dB quieter). (Until review it was
 * read against the analyser's floor itself, and how many high bands cleared the floor moved with the
 * level: a calm record turned up 3 dB began to read as in between.)
 */
export const LEVEL_WINDOW = 0.7
/** Seconds `aggr` follows its target over (the words under the style list drift, never flicker). */
export const AGGR_FOLLOW_S = 2
/** The onset-strength envelope: samples a second, and how many are kept (8 s). */
export const ENVELOPE_RATE = 60
export const ENVELOPE_LENGTH = 480

export interface Feel {
  /** the spectrum at the last sample of the 60-a-second grid, for the flux */
  prev: Float32Array
  env: Float32Array
  envAt: number
  envT: number
  acfBuf: Float32Array
  acf: Float32Array
  /** seconds until the tempo is looked for again */
  acfIn: number
  onsets: number[]
  lastOnset: number
  above: boolean
  fMean: number
  fDev: number
  /** seconds of music heard (silence doesn't count) */
  clock: number
  /** onsets a second, the share of the sound above about 2 kHz, and noisiness - each followed over 5 s */
  density: number
  high: number
  flat: number
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
    prev: new Float32Array(BANDS), env: new Float32Array(ENVELOPE_LENGTH), envAt: 0, envT: 0,
    acfBuf: new Float32Array(ENVELOPE_LENGTH), acf: new Float32Array(128), acfIn: 0,
    onsets: [], lastOnset: -1, above: false, fMean: 0, fDev: 0.01,
    clock: 0, density: 3, high: 0.15, flat: 0.5,
    aggr: 0.45, bpm: 110, bpmRaw: 110, conf: 0, confRaw: 0, beats: 1.83, tempo: 1,
  }
}

/** Hermite smoothstep from a to b. */
export function smooth(a: number, b: number, x: number): number {
  const t = Math.max(0, Math.min(1, (x - a) / (b - a)))
  return t * t * (3 - 2 * t)
}

/**
 * How each reading counts toward `aggr`: [the value that counts nothing, the value that counts in
 * full, its weight] - a smoothstep between the two. Measured through the page's own pipeline (the
 * analyser emulated exactly, these bands, these readings) on 27 real tracks, the middle of each: calm
 * ones give 2.7-4.9 onsets a second, a share above 2 kHz of 0.00-0.04 and a flatness of 0.02-0.23;
 * music between calm and heavy - funk, surf, electronic - 2.8-6.3, 0.02-0.11 and 0.11-0.55; heavy
 * music 3.5-6.1, 0.09-0.17 and 0.43-0.82. So flatness tells calm from the rest, the share above 2 kHz
 * tells heavy from between, and onsets lean both. The ranges were searched on twenty of the tracks and
 * their louder and quieter copies, held to stay wide (no range a threshold in disguise), then rounded;
 * five tracks were kept out and read as tests/fixtures/feel/real-tracks.json says, beside every other
 * track's numbers.
 */
export const FEEL_SCORE: Readonly<Record<'density' | 'high' | 'flat', readonly [number, number, number]>> = {
  density: [2.9, 5.5, 0.31],
  high: [0.025, 0.17, 0.5],
  flat: [0.025, 0.23, 0.19],
}

/** `aggr`'s target from the readings as they stand (FEEL_SCORE), 0..1. */
export function feelScore(F: Pick<Feel, 'density' | 'high' | 'flat'>): number {
  let score = 0, weights = 0
  for (const [key, [from, to, weight]] of Object.entries(FEEL_SCORE) as [keyof typeof FEEL_SCORE, readonly [number, number, number]][]) {
    score += weight * smooth(from, to, F[key])
    weights += weight
  }
  return score / weights
}

/** One frame of the music, `dt` seconds after the last: the feel, moved on (in place) and returned. */
export function musicFeel(F: Feel, spectrum: ArrayLike<number>, dt: number): Feel {
  let sum = 0, top = 0
  for (let i = 0; i < BANDS; i++) {
    const s = spectrum[i] ?? 0
    sum += s
    top = Math.max(top, s)
  }
  //? silence, or a pause: hold everything (the spectrum kept, so what follows is measured against it)
  if (sum / BANDS < 0.03) {
    for (let i = 0; i < BANDS; i++) F.prev[i] = spectrum[i] ?? 0
    return F
  }
  F.clock += dt
  //? the flux - how much the spectrum rose - and the onsets, on a grid of 60 samples a second whatever
  //? the screen's frame rate: a 120 Hz screen reads the analyser twice as often, and counting onsets per
  //? frame counted twice as many (a calm track read in between); here a frame between two samples only
  //? waits, and one late by n samples spreads its flux over the n
  F.envT += dt
  if (F.envT >= 1 / ENVELOPE_RATE) {
    const n = Math.floor(F.envT * ENVELOPE_RATE)
    let flux = 0
    for (let i = 0; i < BANDS; i++) {
      const s = spectrum[i] ?? 0
      flux += Math.max(0, s - F.prev[i]!)
      F.prev[i] = s
    }
    flux /= n
    //? onsets: the flux rising through a threshold that follows the music's own level
    const a1 = 1 - Math.exp(-1 / ENVELOPE_RATE / 1.0)
    for (let k = 0; k < n; k++) {
      //? the onset-strength envelope, the last 8 s kept, for the tempo
      F.env[F.envAt] = flux
      F.envAt = (F.envAt + 1) % F.env.length
      const on = flux > F.fMean + 1.5 * F.fDev + 0.02
      if (on && !F.above && F.clock - F.lastOnset > 0.06) {
        F.onsets.push(F.clock)
        F.lastOnset = F.clock
      }
      F.above = on
      F.fMean += (flux - F.fMean) * a1
      F.fDev += (Math.abs(flux - F.fMean) - F.fDev) * a1
    }
    F.envT -= n / ENVELOPE_RATE
  }
  while (F.onsets.length && F.onsets[0]! < F.clock - 4) F.onsets.shift()
  const density = F.onsets.length / Math.min(4, Math.max(1, F.clock))
  //? brightness and noisiness, read in a window LEVEL_WINDOW deep below the loudest band: each band by how
  //? far it stands above the window's bottom, so the loudest band - however loud the record - sets where
  //? the window is; the bottom never goes below the analyser's floor (LIFT_FLOOR), where there is nothing
  const bottom = Math.max(top - LEVEL_WINDOW, LIFT_FLOOR)
  let all2 = 0, hi2 = 0, lg = 0, ar = 0
  for (let i = 0; i < BANDS; i++) {
    const v = Math.max(0, (spectrum[i] ?? 0) - bottom) / LEVEL_WINDOW
    all2 += v * v
    if (i >= 43) hi2 += v * v
    if (i >= 20) {
      const p = v * v + 1e-4
      lg += Math.log(p)
      ar += p
    }
  }
  const high = hi2 / Math.max(all2, 1e-6)
  const flat = Math.exp(lg / 44) / (ar / 44)
  const a5 = 1 - Math.exp(-dt / 5)
  F.density += (density - F.density) * a5
  F.high += (high - F.high) * a5
  F.flat += (flat - F.flat) * a5
  const score = feelScore(F)
  F.aggr += (score - F.aggr) * (1 - Math.exp(-dt / AGGR_FOLLOW_S))
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
