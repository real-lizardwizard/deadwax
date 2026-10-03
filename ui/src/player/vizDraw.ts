/**
 * The desktop visualizer's Canvas 2D effects (2.0.0-player.20) - Bars, Scope and Halo, and the plain
 * Ambient that shows where there is no WebGL - ported from the canvas board DesktopVisualizer.dc.html.
 *
 * The board draws on a fixed 1440x900; a screen is any shape, so here the drawing is 900 units high
 * and as wide as the screen's shape makes it (`width`, in units: 1440 on a 16:10 screen, 1600 on a
 * 16:9 one), and everything the board placed by x is placed at the same share of that width. Heights,
 * radii and line widths are the board's own, in units. The caller sets the transform from units to
 * the canvas's pixels.
 */

import { lutColour, type Rgb } from '../lib/visualizer'

/** What the 2D effects read each frame. */
export interface DrawState {
  /** the drawing's width in units (900 high) */
  width: number
  /** seconds since the last frame, at the motion's pace (slower under Reduced Motion) */
  dt: number
  /** the visualizer's own clock */
  vt: number
  level: number
  spec: Float32Array
  peaks: Float32Array
  wave: Float32Array
  bass: number
  kick: number
  lut: readonly Rgb[]
  ring: readonly Rgb[]
}

/** What Halo turns: its ring's angle and the record's, kept between frames. */
export interface HaloState {
  rot: number
  spin: number
}

/** Halo's record: the album's CD art when deadwax holds some, else a black record with the cover on
 *  its label - the board's stand-in, made real. */
export interface DiscPictures {
  disc: CanvasImageSource | null
  cover: CanvasImageSource | null
}

export const BACKGROUND = '#050408'
const HEIGHT = 900

/** Bars: 128 bars, the lows in the middle and mirrored out to the highs at both edges, standing on a
 *  floor line with falling peak caps and a reflection that fades out below it. */
export function drawBars(ctx: CanvasRenderingContext2D, s: DrawState): void {
  const W = s.width
  ctx.fillStyle = BACKGROUND
  ctx.fillRect(0, 0, W, HEIGHT)
  const floor = 610, maxH = 390, x0 = W * (96 / 1440), span = W * (1248 / 1440), slot = span / 128, bw = slot - 3
  const glow = ctx.createRadialGradient(W / 2, floor, 0, W / 2, floor, 640)
  glow.addColorStop(0, lutColour(s.lut, 0.1, 0.08 + 0.22 * s.bass))
  glow.addColorStop(1, lutColour(s.lut, 0.1, 0))
  ctx.fillStyle = glow
  ctx.fillRect(0, 0, W, HEIGHT)
  for (let b = 0; b < 128; b++) {
    const band = b < 64 ? 63 - b : b - 64
    const v = s.spec[band]!
    const h = Math.max(2, v * maxH)
    const x = x0 + b * slot + 1.5
    const u = band / 63
    ctx.fillStyle = lutColour(s.lut, u, 0.55 + 0.45 * Math.min(1, v * 1.4))
    ctx.fillRect(x, floor - h, bw, h)
    ctx.fillStyle = lutColour(s.lut, u, 0.2)
    ctx.fillRect(x, floor + 3, bw, h * 0.45)
    ctx.fillStyle = 'rgba(255,255,255,0.7)'
    ctx.fillRect(x, floor - Math.max(h, s.peaks[band]! * maxH) - 5, bw, 2)
  }
  const fade = ctx.createLinearGradient(0, floor, 0, floor + 190)
  fade.addColorStop(0, 'rgba(5,4,8,0)')
  fade.addColorStop(1, 'rgba(5,4,8,1)')
  ctx.fillStyle = fade
  ctx.fillRect(0, floor + 2, W, 200)
  ctx.fillStyle = 'rgba(255,255,255,0.28)'
  ctx.fillRect(x0, floor, span, 1)
}

/** Scope: the waveform as one thin line across the middle, over a slow afterimage - the canvas is only
 *  partly cleared each frame, so the last half-second of lines hangs behind it. */
