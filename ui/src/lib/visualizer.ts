/**
 * The desktop visualizer's pure parts (2.0.0-player.20): its effects and Ambient styles, the fixed
 * order "Rotate all" goes through them in, the colours, and the maths each style moves by - ported
 * from the canvas board DesktopVisualizer.dc.html, which is the reference for how all of it looks and
 * behaves. Nothing here touches audio or the DOM; ui/test/visualizer.sim.cjs drives it. The drawing is
 * player/vizDraw.ts (Canvas 2D) and player/vizGl.ts (WebGL, the shaders in lib/vizShaders.ts); the
 * sound to see is player/vizAudio.ts; the screen is player/Visualizer.tsx.
 *
 * NOTHING HERE IS RANDOM (James: "the style selector shouldn't be random, it should be consistent"):
 * the styles rotate in one fixed order, always starting on the first, and every "noise" is a hash of a
 * clock or a position.
 */

/* ===== the effects and the Ambient styles ===== */

export const EFFECTS = ['bars', 'scope', 'halo', 'ambient'] as const
export type Effect = (typeof EFFECTS)[number]
export const EFFECT_NAMES: Readonly<Record<Effect, string>> = { bars: 'Bars', scope: 'Scope', halo: 'Halo', ambient: 'Ambient' }

/** The Ambient styles, in the order "Rotate all" goes through them - each for HOLD_MS of playing
 *  time, always starting on the first. The first three are deadwax's own; the last five are the Media
 *  Player family, one shader and a set of numbers each (feedbackStyle). */
export const AMBIENT_STYLES = ['mandala', 'waves', 'liquid', 'burst', 'ribbons', 'smoke', 'rings', 'embers'] as const
export type AmbientStyle = (typeof AMBIENT_STYLES)[number]
export type AmbientChoice = 'rotate' | AmbientStyle
export const AMBIENT_CHOICES: readonly AmbientChoice[] = ['rotate', ...AMBIENT_STYLES]
export const STYLE_NAMES: Readonly<Record<AmbientChoice, string>> = {
  rotate: 'Rotate all', mandala: 'Mandala', waves: 'Waves', liquid: 'Liquid',
  burst: 'Burst', ribbons: 'Ribbons', smoke: 'Smoke', rings: 'Rings', embers: 'Embers',
}
/** The styles of the Media Player family: drawn by the one feedback shader. */
export const FEEDBACK_STYLES: readonly AmbientStyle[] = ['burst', 'ribbons', 'smoke', 'rings', 'embers']

/** The style list as the board draws it: Rotate all, the three originals, then the Media Player
 *  family under a heading of its own. */
export type StyleRow = { kind: 'option'; id: AmbientChoice } | { kind: 'heading'; label: string }
export const STYLE_ROWS: readonly StyleRow[] = [
  ...(['rotate', 'mandala', 'waves', 'liquid'] as const).map((id) => ({ kind: 'option' as const, id })),
  { kind: 'heading', label: 'Media Player style' },
  ...FEEDBACK_STYLES.map((id) => ({ kind: 'option' as const, id })),
]

/** How long "Rotate all" holds each style (counted only while the music plays), and how long one
 *  style takes to fade into the next, in ms. */
export const HOLD_MS = 30_000
export const FADE_MS = 2600

/** The effect `step` places on from `effect`, wrapping - V and Shift+V. */
export function cycleEffect(effect: Effect, step: number): Effect {
  const n = EFFECTS.length
  return EFFECTS[(((EFFECTS.indexOf(effect) + step) % n) + n) % n]!
}

/** The style after `style` in the fixed order, wrapping round to the first. */
export function nextStyle(style: AmbientStyle): AmbientStyle {
  return AMBIENT_STYLES[(AMBIENT_STYLES.indexOf(style) + 1) % AMBIENT_STYLES.length]!
}

/** Which Ambient style shows, and the crossfade from the one before: the GL renderer's two slots. */
export interface Rotation {
  cur: AmbientStyle | null
  from: AmbientStyle | null
  /** the slot the current style draws into; the outgoing one has the other */
  curSlot: 0 | 1
  /** when the crossfade began, on the rotation's own clock */
  fadeT0: number
  /** what is left of the current style's hold, ms - counted only while the music plays */
  holdLeft: number
  /** ms since the rotation began, playing or not */
  clock: number
}

export function newRotation(): Rotation {
  return { cur: null, from: null, curSlot: 0, fadeT0: 0, holdLeft: HOLD_MS, clock: 0 }
}

/** Start a style: it takes the other slot, fresh, and fades in over the one showing; held HOLD_MS. */
export function startStyle(A: Rotation, style: AmbientStyle): void {
  if (style === A.cur) return
  if (A.cur) {
    A.from = A.cur
    A.curSlot = A.curSlot === 0 ? 1 : 0
    A.fadeT0 = A.clock
  }
  A.cur = style
  A.holdLeft = HOLD_MS
}

/**
 * The dropdown chose: a style pins it (the next tick crossfades to it); "Rotate all" carries on from
 * whatever is showing, which gets a fresh HOLD_MS.
 */
export function chooseStyle(A: Rotation, choice: AmbientChoice): void {
  if (choice === 'rotate') A.holdLeft = HOLD_MS
}

/**
 * Which style should be showing, `dtMs` later: the pinned one, or under "Rotate all" the next in the
 * fixed order once this one's hold is up - and, before anything has shown, the first. Returns the
 * style it started (for the renderer to clear that slot), else null.
 */
