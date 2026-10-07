/**
 * The desktop visualizer's Ambient styles in WebGL (2.0.0-player.20) - the canvas board
 * DesktopVisualizer.dc.html's WebGL side, ported: each style a fragment shader (lib/vizShaders.ts)
 * reading its own previous frame from a ping-pong pair of framebuffers; two slots of pairs, so the
 * outgoing and incoming styles both run through a crossfade; and a composite pass mixing them onto
 * the screen. Which style shows, and when the next comes, is lib/visualizer.ts's rotation - a fixed
 * order, never random.
 *
 * It draws at a capped size (backingScale with MAX_GL_PIXELS: about 1.25x a 1440x900 screen a side),
 * so a 5K screen isn't asked for 5K fragments twice over during a crossfade; the canvas is scaled up
 * to the screen by CSS. A lost context is noticed and built again once restored; `init` false means
 * no WebGL here, and the screen falls back to the 2D Ambient, saying so once.
 */

import {
  CALM_PACE, FEEDBACK_STYLES, MAX_GL_PIXELS, backingScale, chooseStyle, fadeMix, feedbackFrame, hueStep, liquidFlow, lutFloats,
  mandalaFlow, mandalaMorph, newLiquid, newMandala, newRotation, rotationTick, wavesCamera,
  type AmbientChoice, type AmbientStyle, type LiquidState, type MandalaState, type Rgb, type Roles, type Rotation, type WavesCamera,
} from '../lib/visualizer'
import { COMPOSITE, FEEDBACK_SHADER, LIQUID, MANDALA, VERTEX, WAVES } from '../lib/vizShaders'

/** What one frame of the Ambient styles is drawn from. */
export interface GlFrame {
  /** seconds since the last frame (real time: the crossfade and the rotation's hold) */
  dt: number
  /** the visualizer's own clock, which runs with the music and slows as it pauses */
  vt: number
  /** the song's position, s - where the Mandala's morph starts the first time it draws */
  position: number
  /** 1 playing .. 0 paused and died away */
  level: number
  playing: boolean
  /** Reduced Motion: every clock slower */
  calm: boolean
  /** musicFeel's readings */
  tempo: number
  beats: number
  aggr: number
  bass: number
  kick: number
  energy: number
  /** the smoothed spectrum (64, 0-1) and the waveform (-1..1) */
  spec: Float32Array
  wave: Float32Array
  choice: AmbientChoice
  palette: { floats: Float32Array; ring: readonly Rgb[]; roles: Roles }
}

interface Program {
  p: WebGLProgram
  u: Record<string, WebGLUniformLocation | null>
}

interface Target {
  tex: WebGLTexture
  fbo: WebGLFramebuffer
}

interface Slot {
  idx: number
  t: [Target, Target]
}

const UNIFORMS = ['uRes', 'uTime', 'uBass', 'uKick', 'uPrev', 'uSpec', 'uHist', 'uWave', 'uPal', 'uA', 'uB', 'uMix',
  'uCore', 'uBody', 'uBody2', 'uRing', 'uFlare', 'uFold', 'uOuter', 'uInv', 'uSrc', 'uForm', 'uLat', 'uRingsQ', 'uFormW', 'uEdge', 'uRoom',
  'uHead', 'uPhase', 'uHeading', 'uRoll', 'uCamH', 'uHorizon', 'uYaw', 'uVanish', 'uFlow', 'uFlow2', 'uFlowStep', 'uSurge',
  'uWarp', 'uDrift', 'uFade', 'uLook', 'uRingP', 'uLineW', 'uLineAng', 'uLineP', 'uBarsP', 'uCoreP', 'uHueA', 'uHueB', 'uHueC']

export class GlAmbient {
  private gl: WebGLRenderingContext | null = null
  private progs: Record<string, Program> | null = null
  private vs: WebGLShader | null = null
  private buf: WebGLBuffer | null = null
  private specTex: WebGLTexture | null = null
  private histTex: WebGLTexture | null = null
  private waveTex: WebGLTexture | null = null
  private slots: [Slot, Slot] | null = null
  private width = 0
  private height = 0
  private lost = false
  private readonly specBytes = new Uint8Array(64)
  private readonly waveBytes = new Uint8Array(256)
  private readonly rotation: Rotation = newRotation()
  private mandala: MandalaState | null = null
  private readonly liquid: LiquidState = newLiquid()
  private readonly drift = { x: 0 }
  private cam: WavesCamera | null = null
  private histHead = 0
  private wavePhase = 0
  private fbT = 0