export function drawScope(ctx: CanvasRenderingContext2D, s: DrawState): void {
  const W = s.width
  const f = 1 - Math.exp(-s.dt / 0.16)
  ctx.fillStyle = `rgba(5,4,8,${f.toFixed(3)})`
  ctx.fillRect(0, 0, W, HEIGHT)
  const N = s.wave.length, mid = 450, A = 250
  const left = W * (80 / 1440), across = W * (1280 / 1440)
  const grad = ctx.createLinearGradient(left, 0, left + across, 0)
  for (let k = 0; k <= 5; k++) grad.addColorStop(k / 5, lutColour(s.lut, k / 5, 1))
  ctx.beginPath()
  for (let j = 0; j < N; j++) {
    const x = left + (j / (N - 1)) * across, y = mid - s.wave[j]! * A
    if (j) ctx.lineTo(x, y)
    else ctx.moveTo(x, y)
  }
  ctx.lineJoin = 'round'
  ctx.lineCap = 'round'
  ctx.globalCompositeOperation = 'lighter'
  ctx.strokeStyle = grad
  ctx.globalAlpha = 0.14
  ctx.lineWidth = 10
  ctx.stroke()
  ctx.globalAlpha = 0.32
  ctx.lineWidth = 4
  ctx.stroke()
  ctx.globalAlpha = 1
  ctx.lineWidth = 1.6
  ctx.stroke()
  ctx.strokeStyle = 'rgba(255,255,255,0.5)'
  ctx.lineWidth = 0.6
  ctx.stroke()
}

/** Halo: a ring of 128 spokes (the spectrum mirrored, lows at the top) round the record. The ring
 *  turns about once a minute and the kick pushes it outward; the record spins slowly. */
export function drawHalo(ctx: CanvasRenderingContext2D, s: DrawState, halo: HaloState, pictures: DiscPictures): void {
  const cx = s.width / 2, cy = 450, k = s.kick
  halo.rot += s.dt * 0.11 * (0.3 + 0.7 * s.level)
  halo.spin += s.dt * 0.8 * s.level
  ctx.fillStyle = BACKGROUND
  ctx.fillRect(0, 0, s.width, HEIGHT)
  const discR = 150 * (1 + 0.02 * k)
  const ringR = discR + 24 + 22 * k
  const hue = (s.vt * 0.012) % 1
  const back = ctx.createRadialGradient(cx, cy, discR * 0.8, cx, cy, 620)
  back.addColorStop(0, lutColour(s.ring, hue, 0.1 + 0.28 * s.bass))
  back.addColorStop(0.35, lutColour(s.ring, hue, 0.05 + 0.08 * s.bass))
  back.addColorStop(1, lutColour(s.ring, hue, 0))
  ctx.fillStyle = back
  ctx.fillRect(0, 0, s.width, HEIGHT)
  ctx.globalCompositeOperation = 'lighter'
  ctx.lineCap = 'round'
  for (let pass = 0; pass < 2; pass++) {
    ctx.lineWidth = pass ? 3.4 : 10
    const alpha = pass ? 0.95 : 0.13
    for (let a = 0; a < 128; a++) {
      const band = a < 64 ? a : 127 - a
      const len = 5 + s.spec[band]! * 190
      const ang = halo.rot + (a / 128) * Math.PI * 2 - Math.PI / 2
      const c = Math.cos(ang), sn = Math.sin(ang)
      ctx.strokeStyle = lutColour(s.ring, a / 128, alpha)
      ctx.beginPath()
      ctx.moveTo(cx + c * ringR, cy + sn * ringR)
      ctx.lineTo(cx + c * (ringR + len), cy + sn * (ringR + len))
      ctx.stroke()
    }
  }
  ctx.strokeStyle = `rgba(255,255,255,${(0.1 + 0.25 * Math.min(1, k)).toFixed(3)})`
  ctx.lineWidth = 1
  ctx.beginPath()
  ctx.arc(cx, cy, ringR - 9, 0, Math.PI * 2)
  ctx.stroke()
  ctx.strokeStyle = lutColour(s.ring, hue, 0.3 * Math.min(1, k))
  ctx.lineWidth = 2
  ctx.beginPath()
  ctx.arc(cx, cy, discR + 3, 0, Math.PI * 2)
  ctx.stroke()
  ctx.globalCompositeOperation = 'source-over'
  drawDisc(ctx, cx, cy, discR, halo.spin, pictures)
}

/** The record: the CD art turning, or a black record with grooves and the cover on its label - and
 *  either way a sheen that stays where it is while the record turns under it. */