export function rotationTick(A: Rotation, dtMs: number, playing: boolean, choice: AmbientChoice): AmbientStyle | null {
  A.clock += dtMs
  if (playing) A.holdLeft -= dtMs
  //? a crossfade that has run its course lets the style before go
  if (A.from && A.clock - A.fadeT0 >= FADE_MS) A.from = null
  const pin = choice !== 'rotate' ? choice : null
  const begin = (style: AmbientStyle) => {
    startStyle(A, style)
    return style
  }
  if (!A.cur) return begin(pin ?? AMBIENT_STYLES[0])
  if (pin) return A.cur !== pin ? begin(pin) : null
  if (!A.from && A.holdLeft <= 0) return begin(nextStyle(A.cur))
  return null
}

/** How far the crossfade is (0..1, eased); 1 when there isn't one, or it is done. */
export function fadeMix(A: Rotation): number {
  if (!A.from) return 1
  const x = Math.min(1, (A.clock - A.fadeT0) / FADE_MS)
  return x * x * (3 - 2 * x)
}

/* ===== colours ===== */

export type Rgb = readonly [number, number, number]
export type Colours = 'cover' | 'purple'
export const COLOURS: readonly Colours[] = ['cover', 'purple']

/** deadwax's own purple, darkest to lightest. */
export const PURPLE: readonly Rgb[] = ['#6d28d9', '#8b3cf0', '#a855f7', '#b77af9', '#c084fc', '#dcbcfd'].map(hexRgb)

export function hexRgb(hex: string): Rgb {
  return [parseInt(hex.slice(1, 3), 16), parseInt(hex.slice(3, 5), 16), parseInt(hex.slice(5, 7), 16)]
}

/** 256 colours along the palette (round again to the first when `cyclic`) - what the 2D effects
 *  colour by. */
export function makeLut(cols: readonly Rgb[], cyclic: boolean): Rgb[] {
  const all = cyclic ? [...cols, cols[0]!] : [...cols]
  const lut: Rgb[] = []
  for (let i = 0; i < 256; i++) {
    const u = (i / 255) * (all.length - 1)
    const k = Math.min(all.length - 2, Math.floor(u))
    const f = u - k
    const a = all[k]!, b = all[k + 1]!
    lut.push([Math.round(a[0] + (b[0] - a[0]) * f), Math.round(a[1] + (b[1] - a[1]) * f), Math.round(a[2] + (b[2] - a[2]) * f)])
  }
  return lut
}

/** A LUT's colour at `u` (its fractional part; 1 is the end) as a CSS colour. */
export function lutColour(lut: readonly Rgb[], u: number, alpha: number): string {
  const w = u - Math.floor(u)
  const c = lut[Math.max(0, Math.min(255, Math.round((u >= 1 ? 1 : w) * 255)))]!
  return `rgba(${c[0]},${c[1]},${c[2]},${alpha.toFixed(3)})`
}

/** A cyclic LUT's colour at `u`, 0-1 floats - the Media Player styles' hues. */
export function lutFloats(ring: readonly Rgb[], u: number): [number, number, number] {
  const c = ring[Math.min(255, Math.floor((u - Math.floor(u)) * 256))]!
  return [c[0] / 255, c[1] / 255, c[2] / 255]
}

/** The six colours as eighteen floats, for the shaders' uPal. */
export function palFloats(cols: readonly Rgb[]): Float32Array {
  const out = new Float32Array(18)
  cols.slice(0, 6).forEach((c, i) => {
    out[i * 3] = c[0] / 255
    out[i * 3 + 1] = c[1] / 255
    out[i * 3 + 2] = c[2] / 255
  })
  return out
}

/** The Mandala's parts, each a colour: a core, a body and a second body, rings and a flare. */
export interface Roles {
  core: [number, number, number]
  body: [number, number, number]
  body2: [number, number, number]
  ring: [number, number, number]
  flare: [number, number, number]
}

/** In purple, as the board has them: a near-white core, a violet body, lavender rings, a deep flare. */
export const PURPLE_ROLES: Roles = {
  core: [0.97, 0.9, 1.0], body: [0.7, 0.42, 1.0], body2: [0.82, 0.62, 1.0], ring: [0.95, 0.89, 1.0], flare: [0.42, 0.17, 0.85],
}

const unit = (c: Rgb): [number, number, number] => [c[0] / 255, c[1] / 255, c[2] / 255]
const towards = (a: readonly number[], b: readonly number[], t: number): [number, number, number] =>
  [a[0]! + (b[0]! - a[0]!) * t, a[1]! + (b[1]! - a[1]!) * t, a[2]! + (b[2]! - a[2]!) * t]
/** A colour scaled so its brightest channel is `top`. */
function lift(c: readonly number[], top: number): [number, number, number] {
  const m = Math.max(c[0]!, c[1]!, c[2]!, 1e-3)
  return [c[0]! / m * top, c[1]! / m * top, c[2]! / m * top]
}
const luma = (c: Rgb) => 0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2]

/**
 * The Mandala's parts from a cover's palette, as the board drew them from the prism's: a warm core
 * (the brightest colour, lifted toward white), the body and second body from the palette's later
 * colours at full brightness, rings near white in the second body's colour, and a deeper flare.
 */
export function rolesFrom(cols: readonly Rgb[]): Roles {
  const sorted = [...cols]
  const brightest = sorted.reduce((best, c) => (luma(c) > luma(best) ? c : best), sorted[0]!)
  const body = unit(cols[3] ?? cols[cols.length - 1]!)
  const body2 = unit(cols[4] ?? cols[cols.length - 1]!)
  return {
    core: towards(lift(unit(brightest), 1), [1, 1, 1], 0.3),
    body: lift(body, 0.95),
    body2: lift(body2, 1),
    ring: towards(lift(body2, 1), [1, 1, 1], 0.75),
    flare: lift(unit(cols[5] ?? cols[cols.length - 1]!), 0.85),
  }
}

