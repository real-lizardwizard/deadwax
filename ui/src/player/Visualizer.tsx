import type { RefObject } from 'preact'
import { useEffect, useLayoutEffect, useMemo, useRef, useState } from 'preact/hooks'

import { isAbort, latestOnly } from '../lib/latest'
import { feelWords, musicFeel, newFeel } from '../lib/musicFeel'
import { nextIndex, type QueueTrack } from '../lib/playQueue'
import { isFlac, resamples, type MaxRate } from '../lib/streamWrap'
import { playingDisc } from '../lib/turntable'
import {
  CALM_PACE, EFFECTS, EFFECT_NAMES, MAX_2D_PIXELS, PURPLE, PURPLE_ROLES, STYLE_NAMES, STYLE_ROWS, WAVE_POINTS, backingScale, coverPalette,
  cycleEffect, idleSignal, makeLut, newShaped, palFloats, rolesFrom, shapeSignal,
  type AmbientChoice, type AmbientStyle, type Colours, type Effect, type Rgb, type Roles,
} from '../lib/visualizer'
import type { Seeing, SyncSong } from '../lib/vizSync'
import { readVizColours, readVizEffect, readVizStyle, writeVizColours, writeVizEffect, writeVizStyle } from '../state/persisted'
import { coverUrl, discArtUrl, playedAlbum } from './api'
import { Cover } from './Cover'
import { CheckIcon, ChevronDownIcon, LeaveFullScreenIcon, PauseIcon, PlayIcon } from './icons'
import type { Player } from './usePlayer'
import { BACKGROUND, drawAmbient2d, drawBars, drawHalo, drawScope, type DiscPictures, type DrawState, type HaloState } from './vizDraw'
import { GlAmbient } from './vizGl'
import { VizListener, closeVisualizerAudio, resumeVisualizerAudio, suspendVisualizerAudio } from './vizAudio'

/** How long the controls stay after the pointer last moved, while the music plays, in ms. */
export const CHROME_IDLE_MS = 3000
/** How often that is looked at, ms. */
const IDLE_CHECK_MS = 400
/** A press that brought the faded controls back: the click it makes within this long is swallowed,
 *  so a tap where a hidden control was doesn't press it, ms. */
export const WAKE_CLICK_MS = 700
/** The class on <html> while it shows: the page behind doesn't scroll (app.css, as each sheet's own). */
export const SCROLL_LOCK = 'app-viz-open'
/** How long focus waits to go back to the player bar's button for the browser to leave full screen, ms. */
const FULL_SCREEN_LEAVE_MS = 2000

/** A colour scheme ready to draw with: the 2D effects' two LUTs, the shaders' floats, the Mandala's parts. */
interface Scheme {
  cols: readonly Rgb[]
  lut: Rgb[]
  ring: Rgb[]
  floats: Float32Array
  roles: Roles
}

function scheme(cols: readonly Rgb[], roles: Roles): Scheme {
  return { cols, lut: makeLut(cols, false), ring: makeLut(cols, true), floats: palFloats(cols), roles }
}

const PURPLE_SCHEME = scheme(PURPLE, PURPLE_ROLES)

/** What the frame loop keeps between frames: none of it is a render. */
interface Loop {
  raf: number
  last: number
  count: number
  level: number
  vt: number
  idleT: number
  calm: boolean
  raw: Float32Array
  wave: Float32Array
  shaped: ReturnType<typeof newShaped>
  feel: ReturnType<typeof newFeel>
  halo: HaloState
  drawn: string
  gl: GlAmbient | null
  glTried: boolean
  /** the cover's colours and pictures, for the song showing */
  coverScheme: Scheme | null
  pictures: DiscPictures
}

/**
 * The desktop's full-screen visualizer (2.0.0-player.20): the canvas board DesktopVisualizer.dc.html,
 * made real. Drawn by App over everything on a desktop only (from 1024px), opened from the player
 * bar's button; `open` false draws nothing, and every part of it - the frame loop, the silent copy,
 * the audio context - exists only while it is open.
 */
export function Visualizer({ open, player, opener, onClose }: {
  open: boolean
  player: Player
  /** the player bar's button, taken in the click that opened it: focus goes back there */
  opener: RefObject<HTMLElement | null>
  onClose: () => void
}) {
  if (!open) return null
  return <VisualizerScreen player={player} opener={opener} onClose={onClose} />
}

