/**
 * The test bench's listening room (2.0.0-player.36): A, B and C - or an ABX trial's A, B and X - played
 * together from one moment, all but one silent, so switching is heard at the same moment of the
 * recording. A switch fades what plays out, leaves a moment's silence, and fades the one chosen in -
 * never two clips heard at once (switchPoints). A crossfade between two clips the same tone a fraction of
 * a millisecond apart - A and C, where deadwax's read head strays from the smooth path - dipped and
 * clicked in the middle of the fade, where a switch to X's twin didn't: X given away by the switch, not
 * the sound (review of 2.0.0-player.36). An AudioContext of its own at the recording's rate (so nothing
 * is resampled on the way), made only in a tap - the play button's - since a browser starts audio only
 * from one; it needs no secure page. Each clip loops. Nothing of it touches the deck, the turntable or any
 * media element.
 */

/** A switch fades what plays out over SWITCH_FADE_S, is silent SWITCH_GAP_S, and fades the one chosen in
 *  over SWITCH_FADE_S - the same whichever clips it is between. */
export const SWITCH_FADE_S = 0.005
export const SWITCH_GAP_S = 0.04

/**
 * How each clip's gain moves at a switch to `index` at context time `now`, from the gains it has then:
 * (time, value) points, linear between, held after the last. Every clip out over SWITCH_FADE_S; the one
 * chosen held silent SWITCH_GAP_S more, then in over SWITCH_FADE_S. So at no moment are two clips heard
 * together, and every switch sounds alike, whatever it is between.
 */
export function switchPoints(gains: number[], index: number, now: number): [number, number][][] {
  const out = now + SWITCH_FADE_S
  return gains.map((gain, i) => {
    const points: [number, number][] = [[now, gain], [out, 0]]
    if (i === index) points.push([out + SWITCH_GAP_S, 0], [out + SWITCH_GAP_S + SWITCH_FADE_S, 1])
    return points
  })
}

/** A gain's value at `t` along its points. */
export function gainAt(points: [number, number][], t: number): number {
  if (t <= points[0]![0]) return points[0]![1]
  for (let i = 1; i < points.length; i++) {
    const [t1, v1] = points[i]!
    if (t <= t1) {
      const [t0, v0] = points[i - 1]!
      return t1 > t0 ? v0 + ((v1 - v0) * (t - t0)) / (t1 - t0) : v1
    }
  }
  return points[points.length - 1]![1]
}

type Listener = () => void

export class ListeningRoom {
  private context: AudioContext | null = null
  private clips: Float32Array[] = []
  private rate = 48000
  private buffers: AudioBuffer[] | null = null
  private sources: AudioBufferSourceNode[] = []
  private gains: GainNode[] = []
  private chosen = 0
  /** where it was let go, seconds into the clips, and when (context time) it last started from there */
  private offset = 0
  private startedAt = 0
  private running = false
  private readonly listeners = new Set<Listener>()

  /** New clips (all one length), and which plays: stopped, from their start. */
  load(clips: Float32Array[], rate: number, chosen = 0): void {
    this.stopSources()
    this.clips = clips
    this.rate = rate
    this.buffers = null
    this.offset = 0
    this.chosen = chosen
    this.running = false
    this.changed()
  }

  get playing(): boolean {
    return this.running
  }

  get selected(): number {
    return this.chosen
  }

  /** How many clips it holds. */
  get count(): number {
    return this.clips.length
  }

  get length(): number {
    return (this.clips[0]?.length ?? 0) / this.rate
  }

  /**
   * Where it is, seconds into the clips. Never before where it started: the clips start a moment after the
   * tap (play()'s 20 ms), and a context still starting holds its clock - a pause in between, a quick second
   * press, was a negative offset that every later start refused, Play dead until From the start (review
   * of 2.0.0-player.36).
   */
  position(): number {
    if (!this.running || !this.context) return this.offset
    const length = this.length || 1
    const at = this.offset + Math.max(0, this.context.currentTime - this.startedAt)
    return ((at % length) + length) % length
  }

  onChange(listener: Listener): () => void {
    this.listeners.add(listener)
    return () => this.listeners.delete(listener)
  }

  /** Play or pause - IN A TAP (the room's context is made in the first). */
  toggle(): void {
    if (this.running) this.pause()
    else this.play()
  }

  /** Which clip is heard - from the same moment of the recording, through a moment's silence. */
  select(index: number): void {
    if (index < 0 || index >= this.clips.length) return
    const was = this.chosen
    this.chosen = index
    const context = this.context
    if (context && this.running && index !== was) {
      const now = context.currentTime
      const plans = switchPoints(this.gains.map((gain) => gain.gain.value), index, now)
      this.gains.forEach((gain, i) => {
        gain.gain.cancelScheduledValues(now)
        for (const [at, value] of plans[i]!) {
          if (at <= now) gain.gain.setValueAtTime(value, now)
          else gain.gain.linearRampToValueAtTime(value, at)
        }
      })
    }
    this.changed()
  }

  /** Back to the start of the clips (playing on, if it was). */
  restart(): void {
    const was = this.running
    this.pause()
    this.offset = 0
    if (was) this.play()
    this.changed()
  }

  close(): void {
    this.stopSources()
    this.running = false
    this.context?.close().catch(() => undefined)
    this.context = null
    this.buffers = null
  }

  private play(): void {
    if (!this.clips.length) return
    const context = this.make()
    if (!context) return
    if (context.state !== 'running') context.resume().catch(() => undefined)
    if (!this.buffers) {
      this.buffers = this.clips.map((clip) => {
        const buffer = context.createBuffer(2, Math.max(1, clip.length), this.rate)
        buffer.getChannelData(0).set(clip)
        buffer.getChannelData(1).set(clip)
        return buffer
      })
    }
    const at = context.currentTime + 0.02
    this.sources = []
    this.gains = []
    this.buffers.forEach((buffer, i) => {
      const source = context.createBufferSource()
      source.buffer = buffer
      source.loop = true
      const gain = context.createGain()
      gain.gain.value = i === this.chosen ? 1 : 0
      source.connect(gain)
      gain.connect(context.destination)
      source.start(at, Math.max(0, this.offset) % (buffer.duration || 1))
      this.sources.push(source)
      this.gains.push(gain)
    })
    this.startedAt = at
    this.running = true
    this.changed()
  }

  private pause(): void {
    if (!this.running) return
    this.offset = this.position()
    this.stopSources()
    this.running = false
    this.changed()
  }

  private stopSources(): void {
    for (const source of this.sources) {
      try {
        source.stop()
        source.disconnect()
      } catch {
        //? stopped already
      }
    }
    for (const gain of this.gains) gain.disconnect()
    this.sources = []
    this.gains = []
  }

  /** The room's context, made the first time - in the tap that plays. At the clips' rate where the
   *  browser takes one, so nothing is resampled; at its own otherwise. */
  private make(): AudioContext | null {
    if (this.context && this.context.state !== 'closed') return this.context
    const scope = globalThis as { AudioContext?: new (options?: AudioContextOptions) => AudioContext; webkitAudioContext?: new () => AudioContext }
    const Room = scope.AudioContext ?? scope.webkitAudioContext
    if (!Room) return null
    try {
      this.context = new Room({ sampleRate: this.rate })
    } catch {
      this.context = new Room()
    }
    return this.context
  }

  private changed(): void {
    for (const listener of [...this.listeners]) listener()
  }
}