function hsv(r: number, g: number, b: number): [number, number, number] {
  const max = Math.max(r, g, b), min = Math.min(r, g, b), d = max - min
  let h = 0
  if (d > 0) {
    if (max === r) h = ((g - b) / d) % 6
    else if (max === g) h = (b - r) / d + 2
    else h = (r - g) / d + 4
    h /= 6
    if (h < 0) h += 1
  }
  return [h, max > 0 ? d / max : 0, max / 255]
}

function fromHsv(h: number, s: number, v: number): Rgb {
  const i = Math.floor(h * 6), f = h * 6 - i
  const p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
  const [r, g, b] = [[v, t, p], [q, v, p], [p, v, t], [p, q, v], [t, p, v], [v, p, q]][((i % 6) + 6) % 6]!
  return [Math.round(r! * 255), Math.round(g! * 255), Math.round(b! * 255)]
}

/** A colour made vivid enough to glow on black, its hue kept: at least this saturated and bright. */
function vivid(c: Rgb): Rgb {
  const [h, s, v] = hsv(c[0], c[1], c[2])
  return fromHsv(h, Math.max(s, 0.45), Math.max(v, 0.78))
}

/** How many hue bins a cover's colours are counted in. */
const HUE_BINS = 36

/**
 * Six colours from a cover's pixels (RGBA, as getImageData gives them) - "From the cover". Its most
 * colourful hues, strongest first, kept apart from one another, then put in hue order so the effects'
 * gradients run through them smoothly, each made vivid enough to glow on black. A cover with too few
 * colourful pixels (black and white, a grey sleeve) is a ramp of its own colour, dark to light - what
 * it is, not purple. Null for a picture with no opaque pixels at all. Deterministic: the same picture
 * always gives the same six.
 */
export function coverPalette(pixels: ArrayLike<number>): Rgb[] | null {
  const weight = new Float64Array(HUE_BINS)
  //? each bin's colour sums, three to a bin
  const sums = new Float64Array(HUE_BINS * 3)
  let opaque = 0, colourful = 0
  let sumR = 0, sumG = 0, sumB = 0
  for (let i = 0; i + 3 < pixels.length; i += 4) {
    const r = pixels[i]!, g = pixels[i + 1]!, b = pixels[i + 2]!, a = pixels[i + 3]!
    if (a < 128) continue
    opaque += 1
    sumR += r
    sumG += g
    sumB += b
    const [h, s, v] = hsv(r, g, b)
    if (s < 0.25 || v < 0.2) continue
    colourful += 1
    const bin = Math.min(HUE_BINS - 1, Math.floor(h * HUE_BINS))
    const w = s * v
    weight[bin] = weight[bin]! + w
    sums[bin * 3] = sums[bin * 3]! + r * w
    sums[bin * 3 + 1] = sums[bin * 3 + 1]! + g * w
    sums[bin * 3 + 2] = sums[bin * 3 + 2]! + b * w
  }
  if (!opaque) return null
  const mean: Rgb = [sumR / opaque, sumG / opaque, sumB / opaque]
  if (colourful < opaque * 0.03) {
    //? a black-and-white or grey cover: its own colour, dark to light
    return Array.from({ length: 6 }, (_, k) => {
      const t = k / 5
      const base = lift(mean, Math.max(0.35, Math.max(...mean) / 255))
      const c = towards(towards(base, [0, 0, 0], 0.45 * (1 - t)), [1, 1, 1], 0.7 * t)
      return [Math.round(c[0] * 255), Math.round(c[1] * 255), Math.round(c[2] * 255)] as Rgb
    })
  }
  //? the strongest hues, one at a time; each takes its neighbours' colour with its own (a hue split
  //? across two bins counts once), and they aren't picked again - so hues 20 degrees apart, a prism's
  //? orange and yellow, are both kept
  const picks: { hue: number; colour: Rgb }[] = []
  const taken = new Array<boolean>(HUE_BINS).fill(false)
  let top = 0
  while (picks.length < 6) {
    let best = -1
    for (let k = 0; k < HUE_BINS; k++) if (!taken[k] && (best < 0 || weight[k]! > weight[best]!)) best = k
    if (best < 0 || weight[best]! <= 0) break
    if (!top) top = weight[best]!
    if (weight[best]! < top * 0.02) break
    //? its colour: the weighted mean of the bin and its neighbours
    let w = 0, r = 0, g = 0, b = 0
    for (const k of [best - 1, best, best + 1]) {
      const at = (k + HUE_BINS) % HUE_BINS
      w += weight[at]!
      r += sums[at * 3]!
      g += sums[at * 3 + 1]!
      b += sums[at * 3 + 2]!
    }
    if (w > 0) picks.push({ hue: best / HUE_BINS, colour: vivid([r / w, g / w, b / w]) })
    for (let d = -1; d <= 1; d++) taken[(best + d + HUE_BINS) % HUE_BINS] = true
  }
  if (!picks.length) return null
  //? in hue order, starting after the widest gap between them, so the gradient never doubles back
  picks.sort((a, b) => a.hue - b.hue)
  let start = 0, widest = -1
  for (let k = 0; k < picks.length; k++) {
    const next = picks[(k + 1) % picks.length]!.hue + (k + 1 === picks.length ? 1 : 0)
    const gap = next - picks[k]!.hue
    if (gap > widest) {
      widest = gap
      start = (k + 1) % picks.length
    }
  }
  const ordered = [...picks.slice(start), ...picks.slice(0, start)].map((pick) => pick.colour)
  if (ordered.length >= 6) return ordered.slice(0, 6)
  if (ordered.length === 1) {
    //? one colour: it, from deep to pale
    const only = unit(ordered[0]!)
    return Array.from({ length: 6 }, (_, k) => {
      const t = k / 5
      const c = towards(towards(only, [0, 0, 0], 0.45 * (1 - t)), [1, 1, 1], 0.55 * t)
      return [Math.round(c[0] * 255), Math.round(c[1] * 255), Math.round(c[2] * 255)] as Rgb
    })
  }
  //? two to five: six along the gradient through them
  const lut = makeLut(ordered, false)
  return Array.from({ length: 6 }, (_, k) => lut[Math.round((k / 5) * 255)]!)
}