/**
 * The screen itself. It takes the whole screen (requestFullscreen on its own element, or - refused -
 * a fixed layer over the whole window) and closes on Escape, its close button, or leaving full screen.
 *
 *  - THE EFFECTS, as the board draws them: Bars, Scope and Halo in Canvas 2D (player/vizDraw.ts), and
 *    Ambient in WebGL (player/vizGl.ts) - its styles from a dropdown, or "Rotate all" through them in
 *    one fixed order (lib/visualizer.ts). Without WebGL, Ambient is the board's plain 2D version, said
 *    once on screen. Colours from the cover (lib/visualizer.ts coverPalette, of the playing album's
 *    cover) or deadwax's purple. The three choices are kept on this device (state/persisted.ts).
 *  - THE SOUND IT SEES is a silent copy of the song (player/vizAudio.ts) - never the player's own
 *    element. A song that can't be seen (not a FLAC; its window couldn't be had) runs the effects from
 *    a calm idle signal, and one plain line says so.
 *  - THE FEEL: lib/musicFeel.ts reads the copy's spectrum and waveform; the shapes follow the feel,
 *    the speeds the tempo. Silence and the idle signal hold it.
 *  - THE CONTROLS - the song, the effect, the colours, the style, play/pause and Leave full screen -
 *    fade after CHROME_IDLE_MS without the pointer moving while the music plays (never while paused,
 *    pointed at, or with the style list open), and come back on a move, a press or a key - a tap on a
 *    touch screen moves no pointer, and that tap only brings them back (WAKE_CLICK_MS), never presses
 *    a control that was hidden under it. Space plays or pauses (the player's own toggle, from the key
 *    or the click - app-rules allows this file that one action, called only in onToggle; a held key's
 *    repeats ignored), V and Shift+V step through the effects, Escape leaves. Tab stays inside it,
 *    and focus never falls out of it: a control that goes with focus on it (the style list closing,
 *    the Style button leaving with Ambient) hands it back (the Style button, or the screen itself).
 *    The style list is a listbox: it opens on the chosen style, and the arrows, Home and End move
 *    through it. The page behind doesn't scroll while it shows (SCROLL_LOCK).
 *  - IT COSTS NOTHING HIDDEN: the frame loop runs only while it shows and the page is visible, the
 *    audio context is suspended while hidden, and both canvases are drawn at a capped size.
 *  - REDUCED MOTION: everything runs at CALM_PACE, the spectrum rises and falls slowly, and nothing
 *    is pushed by a kick - a calm, slow version of the same.
 */