  constructor(private readonly canvas: HTMLCanvasElement) {}

  /** The context and everything the styles need; false when there is no WebGL here (or a shader
   *  wouldn't build), and everything made is let go. */
  init(): boolean {
    const opts = { alpha: false, antialias: false, depth: false, stencil: false, premultipliedAlpha: false, preserveDrawingBuffer: false }
    let gl: WebGLRenderingContext | null = null
    try {
      gl = (this.canvas.getContext('webgl', opts) ?? this.canvas.getContext('experimental-webgl', opts)) as WebGLRenderingContext | null
    } catch {
      gl = null
    }
    if (!gl) return false
    this.gl = gl
    this.canvas.addEventListener('webglcontextlost', this.onLost)
    this.canvas.addEventListener('webglcontextrestored', this.onRestored)
    if (!this.build()) {
      this.dispose()
      return false
    }
    return true
  }

  /** The style showing (or crossfading in), for the screen's "now:" - null before the first frame. */
  showing(): AmbientStyle | null {
    return this.rotation.cur
  }

  /** The dropdown chose: "Rotate all" gives what shows a fresh hold (lib/visualizer.ts chooseStyle). */
  choose(choice: AmbientChoice): void {
    chooseStyle(this.rotation, choice)
  }

  /** One frame of Ambient, at the canvas's CSS size `cssWidth` x `cssHeight`. */
  draw(frame: GlFrame, cssWidth: number, cssHeight: number): void {
    const gl = this.gl
    if (!gl || this.lost || !this.progs) return
    this.size(cssWidth, cssHeight)
    if (!this.slots) return
    const pace = frame.calm ? CALM_PACE : 1
    const dt = frame.dt * pace
    for (let i = 0; i < 64; i++) this.specBytes[i] = Math.min(255, Math.round((frame.spec[i] ?? 0) * 255))
    const wn = frame.wave.length - 1
    for (let i = 0; i < 256; i++) {
      const x = (i / 255) * wn, j = Math.min(wn - 1, Math.floor(x))
      const v = frame.wave[j]! + (frame.wave[j + 1]! - frame.wave[j]!) * (x - j)
      this.waveBytes[i] = Math.max(0, Math.min(255, Math.round((v * 0.5 + 0.5) * 255)))
    }
    //? the landscape takes a new row nine times a second (slower as a pause fades the music out); the
    //? newest row follows the live spectrum until the next one starts
    this.wavePhase += dt * 9 * (0.25 + 0.75 * frame.level) * frame.tempo
    //? the Media Player styles' own clock, which the tempo speeds up and slows down
    this.fbT += dt * (0.2 + 0.8 * frame.level) * frame.tempo
    while (this.wavePhase >= 1) {
      this.wavePhase -= 1
      this.histHead = (this.histHead + 1) % 64
    }
    this.cam = wavesCamera(frame.vt, this.drift, frame.level, frame.tempo, frame.bass, frame.kick, dt)
    liquidFlow(this.liquid, frame.vt, frame.spec, frame.bass, frame.tempo, dt)
    if (!this.mandala) this.mandala = newMandala(frame.position)
    mandalaFlow(this.mandala, frame.spec, frame.beats, frame.aggr, frame.level, dt)
    gl.activeTexture(gl.TEXTURE1)
    gl.bindTexture(gl.TEXTURE_2D, this.specTex)
    gl.texSubImage2D(gl.TEXTURE_2D, 0, 0, 0, 64, 1, gl.LUMINANCE, gl.UNSIGNED_BYTE, this.specBytes)
    gl.activeTexture(gl.TEXTURE2)
    gl.bindTexture(gl.TEXTURE_2D, this.histTex)
    gl.texSubImage2D(gl.TEXTURE_2D, 0, 0, this.histHead, 64, 1, gl.LUMINANCE, gl.UNSIGNED_BYTE, this.specBytes)
    gl.activeTexture(gl.TEXTURE3)
    gl.bindTexture(gl.TEXTURE_2D, this.waveTex)
    gl.texSubImage2D(gl.TEXTURE_2D, 0, 0, 0, 256, 1, gl.LUMINANCE, gl.UNSIGNED_BYTE, this.waveBytes)

    const A = this.rotation
    const started = rotationTick(A, frame.dt * 1000, frame.playing, frame.choice)
    if (started) this.clearSlot(this.slots[A.curSlot])
    const cur = A.cur!
    const curTex = this.renderStyle(this.slots[A.curSlot], cur, frame)
    const mix = fadeMix(A)
    const fromTex = A.from ? this.renderStyle(this.slots[A.curSlot === 0 ? 1 : 0], A.from, frame) : curTex
    const cp = this.progs['composite']!
    gl.bindFramebuffer(gl.FRAMEBUFFER, null)
    gl.viewport(0, 0, this.width, this.height)
    gl.useProgram(cp.p)
    gl.activeTexture(gl.TEXTURE0)
    gl.bindTexture(gl.TEXTURE_2D, fromTex)
    gl.activeTexture(gl.TEXTURE1)
    gl.bindTexture(gl.TEXTURE_2D, curTex)
    gl.uniform1i(cp.u['uA']!, 0)
    gl.uniform1i(cp.u['uB']!, 1)
    gl.uniform1f(cp.u['uMix']!, mix)
    gl.uniform2f(cp.u['uRes']!, this.width, this.height)
    gl.drawArrays(gl.TRIANGLES, 0, 3)
  }