/* ===== the Media Player family: one shader, a set of numbers per style ===== */

/** What a feedback style is told each frame: its own clock, and the music. */
export interface FeedbackInput {
  t: number
  bass: number
  kick: number
  energy: number
}

/**
 * One frame's numbers for the feedback shader (lib/vizShaders.ts says what each does):
 *  warp   zoom out per frame, rotation, extra rotation near the centre (swirl), turbulence
 *  drift  x and y the picture moves per frame, then the x and y of the zoom's centre
 *  fade   what is kept each frame, what is subtracted, blur in px, block size (0 = smooth)
 *  look   1 = one hue from dark through the colour to white (0 = each line keeps the colour it was
 *         drawn in), posterise levels (0 = none), floor brightness, line width in px
 *  ring   waveform ring: weight, radius, how far the waveform bends it, extra weight on a kick
 *  lineW / lineAng   up to three waveform lines through the centre: weights and angles
 *  line   how far the waveform bends them, half length, 1 = mirrored left-right, and striation
 *  bars   spectrum bars along the bottom: weight, height, how many (each side), build-up
 *  core   glow at the zoom's centre: weight, size, extra on a kick, and the strokes' halo
 *  hue    seconds spent on each of the palette's six hues, and where in the cycle it starts
 */
export interface FeedbackParams {
  warp: [number, number, number, number]
  drift: [number, number, number, number]
  fade: [number, number, number, number]
  look: [number, number, number, number]
  ring: [number, number, number, number]
  lineW: [number, number, number]
  lineAng: [number, number, number]
  line: [number, number, number, number]
  bars: [number, number, number, number]
  core: [number, number, number, number]
  hue: [number, number]
}

const { sin, cos } = Math

/** The Media Player family's numbers, by style - adding a style is adding an entry here, its name in
 *  STYLE_NAMES and its place in AMBIENT_STYLES. */
export const FEEDBACK: Readonly<Record<string, (s: FeedbackInput) => FeedbackParams>> = {
  //? after James's picture: a ring and a scribble of the waveform, streaked outward
  burst: (s) => ({
    warp: [0.028 + 0.03 * s.kick, 0.006 * sin(s.t * 0.13) + 0.004 * sin(s.t * 0.31), 0.014 * sin(s.t * 0.09), 0],
    drift: [0, 0, 0.07 * sin(s.t * 0.11), 0.05 * cos(s.t * 0.17)],
    fade: [0.985, 0.002, 0.6, 0.03],
    look: [1, 7, 0.22, 2.2],
    ring: [1, 0.2 + 0.06 * s.bass, 0.07 + 0.05 * s.bass, 0],
    lineW: [0.95, 0, 0],
    lineAng: [Math.PI / 2 + 0.5 * sin(s.t * 0.23), 0, 0],
    line: [0.1, 0.36, 0, 0.9],
    bars: [0, 0, 1, 0],
    core: [0.9, 0.035, 0.4, 0.45],
    hue: [10, 0],
  }),
  //? three waveform lines turning about the centre at their own speeds, mirrored, leaving long
  //? trails in the colours they were drawn in
  ribbons: (s) => ({
    warp: [0.006, 0.014 + 0.005 * sin(s.t * 0.1), 0, 0],
    drift: [0, 0, 0, 0],
    fade: [0.986, 0.002, 0.5, 0],
    look: [0, 0, 0, 1.6],
    ring: [0, 0.2, 0, 0],
    lineW: [1, 0.9, 0.8],
    lineAng: [s.t * 0.45, -s.t * 0.31 + 1.0, s.t * 0.19 + 2.4],
    line: [0.1 + 0.08 * s.bass, 0.8, 1, 0],
    bars: [0, 0, 1, 0],
    core: [0, 0.05, 0, 0.25],
    hue: [6, 0.5],
  }),
  //? a dim line and ring smeared by a swirling, drifting, blurred warp into wisps
  smoke: (s) => ({
    warp: [0.002, 0.002, 0.016 + 0.012 * sin(s.t * 0.05), 0.005],
    drift: [0.0006 * sin(s.t * 0.07), 0.0014, 0.1 * sin(s.t * 0.04), 0.06 * cos(s.t * 0.05)],
    fade: [0.992, 0.001, 1.6, 0],
    look: [0, 0, 0, 2.6],
    ring: [0.4, 0.16 + 0.05 * s.bass, 0.06, 0],
    lineW: [0.55, 0, 0],
    lineAng: [s.t * 0.06, 0, 0],
    line: [0.14, 0.55, 0, 0],
    bars: [0, 0, 1, 0],
    core: [0, 0.05, 0, 0.9],
    hue: [12, 2.5],
  }),
  //? a small circle struck on each kick, carried outward by the zoom into ripples
  rings: (s) => ({
    warp: [0.018 + 0.012 * s.bass, 0.003 * sin(s.t * 0.1), 0, 0],
    drift: [0, 0, 0.03 * sin(s.t * 0.13), 0.02 * cos(s.t * 0.19)],
    fade: [0.989, 0.0015, 0, 0],
    look: [0, 0, 0, 2.6],
    ring: [0.45, 0.07 + 0.02 * s.bass, 0.012 + 0.018 * s.bass, 1.2],
    lineW: [0, 0, 0],
    lineAng: [0, 0, 0],
    line: [0, 0.3, 0, 0],
    bars: [0, 0, 1, 0],
    core: [0, 0.025, 0.5, 0.3],
    hue: [5, 1.2],
  }),
  //? the spectrum as bars along the bottom, drifting up and flickering like flames
  embers: (s) => ({
    warp: [0, 0, 0, 0.0035 + 0.003 * s.energy],
    drift: [0.0008 * sin(s.t * 0.9), 0.007 + 0.006 * s.energy, 0, 0],
    fade: [0.955, 0.004, 1.2, 0.014],
    look: [1, 10, 0, 1],
    ring: [0, 0.2, 0, 0],
    lineW: [0, 0, 0],
    lineAng: [0, 0, 0],
    line: [0, 0.3, 0, 0],
    bars: [0.9, 0.34, 40, 0],
    core: [0, 0.05, 0, 0],
    hue: [9, 0.2],
  }),
}