function VisualizerScreen({ player, opener, onClose }: { player: Player; opener: RefObject<HTMLElement | null>; onClose: () => void }) {
  const [effect, setEffect] = useState<Effect>(readVizEffect)
  const [colours, setColours] = useState<Colours>(readVizColours)
  const [choice, setChoice] = useState<AmbientChoice>(readVizStyle)
  const [menuOpen, setMenuOpen] = useState(false)
  const [awake, setAwake] = useState(true)
  const [glFailed, setGlFailed] = useState(false)
  const [feelText, setFeelText] = useState('')
  const [nowStyle, setNowStyle] = useState<AmbientStyle | null>(null)
  const [seeing, setSeeing] = useState<{ seeing: Seeing; why: string | null }>({ seeing: 'nothing', why: null })

  const root = useRef<HTMLDivElement>(null)
  const canvas = useRef<HTMLCanvasElement>(null)
  const glCanvas = useRef<HTMLCanvasElement>(null)
  const styleButton = useRef<HTMLButtonElement>(null)
  const styleList = useRef<HTMLDivElement>(null)
  const lastActive = useRef(performance.now())
  const overChrome = useRef(false)
  const seeingNow = useRef<Seeing>('nothing')
  //? when a press last brought the faded controls back (WAKE_CLICK_MS)
  const wokeByPress = useRef(0)

  const visible = awake || !player.playing || menuOpen
  //? what the frame loop reads, kept in step every render: the player, the choices, what is showing
  const latest = useRef({ player, effect, colours, choice, glFailed, menuOpen, awake, visible })
  latest.current = { player, effect, colours, choice, glFailed, menuOpen, awake, visible }
  const closing = useRef(onClose)
  closing.current = onClose

  const listener = useMemo(() => new VizListener((next, why) => {
    seeingNow.current = next
    setSeeing({ seeing: next, why })
  }), [])

  const loop = useRef<Loop>({
    raf: 0, last: 0, count: 0, level: player.playing ? 1 : 0, vt: 0, idleT: 0, calm: false,
    raw: new Float32Array(64), wave: new Float32Array(WAVE_POINTS), shaped: newShaped(), feel: newFeel(),
    halo: { rot: 0, spin: 0 }, drawn: '', gl: null, glTried: false, coverScheme: null, pictures: { disc: null, cover: null },
  })

  const wake = () => {
    lastActive.current = performance.now()
    if (!latest.current.awake) setAwake(true)
  }

  /** Play or pause - the player's own toggle, straight from the click or the key. */
  const onToggle = () => {
    wake()
    resumeVisualizerAudio()
    player.toggle()
  }

  const chooseEffect = (next: Effect) => {
    wake()
    writeVizEffect(next)
    setEffect(next)
    setMenuOpen(false)
  }
  const chooseColours = (next: Colours) => {
    wake()
    writeVizColours(next)
    setColours(next)
  }
  const chooseAmbient = (next: AmbientChoice) => {
    wake()
    writeVizStyle(next)
    loop.current.gl?.choose(next)
    setChoice(next)
    closeMenu()
  }
  /** The style list closed, by a pick or Escape: focus back on its button, as a listbox's goes - the
   *  option that had it is about to go. */
  const closeMenu = () => {
    setMenuOpen(false)
    styleButton.current?.focus({ preventScroll: true })
  }

  //? Full screen, on its own element; refused (or not there), it is already a fixed layer over the
  //? window. Leaving full screen - the browser's Escape, its own controls - closes it. Focus goes in as
  //? it opens, and back to the player bar's button as it goes.
  useLayoutEffect(() => {
    const element = root.current
    if (!element) return
    element.focus({ preventScroll: true })
    const doc = document as Document & { webkitFullscreenElement?: Element | null; webkitExitFullscreen?: () => void }
    const showing = () => doc.fullscreenElement ?? doc.webkitFullscreenElement ?? null
    let entered = false
    const onChange = () => {
      if (showing() === element) entered = true
      else if (entered) closing.current()
    }
    doc.addEventListener('fullscreenchange', onChange)
    doc.addEventListener('webkitfullscreenchange', onChange)
    const box = element as HTMLElement & { webkitRequestFullscreen?: () => void }
    try {
      const asked = box.requestFullscreen ? box.requestFullscreen({ navigationUI: 'hide' }) : box.webkitRequestFullscreen?.()
      ;(asked as Promise<void> | undefined)?.catch?.(() => undefined)
    } catch {
      // refused: the fixed layer it already is
    }
    return () => {
      doc.removeEventListener('fullscreenchange', onChange)
      doc.removeEventListener('webkitfullscreenchange', onChange)
      const giveBack = () => opener.current?.focus({ preventScroll: true })
      if (showing() === element) {
        //? still full screen (Leave full screen, V..., Escape where the browser lets the page have it):
        //? Chromium keeps everything outside the full-screen element inert until it has left, so focus
        //? given back now goes nowhere - it goes back again once the browser has left
        const left = () => {
          doc.removeEventListener('fullscreenchange', left)
          doc.removeEventListener('webkitfullscreenchange', left)
          clearTimeout(giveUp)
          giveBack()
        }
        const giveUp = setTimeout(left, FULL_SCREEN_LEAVE_MS)
        doc.addEventListener('fullscreenchange', left)
        doc.addEventListener('webkitfullscreenchange', left)
        try {
          const leaving = doc.exitFullscreen ? doc.exitFullscreen() : doc.webkitExitFullscreen?.()
          ;(leaving as Promise<void> | undefined)?.catch?.(() => undefined)
        } catch {
          // already left
        }
      }
      giveBack()
    }
  }, [])

  //? The page behind doesn't scroll while it shows - a key the screen doesn't take (an arrow, Page
  //? Down) would move it unseen, and in the fixed layer its scrollbar would show at the edge
  useLayoutEffect(() => {
    const page = document.documentElement
    page.classList.add(SCROLL_LOCK)
    return () => page.classList.remove(SCROLL_LOCK)
  }, [])

  //? Focus never falls out of the screen: a control that goes while it has focus (the style list's
  //? option as the list closes, the Style button as Ambient goes or WebGL fails) leaves focus on the
  //? page's body, where the screen's keys - Space, V, Escape, Tab - would never reach it. After every
  //? render, focus outside the screen comes back to it.
  useLayoutEffect(() => {
    const element = root.current
    if (element && !element.contains(document.activeElement)) element.focus({ preventScroll: true })
  })

  //? The style list opens on the chosen style, as a listbox does
  useLayoutEffect(() => {
    if (!menuOpen) return
    styleList.current?.querySelector<HTMLElement>('[aria-selected="true"]')?.focus({ preventScroll: true })
  }, [menuOpen])

  //? the silent copy and its audio context go with the screen, and the pictures and WebGL with them
  useEffect(() => () => {
    listener.destroy()
    closeVisualizerAudio()
    loop.current.gl?.dispose()
    loop.current.gl = null
    letGo(loop.current.pictures)
  }, [])

  //? Reduced Motion, read as it changes
  useEffect(() => {
    const query = typeof matchMedia === 'function' ? matchMedia('(prefers-reduced-motion: reduce)') : null
    const read = () => {
      loop.current.calm = !!query?.matches
    }
    read()
    query?.addEventListener?.('change', read)
    return () => query?.removeEventListener?.('change', read)
  }, [])

  //? The controls fade after CHROME_IDLE_MS of stillness while playing - never while paused, pointed
  //? at, or with the style list open
  useEffect(() => {
    const timer = setInterval(() => {
      const now = latest.current
      if (!now.awake || !now.player.playing || overChrome.current || now.menuOpen) return
      if (performance.now() - lastActive.current > CHROME_IDLE_MS) setAwake(false)
    }, IDLE_CHECK_MS)
    return () => clearInterval(timer)
  }, [])

  //? The cover's colours and pictures, and the CD art, for the song playing - only the newest answer
  //? counts. Fetched as a picture's bytes and decoded off the page (createImageBitmap), so no image
  //? element is made for them. Each is asked for only when ITS address changes - the next song of the
  //? same album asks nothing - and the last one stays on screen until the next has come: an album's
  //? colours never flash to the purple, nor Halo's record to a plain one, between songs. CD art deadwax
  //? said it hasn't isn't asked for again this opening.
  const track = player.track
  const coverRequests = useMemo(latestOnly, [])
  const discRequests = useMemo(latestOnly, [])
  const noDiscArt = useRef(new Set<string>())
  const disc = track ? playingDisc(playedAlbum(track.albumId)?.song, track.id) : 1
  const coverAddress = track ? coverUrl(track.coverArt, 300) : null
  const discAddress = track ? discArtUrl(track.albumId, disc) : null
  useEffect(() => {
    const L = loop.current
    const request = coverRequests.begin()
    if (!coverAddress || typeof createImageBitmap !== 'function') {
      L.coverScheme = null
      L.pictures = swapPicture(L.pictures, 'cover', null)
      return
    }
    fetchPicture(coverAddress, request.signal).then(
      (cover) => {
        if (!request.current()) return letGoOf(cover)
        const cols = cover ? coverPalette(pixelsOf(cover)) : null
        L.pictures = swapPicture(L.pictures, 'cover', cover)
        L.coverScheme = cols ? scheme(cols, rolesFrom(cols)) : null
      },
      (reason: unknown) => {
        if (!request.current() || isAbort(reason)) return
        L.pictures = swapPicture(L.pictures, 'cover', null)
        L.coverScheme = null
      },
    )
    return () => coverRequests.supersede()
  }, [coverAddress])
  useEffect(() => {
    const L = loop.current
    const request = discRequests.begin()
    if (!discAddress || noDiscArt.current.has(discAddress) || typeof createImageBitmap !== 'function') {
      L.pictures = swapPicture(L.pictures, 'disc', null)
      return
    }
    fetchPicture(discAddress, request.signal).then(
      (art) => {
        if (!request.current()) return letGoOf(art)
        if (!art) noDiscArt.current.add(discAddress)
        L.pictures = swapPicture(L.pictures, 'disc', art)
      },
      (reason: unknown) => {
        if (!request.current() || isAbort(reason)) return
        L.pictures = swapPicture(L.pictures, 'disc', null)
      },
    )
    return () => discRequests.supersede()
  }, [discAddress])

  //? The frame loop: only while the page shows - hidden, it stops and the audio context is suspended;
  //? shown again, both carry on (a browser wanting a gesture to resume gets one from the next click or key)
  useEffect(() => {
    const L = loop.current
    const start = () => {
      if (L.raf) return
      L.last = performance.now()
      L.raf = requestAnimationFrame(frame)
    }
    const stop = () => {
      cancelAnimationFrame(L.raf)
      L.raf = 0
    }
    const onVisibility = () => {
      if (document.visibilityState === 'hidden') {
        stop()
        suspendVisualizerAudio()
      } else {
        resumeVisualizerAudio()
        start()
      }
    }
    const frame = (now: number) => {
      L.raf = requestAnimationFrame(frame)
      step(now)
    }
    if (document.visibilityState !== 'hidden') start()
    document.addEventListener('visibilitychange', onVisibility)
    return () => {
      document.removeEventListener('visibilitychange', onVisibility)
      stop()
    }
  }, [])

  /** One frame: the song followed, the signal read and shaped, the feel moved on, the effect drawn. */
  function step(now: number) {
    const L = loop.current
    const { player: p, effect: shown, colours: colourChoice, choice: style, glFailed: noGl } = latest.current
    const dt = Math.min(0.05, Math.max(0, (now - L.last) / 1000))
    L.last = now
    L.count += 1
    const playing = p.playing
    L.level = playing ? L.level + (1 - L.level) * (1 - Math.exp(-dt / 0.06)) : L.level * Math.exp(-dt / 0.4)
    const pace = L.calm ? CALM_PACE : 1
    L.vt += dt * pace * (0.2 + 0.8 * L.level)

    //? the silent copy kept in time with the element - and the next song's first window fetched ahead
    const song = p.track ? syncSong(p.track, p.duration || p.track.duration, p.maxRate) : null
    const after = nextIndex(p.queue)
    const following = after === null ? null : p.queue.tracks[after] ?? null
    listener.tick(song, following ? syncSong(following, following.duration, p.maxRate) : null, playing && !p.buffering, p.position())

    //? the signal: the copy's, the calm idle one for a song that can't be seen, or silence
    const heard = listener.read(L.raw, L.wave, L.level, dt)
    if (!heard) {
      if (seeingNow.current === 'unseen') {
        L.idleT += dt * pace
        idleSignal(L.idleT, L.raw, L.wave)
        for (let i = 0; i < L.raw.length; i++) L.raw[i] = L.raw[i]! * L.level
        for (let j = 0; j < L.wave.length; j++) L.wave[j] = L.wave[j]! * L.level
      } else {
        L.raw.fill(0)
        L.wave.fill(0)
      }
    }
    shapeSignal(L.shaped, L.raw, dt, L.calm)
    //? only the song itself is felt: silence holds the feel by itself, and the idle signal must too
    if (heard) musicFeel(L.feel, L.raw, L.wave, dt)
    if (L.count % 30 === 0) {
      const words = feelWords(L.feel)
      setFeelText((before) => (before === words ? before : words))
      const showing = L.gl?.showing() ?? null
      setNowStyle((before) => (before === showing ? before : showing))
    }

    const drawWith = colourChoice === 'cover' ? L.coverScheme ?? PURPLE_SCHEME : PURPLE_SCHEME
    const box = root.current
    const cssWidth = Math.max(1, box?.clientWidth ?? 1), cssHeight = Math.max(1, box?.clientHeight ?? 1)

    if (shown === 'ambient' && !noGl) {
      if (!L.gl && !L.glTried && glCanvas.current) {
        L.glTried = true
        const gl = new GlAmbient(glCanvas.current)
        if (gl.init()) {
          gl.choose(style)
          L.gl = gl
        } else {
          setGlFailed(true)
        }
      }
      L.gl?.draw({
        dt, vt: L.vt, position: p.position(), level: L.level, playing, calm: L.calm,
        tempo: L.calm ? Math.min(L.feel.tempo, 0.8) : L.feel.tempo, beats: L.feel.beats, aggr: L.feel.aggr,
        bass: L.shaped.bass, kick: L.shaped.kick, energy: L.shaped.energy, spec: L.shaped.spec, wave: L.wave,
        choice: style, palette: { floats: drawWith.floats, ring: drawWith.ring, roles: drawWith.roles },
      }, cssWidth, cssHeight)
      //? the 2D canvas is hidden meanwhile: cleared when it comes back
      L.drawn = ''
      return
    }

    const surface = canvas.current
    const ctx = surface?.getContext('2d')
    if (!surface || !ctx) return
    const scale = backingScale(cssWidth, cssHeight, typeof devicePixelRatio === 'number' ? devicePixelRatio : 1, MAX_2D_PIXELS)
    const width = Math.max(1, Math.round(cssWidth * scale)), height = Math.max(1, Math.round(cssHeight * scale))
    if (surface.width !== width || surface.height !== height) {
      surface.width = width
      surface.height = height
      L.drawn = ''
    }
    //? 900 units high, as wide as the screen's shape makes it (player/vizDraw.ts)
    const k = height / 900
    ctx.setTransform(k, 0, 0, k, 0, 0)
    ctx.globalCompositeOperation = 'source-over'
    ctx.globalAlpha = 1
    const units = (900 * cssWidth) / cssHeight
    if (L.drawn !== shown) {
      ctx.fillStyle = BACKGROUND
      ctx.fillRect(0, 0, units, 900)
      L.drawn = shown
    }
    const state: DrawState = {
      width: units, dt: dt * pace, vt: L.vt, level: L.level, spec: L.shaped.spec, peaks: L.shaped.peaks, wave: L.wave,
      bass: L.shaped.bass, kick: L.shaped.kick, lut: drawWith.lut, ring: drawWith.ring,
    }
    if (shown === 'bars') drawBars(ctx, state)
    else if (shown === 'scope') drawScope(ctx, state)
    else if (shown === 'ambient') drawAmbient2d(ctx, state)
    else drawHalo(ctx, state, L.halo, L.pictures)
    ctx.globalCompositeOperation = 'source-over'
    ctx.globalAlpha = 1
  }

  const onKeyDown = (event: KeyboardEvent) => {
    wake()
    const key = event.key
    if (key === 'Escape') {
      event.preventDefault()
      if (menuOpen) closeMenu()
      else onClose()
      return
    }
    if (key === ' ' || key === 'Spacebar' || event.code === 'Space') {
      event.preventDefault()
      //? one press, one toggle: a held key's repeats would play and pause it over and over
      if (event.repeat) return
      onToggle()
      return
    }
    if (menuOpen && moveInList(key)) {
      event.preventDefault()
      return
    }
    if ((key === 'v' || key === 'V') && !event.metaKey && !event.ctrlKey && !event.altKey) {
      event.preventDefault()
      chooseEffect(cycleEffect(latest.current.effect, event.shiftKey ? -1 : 1))
      return
    }
    if (key === 'Tab') keepFocusInside(event)
  }
  //? Space is taken on keydown; stopping it on keyup too keeps a focused button from also clicking
  const onKeyUp = (event: KeyboardEvent) => {
    if (event.key === ' ' || event.code === 'Space') event.preventDefault()
    resumeVisualizerAudio()
  }
  const onPointerMove = (event: PointerEvent) => {
    overChrome.current = !!(event.target as Element | null)?.closest?.('[data-chrome]')
    wake()
  }
  //? A press brings the faded controls back - a tap on a touch screen moves no pointer, so a move
  //? alone never would - and does only that: its click is swallowed (onClickCapture), so a tap where a
  //? hidden control was doesn't press it. A press anywhere outside the style list closes it.
  const onPointerDown = (event: PointerEvent) => {
    wokeByPress.current = latest.current.visible ? 0 : performance.now()
    wake()
    if (menuOpen && !(event.target as Element | null)?.closest?.('[data-menu]')) setMenuOpen(false)
  }
  const onClickCapture = (event: MouseEvent) => {
    const woke = wokeByPress.current
    wokeByPress.current = 0
    if (woke && performance.now() - woke < WAKE_CLICK_MS) {
      event.stopPropagation()
      event.preventDefault()
      resumeVisualizerAudio()
    }
  }

  /** The arrows, Home and End move through the open style list, as a listbox's do. */
  const moveInList = (key: string): boolean => {
    if (key !== 'ArrowDown' && key !== 'ArrowUp' && key !== 'Home' && key !== 'End') return false
    const options = [...(styleList.current?.querySelectorAll<HTMLElement>('[role="option"]') ?? [])]
    if (!options.length) return false
    const at = options.indexOf(document.activeElement as HTMLElement)
    const to = key === 'Home' ? 0 : key === 'End' ? options.length - 1
      : key === 'ArrowDown' ? Math.min(options.length - 1, at + 1) : Math.max(0, at < 0 ? options.length - 1 : at - 1)
    options[to]?.focus({ preventScroll: true })
    return true
  }

  /** Tab and Shift+Tab go round the screen's own controls, never out to the page behind. */
  const keepFocusInside = (event: KeyboardEvent) => {
    const box = root.current
    if (!box) return
    const stops = [box, ...box.querySelectorAll<HTMLElement>('button:not([disabled])')]
    const at = stops.indexOf(document.activeElement as HTMLElement)
    const next = event.shiftKey ? (at <= 0 ? stops.length - 1 : at - 1) : (at < 0 || at >= stops.length - 1 ? 0 : at + 1)
    event.preventDefault()
    stops[next]?.focus()
  }

  const ambient = effect === 'ambient'
  const glOn = ambient && !glFailed
  const byline = track ? [track.artist, track.album] : []

  return (
    <div
      ref={root}
      class={`app-viz${visible ? '' : ' is-still'}`}
      tabIndex={0}
      role="application"
      aria-label="Full-screen visualizer"
      onKeyDown={onKeyDown}
      onKeyUp={onKeyUp}
      onPointerMove={onPointerMove}
      onPointerDown={onPointerDown}
      onPointerLeave={() => {
        overChrome.current = false
      }}
      onClickCapture={onClickCapture}
      onClick={() => resumeVisualizerAudio()}
      onWheel={(event) => event.preventDefault()}
    >
      <canvas ref={canvas} class="app-viz-canvas" role="img" aria-label={`Visualizer, ${EFFECT_NAMES[effect]} effect`} hidden={glOn} />
      <canvas ref={glCanvas} class="app-viz-canvas is-gl" role="img" aria-label={`Visualizer, ${EFFECT_NAMES[effect]} effect`} hidden={!glOn} />
      <div class="app-viz-chrome">
        <div class="app-viz-scrim is-top" />
        <div class="app-viz-scrim is-bottom" />

        {/* the song at the left, the choices at the right: one row while there is room, the choices
            wrapping under one another at a narrow desktop */}
        <div class="app-viz-top">
          <div class="app-viz-song" data-chrome="1">
            <Cover id={track?.coverArt} size={112} class="app-viz-cover" />
            <div class="app-viz-song-text">
              <span class="app-viz-title">{track ? track.title : 'Nothing playing'}</span>
              {byline[0] ? <span class="app-viz-artist">{byline[0]}</span> : null}
              {byline[1] ? <span class="app-viz-album">{byline[1]}</span> : null}
            </div>
          </div>

          <div class="app-viz-tools" data-chrome="1">
            <div class="app-viz-segmented" role="group" aria-label="Effect">
              {EFFECTS.map((id) => (
                <button type="button" key={id} class={`app-viz-segment${id === effect ? ' is-on' : ''}`} aria-pressed={id === effect} onClick={() => chooseEffect(id)}>
                  {EFFECT_NAMES[id]}
                </button>
              ))}
            </div>

            {glOn && (
              <div class="app-viz-menu" data-menu="1">
                <button ref={styleButton} type="button" class="app-viz-button" aria-haspopup="listbox" aria-expanded={menuOpen} onClick={() => {
                  wake()
                  setMenuOpen((was) => !was)
                }}>
                  <span class="app-viz-button-label">Style:</span>
                  <b class="app-viz-button-value">{STYLE_NAMES[choice]}</b>
                  <ChevronDownIcon class="app-viz-chevron" />
                </button>
                {!menuOpen && feelText ? (
                  <div class="app-viz-readout">
                    {choice === 'rotate' && nowStyle ? <span>now: {STYLE_NAMES[nowStyle]}</span> : null}
                    <span>feel: {feelText}</span>
                  </div>
                ) : null}
                {menuOpen ? (
                  <div ref={styleList} class="app-viz-list" role="listbox" aria-label="Ambient style">
                    {STYLE_ROWS.map((row) => row.kind === 'heading' ? (
                      <div key={row.label} class="app-viz-list-heading">{row.label}</div>
                    ) : (
                      <button
                        type="button"
                        key={row.id}
                        role="option"
                        aria-selected={row.id === choice}
                        class={`app-viz-option${row.id === choice ? ' is-on' : ''}`}
                        onClick={() => chooseAmbient(row.id)}
                      >
                        <span class="app-viz-tick">{row.id === choice ? <CheckIcon class="app-viz-tick-icon" /> : null}</span>
                        <span>{STYLE_NAMES[row.id]}</span>
                      </button>
                    ))}
                  </div>
                ) : null}
              </div>
            )}

            <div class="app-viz-colours">
              <span class="app-viz-label">Colour</span>
              <div class="app-viz-segmented" role="group" aria-label="Colour">
                <button type="button" class={`app-viz-segment${colours === 'cover' ? ' is-on' : ''}`} aria-pressed={colours === 'cover'} onClick={() => chooseColours('cover')}>
                  From the cover
                </button>
                <button type="button" class={`app-viz-segment${colours === 'purple' ? ' is-on' : ''}`} aria-pressed={colours === 'purple'} onClick={() => chooseColours('purple')}>
                  Purple
                </button>
              </div>
            </div>

            <button type="button" class="app-viz-button is-leave" onClick={onClose}>
              <LeaveFullScreenIcon class="app-viz-leave-icon" />
              Leave full screen
            </button>
          </div>
        </div>

        <div class="app-viz-transport" data-chrome="1">
          <button type="button" class="app-viz-play" onClick={onToggle} aria-label={player.playing ? 'Pause' : 'Play'} aria-keyshortcuts="Space">
            {player.playing ? <PauseIcon class="app-viz-play-icon" /> : <PlayIcon class="app-viz-play-icon" />}
          </button>
        </div>

        <p class="app-viz-hint">Space play/pause · V next effect · Esc leave</p>
        <div class="app-viz-notes">
          {seeing.seeing === 'unseen' && seeing.why ? <p class="app-viz-note">{seeing.why}</p> : null}
          {ambient && glFailed ? <p class="app-viz-note">WebGL isn't available here, so Ambient is showing the simple version.</p> : null}
        </div>
      </div>
    </div>
  )
}

/** What the silent copy needs to know of a song: its id and length, whether it is a FLAC, and the
 *  cap the player asks for it at (so the window is cut from the very copy it plays). */
function syncSong(track: QueueTrack, length: number, maxRate: MaxRate): SyncSong {
  return { id: track.id, length: length || 0, flac: isFlac(track), maxRate: resamples(track, maxRate, 'raw') ? 48000 : null }
}

/** A picture fetched and decoded; null when there is none (a 404 - for CD art, deadwax has none). */
async function fetchPicture(address: string, signal: AbortSignal | undefined): Promise<ImageBitmap | null> {
  const response = await fetch(address, signal ? { signal } : undefined)
  if (!response.ok) return null
  return createImageBitmap(await response.blob())
}

/** One of the song's pictures swapped for the next, the one it replaces let go of. */
function swapPicture(pictures: DiscPictures, which: keyof DiscPictures, next: ImageBitmap | null): DiscPictures {
  if (pictures[which] === next) return pictures
  letGoOf(pictures[which])
  return { ...pictures, [which]: next }
}

/** A decoded picture holds its memory until closed. */
function letGoOf(picture: CanvasImageSource | null): void {
  if (picture && typeof (picture as ImageBitmap).close === 'function') (picture as ImageBitmap).close()
}

/** The song's pictures let go of as the screen goes. */
function letGo(pictures: DiscPictures): void {
  letGoOf(pictures.cover)
  letGoOf(pictures.disc)
}

/** A picture's pixels, drawn small - enough to find its colours in. */
function pixelsOf(picture: ImageBitmap): Uint8ClampedArray {
  const side = 40
  const surface = document.createElement('canvas')
  surface.width = side
  surface.height = side
  const ctx = surface.getContext('2d')
  if (!ctx) return new Uint8ClampedArray(0)
  ctx.drawImage(picture, 0, 0, side, side)
  return ctx.getImageData(0, 0, side, side).data
}