function drawDisc(ctx: CanvasRenderingContext2D, cx: number, cy: number, R: number, spin: number, pictures: DiscPictures): void {
  ctx.save()
  ctx.translate(cx, cy)
  ctx.rotate(spin)
  ctx.save()
  ctx.beginPath()
  ctx.arc(0, 0, R, 0, Math.PI * 2)
  ctx.clip()
  if (pictures.disc) {
    ctx.drawImage(pictures.disc, -R, -R, R * 2, R * 2)
  } else {
    ctx.fillStyle = '#0b0a0d'
    ctx.fillRect(-R, -R, R * 2, R * 2)
    ctx.strokeStyle = 'rgba(255,255,255,0.035)'
    ctx.lineWidth = 1
    ctx.beginPath()
    for (let r = R * 0.42; r < R - 5; r += 4) {
      ctx.moveTo(r, 0)
      ctx.arc(0, 0, r, 0, Math.PI * 2)
    }
    ctx.stroke()
  }
  ctx.restore()
  if (typeof ctx.createConicGradient === 'function') {
    const sheen = ctx.createConicGradient(-spin - 0.9, 0, 0)
    sheen.addColorStop(0, 'rgba(255,255,255,0)')
    sheen.addColorStop(0.07, 'rgba(255,255,255,0.08)')
    sheen.addColorStop(0.14, 'rgba(255,255,255,0)')
    sheen.addColorStop(0.5, 'rgba(255,255,255,0)')
    sheen.addColorStop(0.57, 'rgba(255,255,255,0.06)')
    sheen.addColorStop(0.64, 'rgba(255,255,255,0)')
    sheen.addColorStop(1, 'rgba(255,255,255,0)')
    ctx.fillStyle = sheen
    ctx.beginPath()
    ctx.arc(0, 0, R, 0, Math.PI * 2)
    ctx.fill()
  }
  ctx.strokeStyle = 'rgba(255,255,255,0.12)'
  ctx.lineWidth = 1.5
  ctx.beginPath()
  ctx.arc(0, 0, R - 0.75, 0, Math.PI * 2)
  ctx.stroke()
  if (!pictures.disc) {
    const L = R * 0.36
    ctx.save()
    ctx.beginPath()
    ctx.arc(0, 0, L, 0, Math.PI * 2)
    ctx.fillStyle = '#030303'
    ctx.fill()
    ctx.clip()
    if (pictures.cover) ctx.drawImage(pictures.cover, -L, -L, L * 2, L * 2)
    ctx.restore()
    ctx.strokeStyle = 'rgba(255,255,255,0.14)'
    ctx.lineWidth = 1
    ctx.beginPath()
    ctx.arc(0, 0, L, 0, Math.PI * 2)
    ctx.stroke()
    ctx.fillStyle = '#1a1820'
    ctx.beginPath()
    ctx.arc(0, 0, 2.6, 0, Math.PI * 2)
    ctx.fill()
  }
  ctx.restore()
}

/** Ambient without WebGL: the plain version - six soft blobs, one per colour, drifting and swelling
 *  with the bass under a vignette. The screen says it's the simple version. */
export function drawAmbient2d(ctx: CanvasRenderingContext2D, s: DrawState): void {
  const W = s.width, cx = W / 2
  ctx.fillStyle = '#040306'
  ctx.fillRect(0, 0, W, HEIGHT)
  ctx.globalCompositeOperation = 'screen'
  const breathe = 0.82 + 0.4 * s.bass
  for (let i = 0; i < 6; i++) {
    const sp = 1 + i * 0.13
    const x = cx + 560 * (W / 1440) * Math.sin(s.vt * 0.045 * sp + i * 1.1)
    const y = 450 + 330 * Math.cos(s.vt * 0.037 * sp + i * 2.3)
    const r = (380 + 120 * Math.sin(s.vt * 0.11 + i * 1.7)) * breathe
    const u = i / 5
    const g = ctx.createRadialGradient(x, y, 0, x, y, r)
    g.addColorStop(0, lutColour(s.lut, u, 0.5))
    g.addColorStop(0.5, lutColour(s.lut, u, 0.2))
    g.addColorStop(1, lutColour(s.lut, u, 0))
    ctx.fillStyle = g
    ctx.fillRect(x - r, y - r, r * 2, r * 2)
  }
  ctx.fillStyle = lutColour(s.lut, 0.5, 0.05 * Math.min(1, s.kick))
  ctx.fillRect(0, 0, W, HEIGHT)
  ctx.globalCompositeOperation = 'source-over'
  const vig = ctx.createRadialGradient(cx, 450, 260, cx, 450, Math.max(900, W * 0.625))
  vig.addColorStop(0, 'rgba(0,0,0,0)')
  vig.addColorStop(1, 'rgba(0,0,0,0.6)')
  ctx.fillStyle = vig
  ctx.fillRect(0, 0, W, HEIGHT)
}