/** A feedback style's numbers with the tempo setting how fast the picture is carried: zoom, turn,
 *  swirl and drift per frame. */
export function feedbackFrame(style: AmbientStyle, s: FeedbackInput, tempo: number): FeedbackParams | null {
  const make = FEEDBACK[style]
  if (!make) return null
  const P = make(s)
  P.warp = [P.warp[0] * tempo, P.warp[1] * tempo, P.warp[2] * tempo, P.warp[3]]
  P.drift = [P.drift[0] * tempo, P.drift[1] * tempo, P.drift[2], P.drift[3]]
  return P
}

/** One of the palette's hues at a time (0..1 round the cyclic LUT): it rests on each for most of its
 *  turn and slides to the next over the last third. */
export function hueStep(vt: number, secondsPerHue: number, offset: number): number {
  const x = vt / secondsPerHue + offset
  const k = Math.floor(x)
  return (k + smoothstep(0.65, 1, x - k)) / 6
}

export function smoothstep(a: number, b: number, x: number): number {
  const t = Math.max(0, Math.min(1, (x - a) / (b - a)))
  return t * t * (3 - 2 * t)
}

/* ===== the Mandala ===== */

/** The Mandala's clocks: the mirrors' (beats), the source's, its spin and twist, and the mids. */
export interface MandalaState {
  clock: number
  shape: number
  spin: number
  twist: number
  mid: number
}

/** The morph starts from the song's position, so where you come in decides the first figure. */
export function newMandala(songSeconds: number): MandalaState {
  return { clock: songSeconds * 1.5, shape: songSeconds * 1.5, spin: 0, twist: 0, mid: 0.38 }
}

/**
 * The Mandala's clocks moved on. Nothing the music does here is a throb: the tempo sets the pace and
 * the mids only lean it. The mirrors' clock counts beats (musicFeel's, halved or doubled into a
 * watchable range), so its 16-unit steps are 16-beat phrases; the source's clock runs a little faster
 * or slower with the mids, so the shapes drift against the mirrors; the spin follows the tempo, and
 * the twist winds faster the more aggressive the music is.
 */
export function mandalaFlow(M: MandalaState, spec: ArrayLike<number>, beats: number, aggr: number, level: number, dt: number): void {
  let mid = 0
  for (let i = 16; i < 40; i++) mid += spec[i] ?? 0
  M.mid += (mid / 24 - M.mid) * (1 - Math.exp(-dt / 0.8))
  const go = 0.2 + 0.8 * level
  const rate = beats * go
  M.clock += dt * rate
  M.shape += dt * rate * (0.6 + 1.1 * M.mid)
  M.spin += dt * go * (0.035 * beats + 0.14 * (M.mid - 0.38))
  M.twist += dt * rate * (0.02 + 0.035 * aggr)
}

export interface MandalaFigure {
  fold: [number, number, number, number]
  inv: [number, number, number, number]
  src: [number, number, number, number]
  form: [number, number, number, number]
  formW: [number, number, number]
  lat: [number, number, number, number]
  rings: [number, number, number, number]
  edge: [number, number, number, number]
}

/**
 * The Mandala's figure, from its clocks. Every number moves on its own slow curve, out of step with
 * the others, so the combinations keep coming out different: the mirror count and the polygon's
 * sides step through lists, holding each value and gliding to the next (the glide is the mirrors
 * swinging, or a square's corners bulging into a pentagon); the kind of figure (polygon, flower of
 * circles, lattice) and the kind of lattice cycle the same way; starriness and roundness rise only now
 * and then; the inversion spends most of its time off and turns the plane inside out for a stretch;
 * the twist winds and unwinds; the zoom flies in and out. The music's feel (A: 0 smooth .. 1
 * aggressive) leans every curve without replacing it: aggressive music brings stars and spikes, sharp
 * corners, triangles and few sides, triangle lattices, fast tight twists, more time turned inside out
 * and harder lines; smooth music brings roundness, circles and flowers of circles, many sides rounding
 * toward circles, hexagons, soft glow, wide gentle shapes and long slow twists, and hardly ever a star.
 */