  /** Everything let go - the context too, which a browser holds few of. */
  dispose(): void {
    const gl = this.gl
    this.canvas.removeEventListener('webglcontextlost', this.onLost)
    this.canvas.removeEventListener('webglcontextrestored', this.onRestored)
    if (gl) {
      this.freeSlots()
      if (this.progs) for (const prog of Object.values(this.progs)) gl.deleteProgram(prog.p)
      if (this.vs) gl.deleteShader(this.vs)
      if (this.buf) gl.deleteBuffer(this.buf)
      for (const tex of [this.specTex, this.histTex, this.waveTex]) if (tex) gl.deleteTexture(tex)
      gl.getExtension('WEBGL_lose_context')?.loseContext()
    }
    this.gl = null
    this.progs = null
    this.vs = null
    this.buf = null
    this.specTex = null
    this.histTex = null
    this.waveTex = null
    this.slots = null
  }

  private readonly onLost = (event: Event) => {
    event.preventDefault()
    this.lost = true
  }

  //? a restored context has none of the old objects: built again, from nothing
  private readonly onRestored = () => {
    this.lost = false
    this.progs = null
    this.slots = null
    this.width = 0
    if (!this.build()) this.dispose()
  }

  private build(): boolean {
    const gl = this.gl
    if (!gl) return false
    this.vs = this.compile(gl.VERTEX_SHADER, VERTEX)
    if (!this.vs) return false
    const sources: Record<string, string> = { mandala: MANDALA, waves: WAVES, liquid: LIQUID, feedback: FEEDBACK_SHADER, composite: COMPOSITE }
    const progs: Record<string, Program> = {}
    for (const [name, source] of Object.entries(sources)) {
      const prog = this.program(source)
      if (!prog) return false
      progs[name] = prog
    }
    this.progs = progs
    this.buf = gl.createBuffer()
    gl.bindBuffer(gl.ARRAY_BUFFER, this.buf)
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW)
    gl.enableVertexAttribArray(0)
    gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0)
    gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1)
    gl.disable(gl.BLEND)
    gl.disable(gl.DEPTH_TEST)
    gl.clearColor(0, 0, 0, 1)
    gl.clear(gl.COLOR_BUFFER_BIT)
    this.specTex = this.dataTexture(64, 1)
    this.histTex = this.dataTexture(64, 64)
    this.waveTex = this.dataTexture(256, 1)
    //? a first size, so the framebuffers can be checked
    this.size(Math.max(1, this.canvas.clientWidth), Math.max(1, this.canvas.clientHeight))
    if (!this.slots) return false
    gl.bindFramebuffer(gl.FRAMEBUFFER, this.slots[0].t[0].fbo)
    const ok = gl.checkFramebufferStatus(gl.FRAMEBUFFER) === gl.FRAMEBUFFER_COMPLETE
    gl.bindFramebuffer(gl.FRAMEBUFFER, null)
    return ok
  }

  private compile(type: number, source: string): WebGLShader | null {
    const gl = this.gl!
    const shader = gl.createShader(type)
    if (!shader) return null
    gl.shaderSource(shader, source)
    gl.compileShader(shader)
    if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
      console.warn('deadwax visualizer: a shader did not compile', gl.getShaderInfoLog(shader))
      gl.deleteShader(shader)
      return null
    }
    return shader
  }

  private program(fragment: string): Program | null {
    const gl = this.gl!
    const fs = this.compile(gl.FRAGMENT_SHADER, fragment)
    if (!fs || !this.vs) return null
    const prog = gl.createProgram()
    if (!prog) return null
    gl.attachShader(prog, this.vs)
    gl.attachShader(prog, fs)
    gl.bindAttribLocation(prog, 0, 'aPos')
    gl.linkProgram(prog)
    gl.deleteShader(fs)
    if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) {
      console.warn('deadwax visualizer: a shader program did not link', gl.getProgramInfoLog(prog))
      gl.deleteProgram(prog)
      return null
    }
    const u: Record<string, WebGLUniformLocation | null> = {}
    for (const name of UNIFORMS) u[name] = gl.getUniformLocation(prog, name)
    return { p: prog, u }
  }

  private dataTexture(width: number, height: number): WebGLTexture | null {
    const gl = this.gl!
    const tex = gl.createTexture()
    gl.bindTexture(gl.TEXTURE_2D, tex)
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.LUMINANCE, width, height, 0, gl.LUMINANCE, gl.UNSIGNED_BYTE, new Uint8Array(width * height))
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
    return tex
  }

  /** Cleared to nothing at all, alpha included: the Media Player styles keep their brightness in the
   *  alpha channel, and a slot that started opaque would start them white. */
  private target(): Target {
    const gl = this.gl!
    const tex = gl.createTexture()!
    gl.bindTexture(gl.TEXTURE_2D, tex)
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, this.width, this.height, 0, gl.RGBA, gl.UNSIGNED_BYTE, null)
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
    const fbo = gl.createFramebuffer()!
    gl.bindFramebuffer(gl.FRAMEBUFFER, fbo)
    gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, tex, 0)
    gl.clearColor(0, 0, 0, 0)
    gl.clear(gl.COLOR_BUFFER_BIT)
    gl.bindFramebuffer(gl.FRAMEBUFFER, null)
    return { tex, fbo }
  }

  private freeSlots(): void {
    const gl = this.gl
    if (!gl || !this.slots) return
    for (const slot of this.slots) {
      for (const target of slot.t) {
        gl.deleteTexture(target.tex)
        gl.deleteFramebuffer(target.fbo)
      }
    }
    this.slots = null
  }

  private clearSlot(slot: Slot): void {
    const gl = this.gl!
    gl.clearColor(0, 0, 0, 0)
    for (const target of slot.t) {
      gl.bindFramebuffer(gl.FRAMEBUFFER, target.fbo)
      gl.clear(gl.COLOR_BUFFER_BIT)
    }
    gl.bindFramebuffer(gl.FRAMEBUFFER, null)
    slot.idx = 0
  }

  /** The drawing size from the canvas's CSS size and the screen's pixel ratio, capped - remade (which
   *  clears the trails) only when it has really changed. */
  private size(cssWidth: number, cssHeight: number): void {
    const gl = this.gl
    if (!gl) return
    const scale = backingScale(cssWidth, cssHeight, typeof devicePixelRatio === 'number' ? devicePixelRatio : 1, MAX_GL_PIXELS)
    const width = Math.max(1, Math.round(cssWidth * scale))
    const height = Math.max(1, Math.round(cssHeight * scale))
    if (this.slots && Math.abs(width - this.width) <= 1 && Math.abs(height - this.height) <= 1) return
    this.width = width
    this.height = height
    this.canvas.width = width
    this.canvas.height = height
    this.freeSlots()
    this.slots = [{ idx: 0, t: [this.target(), this.target()] }, { idx: 0, t: [this.target(), this.target()] }]
  }

  private renderStyle(slot: Slot, style: AmbientStyle, frame: GlFrame): WebGLTexture {
    const gl = this.gl!
    const feedback = FEEDBACK_STYLES.includes(style)
    const prog = this.progs![feedback ? 'feedback' : style]!, u = prog.u
    const read = slot.t[slot.idx]!, write = slot.t[slot.idx === 0 ? 1 : 0]
    const kick = Math.min(1.5, frame.kick)
    gl.bindFramebuffer(gl.FRAMEBUFFER, write.fbo)
    gl.viewport(0, 0, this.width, this.height)
    gl.useProgram(prog.p)
    gl.activeTexture(gl.TEXTURE0)
    gl.bindTexture(gl.TEXTURE_2D, read.tex)
    gl.activeTexture(gl.TEXTURE1)
    gl.bindTexture(gl.TEXTURE_2D, this.specTex)
    gl.activeTexture(gl.TEXTURE2)
    gl.bindTexture(gl.TEXTURE_2D, this.histTex)
    gl.activeTexture(gl.TEXTURE3)
    gl.bindTexture(gl.TEXTURE_2D, this.waveTex)
    gl.uniform1i(u['uPrev']!, 0)
    gl.uniform1i(u['uSpec']!, 1)
    gl.uniform1i(u['uHist']!, 2)
    gl.uniform1i(u['uWave']!, 3)
    gl.uniform2f(u['uRes']!, this.width, this.height)
    gl.uniform1f(u['uTime']!, frame.vt)
    gl.uniform1f(u['uBass']!, frame.bass)
    gl.uniform1f(u['uKick']!, kick)
    gl.uniform3fv(u['uPal']!, frame.palette.floats)
    if (feedback) {
      const P = feedbackFrame(style, { t: this.fbT, bass: frame.bass, kick, energy: frame.energy }, frame.tempo)!
      const h = hueStep(frame.vt, P.hue[0], P.hue[1])
      gl.uniform3fv(u['uHueA']!, lutFloats(frame.palette.ring, h))
      gl.uniform3fv(u['uHueB']!, lutFloats(frame.palette.ring, h + 1 / 6))
      gl.uniform3fv(u['uHueC']!, lutFloats(frame.palette.ring, h + 2 / 6))
      gl.uniform4fv(u['uWarp']!, P.warp)
      gl.uniform4fv(u['uDrift']!, P.drift)
      gl.uniform4fv(u['uFade']!, P.fade)
      gl.uniform4fv(u['uLook']!, P.look)
      gl.uniform4fv(u['uRingP']!, P.ring)
      gl.uniform3fv(u['uLineW']!, P.lineW)
      gl.uniform3fv(u['uLineAng']!, P.lineAng)
      gl.uniform4fv(u['uLineP']!, P.line)
      gl.uniform4fv(u['uBarsP']!, P.bars)
      gl.uniform4fv(u['uCoreP']!, P.core)
    } else if (style === 'mandala') {
      const roles = frame.palette.roles
      const M = mandalaMorph(this.mandala!, frame.aggr)
      gl.uniform3fv(u['uCore']!, roles.core)
      gl.uniform3fv(u['uBody']!, roles.body)
      gl.uniform3fv(u['uBody2']!, roles.body2)
      gl.uniform3fv(u['uRing']!, roles.ring)
      gl.uniform3fv(u['uFlare']!, roles.flare)
      gl.uniform4fv(u['uFold']!, M.fold)
      gl.uniform1f(u['uOuter']!, M.outer)
      gl.uniform4fv(u['uInv']!, M.inv)
      gl.uniform4fv(u['uSrc']!, M.src)
      gl.uniform4fv(u['uForm']!, M.form)
      gl.uniform4fv(u['uLat']!, M.lat)
      gl.uniform4fv(u['uRingsQ']!, M.rings)
      gl.uniform3fv(u['uFormW']!, M.formW)
      gl.uniform3fv(u['uEdge']!, M.edge)
      gl.uniform4fv(u['uRoom']!, M.room)
    } else if (style === 'waves') {
      const C = this.cam!
      gl.uniform1f(u['uHead']!, this.histHead)
      gl.uniform1f(u['uPhase']!, this.wavePhase)
      gl.uniform1f(u['uHeading']!, C.heading)
      gl.uniform1f(u['uRoll']!, C.roll)
      gl.uniform1f(u['uCamH']!, C.camH)
      gl.uniform1f(u['uHorizon']!, C.horizon)
      gl.uniform1f(u['uYaw']!, C.yaw)
      gl.uniform1f(u['uVanish']!, C.vanish)
    } else if (style === 'liquid') {
      const L = this.liquid
      gl.uniform4f(u['uFlow']!, L.x, L.y, L.phase, 2.8 + 2.4 * L.bass)
      gl.uniform4f(u['uFlow2']!, L.dx, L.dy, 0.02 + 0.3 * L.high, L.col)
      gl.uniform2f(u['uFlowStep']!, L.sx, L.sy)
      gl.uniform1f(u['uSurge']!, L.bass)
    }
    gl.drawArrays(gl.TRIANGLES, 0, 3)
    slot.idx = slot.idx === 0 ? 1 : 0
    return write.tex
  }
}