export function mandalaMorph(M: MandalaState, aggr: number): MandalaFigure {
  const c = M.clock, m = M.shape
  const A = aggr, S = 1 - A
  const mix = (a: number, b: number, t: number) => a + (b - a) * t
  const s = (x: number, w: number, o: number) => 0.5 + 0.5 * sin(x * w + o)
  const glide = (list: readonly number[], period: number, x: number, hold: number) => {
    const ph = x / period, k = Math.floor(ph), n = list.length
    const a = list[((k % n) + n) % n]!, b = list[(((k + 1) % n) + n) % n]!
    return a + (b - a) * smoothstep(hold, 1, ph - k)
  }
  const step = (period: number, x: number, hold: number) => {
    const ph = x / period, k = Math.floor(ph)
    return k + smoothstep(hold, 1, ph - k)
  }
  //? the kind of figure: three weights (polygon, flower of circles, lattice) turning round on one slow
  //? curve, sharpened so one leads most of the time, and leaned by the feel; the shader blends the
  //? three distance fields by them, so a change of kind is a morph
  const lean = [mix(1.0, 1.1, A), mix(1.25, 0.55, A), mix(0.8, 1.2, A)]
  const formW = [0, 2.094, 4.189].map((o, i) => Math.pow(s(c, 0.066, o) * lean[i]!, 6) + 0.002) as [number, number, number]
  //? the kind of lattice cycles triangle, square, hexagon; aggressive music pulls it toward triangles
  //? and smooth toward hexagons (a pull that wraps round, so it never jumps)
  const k2 = (Math.PI * 2) / 3
  let lk = step(31, m, 0.5) % 3
  lk -= (A * 0.6 / k2) * sin(k2 * lk)
  lk -= (S * 0.6 / k2) * sin(k2 * (lk - 2))
  const starNow = Math.pow(Math.max(0, sin(m * 0.041 + 1.0)), 6)
  const roundNow = Math.pow(Math.max(0, sin(m * 0.033 + 2.5)), 4)
  return {
    fold: [
      glide([6, 8, 5, 12, 7, 10, 4, 9], 16, c, 0.62),
      M.spin,
      mix(1.0, 2.4, A) * sin(M.twist) * s(c, 0.013, 0.5),
      Math.exp(0.35 * sin(c * 0.045 + 0.3)),
    ],
    inv: [
      smoothstep(mix(0.72, 0.6, A), mix(0.95, 0.86, A), s(c, 0.031, -1.2)),
      0.3,
      0.04 + 0.18 * s(m, 0.043, 0),
      0.12 * sin(m * 0.031 + 1.7),
    ],
    src: [
      m * 0.05 + 1.5 * sin(m * 0.02),
      (0.32 + 0.22 * s(m, 0.027, 1.1)) * mix(1.2, 0.9, A),
      mix(glide([6, 8, 7, 5, 8, 6, 7], 13, m, 0.55), glide([3, 4, 3, 5, 3, 4, 3], 11, m, 0.55), A),
      Math.min(1, starNow * S * 0.28 + A * (0.4 + 0.6 * s(m, 0.057, 0.3))),
    ],
    form: [
      mix(0.14, 0.05, A),
      mix(0.35 + 0.65 * s(m, 0.033, 2.5), roundNow * 0.1, A),
      0.08 + 0.06 * s(m, 0.053, 2),
      (0.05 + 0.25 * s(c, 0.047, 4.4)) * mix(1.3, 0.8, A),
    ],
    formW,
    lat: [
      lk,
      (0.32 + 0.16 * s(m, 0.039, 0.9)) * mix(1.15, 0.9, A),
      0.36 + 0.1 * s(c, 0.025, 1),
      0.05 + 0.03 * s(m, 0.061, 2.2),
    ],
    rings: [
      0.1 + 0.08 * s(c, 0.034, 0),
      smoothstep(0.5, 0.9, s(c, 0.043, 1.9)),
      0.18 + 0.05 * s(m, 0.029, 3),
      0.03 * s(m, 0.051, 0.4),
    ],
    //? the look of the lines: glow tail, width, colour fringe, and the trail's fringe
    edge: [mix(0.45, 0.06, A), mix(1.3, 1.0, A), mix(0.005, 0.015, A), mix(0.0015, 0.0045, A)],
  }
}

/* ===== Waves ===== */

export interface WavesCamera {
  heading: number
  roll: number
  camH: number
  horizon: number
  yaw: number
  vanish: number
}

/**
 * Where the Waves camera is, from the clock alone: a heading that sweeps left and right on three slow
 * sines, a roll into each turn (from how fast the heading is changing), and a height that mostly
 * stays low over the ridges and now and then climbs and comes back. It flies mostly where it points,
 * so the landscape also slides sideways under it - `drift` keeps where it has slid to.
 */
export function wavesCamera(t: number, drift: { x: number }, level: number, tempo: number, bass: number, kick: number, dt: number): WavesCamera {
  const psi = 0.34 * sin(t * 0.17) + 0.2 * sin(t * 0.093 + 1.3) + 0.07 * sin(t * 0.37 + 0.4)
  const turn = 0.34 * 0.17 * cos(t * 0.17) + 0.2 * 0.093 * cos(t * 0.093 + 1.3) + 0.07 * 0.37 * cos(t * 0.37 + 0.4)
  const up = 0.5 + 0.5 * sin(t * 0.071 + 4.2)
  const climb = up * up
  const speed = 9 * 0.36 * (0.25 + 0.75 * level) * tempo
  drift.x = (drift.x + dt * speed * 0.75 * Math.tan(psi)) % 6.4
  return {
    heading: psi,
    roll: -2.4 * turn + 0.02 * sin(t * 0.23),
    camH: 0.95 + 0.7 * climb + 0.05 * bass + 0.02 * Math.min(1, kick) + 0.02 * sin(t * 0.9),
    horizon: 0.17 + 0.1 * climb,
    yaw: drift.x,
    vanish: Math.tan(Math.atan(0.75 * Math.tan(psi)) - psi),
  }
}

/* ===== Liquid ===== */

export interface LiquidState {
  x: number
  y: number
  sx: number
  sy: number
  phase: number
  col: number
  dx: number
  dy: number
  bass: number
  mid: number
  high: number
}

export function newLiquid(): LiquidState {
  return { x: 0, y: 0, sx: 0, sy: 0, phase: 0, col: 0, dx: 1, dy: 0, bass: 0, mid: 0.3, high: 0 }
}

/**
 * Liquid's currents. Everything the music does here is motion, never brightness, taken from slow
 * followers of the bass, mids and highs so the flow surges instead of twitching: the bass sets the
 * speed, the mids bend the direction on top of its own slow wander, the highs size the ripples, and
 * the colours' place in the palette creeps along with the flow.
 */
export function liquidFlow(L: LiquidState, t: number, spec: ArrayLike<number>, bass: number, tempo: number, dt: number): void {
  let mid = 0, high = 0
  for (let i = 16; i < 40; i++) mid += spec[i] ?? 0
  for (let i = 44; i < 64; i++) high += spec[i] ?? 0
  L.bass += (bass - L.bass) * (1 - Math.exp(-dt / 0.35))
  L.mid += (mid / 24 - L.mid) * (1 - Math.exp(-dt / 0.5))
  L.high += (high / 20 - L.high) * (1 - Math.exp(-dt / 0.15))
  const speed = (0.3 + 2.2 * L.bass) * tempo
  const ang = 0.9 * sin(t * 0.043) + 0.6 * sin(t * 0.027 + 2) + t * 0.02 + 2.4 * (L.mid - 0.3)
  L.dx = cos(ang)
  L.dy = sin(ang)
  //? how far the noise travels this frame; the shader carries the last frame the same way (the noise
  //? is laid at 1.7x the screen's scale, hence the division)
  const step = dt * speed * 0.14
  L.x += step * L.dx
  L.y += step * L.dy
  L.sx = (step * L.dx) / 1.7
  L.sy = (step * L.dy) / 1.7
  L.phase += dt * speed * 0.1
  L.col += dt * (0.012 + 0.03 * L.bass)
}

/* ===== the signal: what the analyser gives, shaped as the board's effects read it ===== */

/** How many points the waveform has, and how much of the song it spans (s) - the board's. */
export const WAVE_POINTS = 384
export const WAVE_SPAN_S = 0.028
/** The analyser's FFT: 2048 samples is about 43 ms - onsets stay sharp, and the low bands, narrower
 *  than a bin, are read between bins. */
export const FFT_SIZE = 2048
/** The spectrum's range in dB, as getByteFrequencyData scales it to 0-255 (the analyser's own
 *  smoothing is off: the effects smooth, and the feel needs the raw flux). */
export const MIN_DB = -90
export const MAX_DB = -22
export const LOW_HZ = 30
export const HIGH_HZ = 16_000

/** Each band's place among the FFT's bins: the bins it covers (lo..hi, fractional). */
export interface BandSpan {
  lo: number
  hi: number
}

/** The 64 bands, log-spaced from LOW_HZ to HIGH_HZ, as bins of an FFT of `fftSize` at `sampleRate`. */
export function bandLayout(fftSize: number, sampleRate: number): BandSpan[] {
  const binHz = sampleRate / fftSize
  const edge = (b: number) => LOW_HZ * Math.pow(HIGH_HZ / LOW_HZ, b / 64)
  return Array.from({ length: 64 }, (_, b) => ({ lo: edge(b) / binHz, hi: edge(b + 1) / binHz }))
}

/**
 * The 64 bands, 0-1, from getByteFrequencyData's bins: the loudest bin a band covers, or - a low band
 * narrower than a bin - read between the two bins round its middle.
 */
export function bandsFromBins(bins: ArrayLike<number>, layout: readonly BandSpan[], out: Float32Array): void {
  const last = bins.length - 1
  for (let b = 0; b < layout.length; b++) {
    const { lo, hi } = layout[b]!
    const first = Math.ceil(lo), end = Math.min(last, Math.floor(hi))
    let v = 0
    if (end >= first) {
      for (let k = first; k <= end; k++) v = Math.max(v, bins[k] ?? 0)
    } else {
      const c = Math.min(last, (lo + hi) / 2)
      const k = Math.floor(c), f = c - k
      v = (bins[k] ?? 0) * (1 - f) + (bins[Math.min(last, k + 1)] ?? 0) * f
    }
    out[b] = v / 255
  }
}

/**
 * The waveform the board draws, from the analyser's time-domain samples (-1..1): the last WAVE_SPAN_S
 * of them as WAVE_POINTS points, through a slow automatic gain (`agc.peak` follows the loudest
 * sample, so a quiet recording still draws a line worth seeing), softly limited (tanh) and tapered to
 * nothing at both ends, scaled by `level` (0 as a pause dies away).
 */
export function waveFromSamples(samples: ArrayLike<number>, sampleRate: number, agc: { peak: number }, level: number, dt: number, out: Float32Array): void {
  const span = Math.max(2, Math.min(samples.length, Math.round(WAVE_SPAN_S * sampleRate)))
  const start = samples.length - span
  let peak = 0
  for (let k = start; k < samples.length; k++) peak = Math.max(peak, Math.abs(samples[k] ?? 0))
  agc.peak = Math.max(peak, agc.peak * Math.exp(-dt / 2))
  const gain = Math.max(0.8, Math.min(4, 0.7 / Math.max(agc.peak, 0.05)))
  const N = out.length
  for (let j = 0; j < N; j++) {
    const x = start + (j / (N - 1)) * (span - 1)
    const k = Math.floor(x), f = x - k
    const v = (samples[k] ?? 0) * (1 - f) + (samples[Math.min(samples.length - 1, k + 1)] ?? 0) * f
    out[j] = Math.tanh(v * 0.9 * gain * level) * taper(j, N)
  }
}

/** The board's taper at the waveform's ends: a raised cosine over 8% of it at each end. */
export function taper(j: number, N: number): number {
  const k = Math.min(j, N - 1 - j) / (N * 0.08)
  return k >= 1 ? 1 : 0.5 - 0.5 * Math.cos(Math.PI * k)
}

/**
 * A calm idle signal - what the effects run from when a song can't be seen (not a FLAC, its sound
 * couldn't be had): a soft, slowly changing slope across the bands and a gentle low wave. Nothing in
 * it is a beat, and the feel isn't read from it (it holds), so a song that can't be seen never reads
 * as "smooth" either.
 */
export function idleSignal(t: number, spectrum: Float32Array, wave: Float32Array): void {
  for (let i = 0; i < spectrum.length; i++) {
    const v = 0.2 + 0.08 * sin(t * 0.35 + i * 0.21) + 0.06 * sin(t * 0.13 - i * 0.09)
    spectrum[i] = Math.max(0, v * (1 - i / 90))
  }
  const N = wave.length
  for (let j = 0; j < N; j++) {
    const x = j / (N - 1)
    const v = 0.22 * sin(2 * Math.PI * x * 2 + t * 0.6) + 0.08 * sin(2 * Math.PI * x * 5 - t * 0.4)
    wave[j] = v * taper(j, N)
  }
}

/** What the effects read each frame: the smoothed spectrum, its peaks, the bass and the energy, and a
 *  kick - from the raw spectrum the frame brought. */
export interface Shaped {
  spec: Float32Array
  peaks: Float32Array
  bass: number
  energy: number
  kick: number
  /** the low bands' slow level, which a kick stands out from */
  lowSlow: number
}

export function newShaped(): Shaped {
  return { spec: new Float32Array(64), peaks: new Float32Array(64), bass: 0, energy: 0, kick: 0, lowSlow: 0 }
}

/**
 * One frame's raw spectrum taken in, as the board's effects read it: each band rises fast (30 ms) and
 * falls slower (160 ms), its peak cap falls 0.3 a second, the bass is the low twelve bands and the
 * energy all 64. The kick - the board's synthetic songs knew theirs; a real song's is read here - is
 * the low bands jumping above their own slow level, and dies away over about 120 ms. `calm` (Reduced
 * Motion): everything rises and falls slowly, and there is no kick.
 */
export function shapeSignal(S: Shaped, raw: ArrayLike<number>, dt: number, calm: boolean): void {
  const up = 1 - Math.exp(-dt / (calm ? 0.45 : 0.03)), down = 1 - Math.exp(-dt / (calm ? 0.9 : 0.16))
  let low = 0, all = 0, lowRaw = 0
  for (let i = 0; i < 64; i++) {
    const v = raw[i] ?? 0, s = S.spec[i]!
    S.spec[i] = s + (v - s) * (v > s ? up : down)
    S.peaks[i] = Math.max(S.peaks[i]! - dt * 0.3, S.spec[i]!)
    if (i < 12) low += S.spec[i]!
    if (i < 8) lowRaw += v
    all += S.spec[i]!
  }
  S.bass = low / 12
  S.energy = all / 64
  lowRaw /= 8
  S.lowSlow += (lowRaw - S.lowSlow) * (1 - Math.exp(-dt / 0.25))
  const hit = calm ? 0 : Math.min(1.5, Math.max(0, lowRaw - S.lowSlow) * 3)
  S.kick = calm ? 0 : Math.max(S.kick * Math.exp(-dt / 0.12), hit)
}

/* ===== drawing at a size the screen can afford ===== */

/** The most pixels each canvas is drawn at: the 2D effects at a 1440x900 screen's at twice its pixel
 *  ratio (a laptop's Retina screen, sharp), the WebGL styles - whose feedback runs two styles at once
 *  through a crossfade - at 1.25x a 1440x900 screen a side, as the board does; the canvas is scaled
 *  up to the screen. So a 5K screen isn't asked for 5K fragments. */
export const MAX_2D_PIXELS = 2880 * 1800
export const MAX_GL_PIXELS = 1800 * 1125

/** The backing store's scale for a canvas `width` x `height` CSS px: the device pixel ratio, capped
 *  so it holds no more than `maxPixels`, and never below half. */
export function backingScale(width: number, height: number, dpr: number, maxPixels: number): number {
  const area = Math.max(1, width * height)
  const cap = Math.sqrt(maxPixels / area)
  return Math.max(0.5, Math.min(dpr > 0 ? dpr : 1, cap))
}

/** Reduced Motion: every clock runs this much slower, so nothing moves fast. */
export const CALM_PACE = 0.35
