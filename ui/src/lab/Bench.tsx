import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'preact/hooks'

import { turntableRow, turntableTimingRow, type DebugRow } from '../lib/debugRows'
import type { DeckReport } from '../lib/deckVoice'
import { latestOnly } from '../lib/latest'
import { clock } from '../lib/scrub'
import {
  WINDOW_S, deckRecorded, deckRecordingData, deckReport, deckSoundAnalyser, onDeckRecorded, onDeckReport, recordDeckSound,
  releaseDeckSoundAnalyser, stopDeckRecording, wakeDeckAudio, type Deck, type DeckRecorded, type DeckRecordingData,
} from '../player/deck'
import { Turntable, TurntableTime, type TurntablePreview, type WindowSource } from '../player/Turntable'
import { exactKnots, guessingChance, heat, type ExactMotion, type RecordedMessage, type SpectrogramImage } from './analysis'
import { useBenchPlayer, type BenchPlayer, type BenchSong } from './benchPlayer'
import { blocksLine, checkFile, checkLine, checkRuns, framesLine, runCounts, type CheckRun, type CheckState } from './check'
import { compare, replayHeld, tookTheRecord, type Comparison } from './compare'
import { decodeAt } from './decode'
import { ListeningRoom } from './listen'
import { MOTIONS, motionNeeds, motionStart, type Motion, type MotionId } from './motions'
import { NOT_HELD, NOT_TAKEN, STARTING, againLine, dbText, meaning, numberRows, percent, transportLine } from './reading'
import { runMotion, type MotionResult, type MotionRun } from './runner'
import { SIGNALS, SOURCE_RATES, makeSignal, seeded, signalWindow, wavBytes, type Signal, type SignalId, type SourceRate } from './signals'
import { watchForHide, type HideWatch } from './watch'

/** What a check stopped by you was stopped with. */
const STOPPED = 'stopped'

/** A recording the Record button makes, seconds. */
export const RECORD_SECONDS = 10
/** After a motion lets go, the recording runs on this long for the coast, ms. */
export const MOTION_TAIL_MS = 1600
/** What "Check this device" runs: each motion on each signal. */
export const CHECK_SIGNALS: readonly SignalId[] = ['sine1k', 'sine440']
export const CHECK_MOTIONS: readonly MotionId[] = ['steady1', 'half', 'double', 'back1', 'wobble']

type Clip = 'A' | 'B' | 'C'
const CLIPS: readonly Clip[] = ['A', 'B', 'C']
const CLIP_NAMES: Record<Clip, string> = { A: 'A - deadwax', B: "B - ideal, deadwax's path", C: 'C - ideal, smooth path' }
const CLIP_NOTES: Record<Clip, string> = {
  A: 'What the voice played.',
  B: "The signal read exactly along deadwax's own read head: B against A is how the voice reads the song.",
  C: 'The signal read exactly along a smooth path through your movement: C against A is everything deadwax\'s real-time path adds.',
}

const message = (error: unknown) => (error instanceof Error ? error.message : String(error))
const sleep = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms))
const breathe = () => new Promise<void>((resolve) => setTimeout(resolve, 0))
const DEG = 180 / Math.PI

/** Waits until `ready` says so, looking every 100 ms, `ms` at most. */
async function until(ready: () => boolean, ms: number): Promise<boolean> {
  const end = performance.now() + ms
  while (!ready()) {
    if (performance.now() > end) return false
    await sleep(100)
  }
  return true
}

let songs = 0

/** What the bench made: the signal, and the song its <audio> plays. */
interface Made {
  signal: Signal
  song: BenchSong
}

/** What a recording was of: the song, the window the voice had as it began, the motion if one ran - and
 *  whether the page was hidden while it recorded (then it is thrown away, not measured). */
interface Recorded {
  label: string
  made: Made
  windowAtStart: DeckReport['window']
  motion: { def: Motion; result: MotionResult } | null
  watch: HideWatch | null
}

/** A motion run: what it did, what was recorded, the window it began with - and whether a hide cut it short. */
interface MotionDone {
  result: MotionResult
  data: DeckRecordingData | null
  windowAtStart: DeckReport['window']
  interrupted: boolean
}

/** A comparison worked out, and what it was of. */
interface Compared {
  label: string
  signal: Signal
  result: Comparison
}

/** A recording set beside the ideal turntables: its windows decoded again, the replay and the rest. */
async function compareRecording(data: DeckRecordingData, what: Recorded, pictures: boolean): Promise<Comparison> {
  const signal = what.made.signal
  //? every window the voice had over the recording - the one as it began, and any sent since - decoded
  //? again from the bench's own bytes at the deck's rate, by the same decoder
  const shapes = new Map<string, { start: number; rate: number; length: number }>()
  const key = (start: number, rate: number, length: number) => `${start.toFixed(9)}/${rate}/${length}`
  const start = what.windowAtStart
  if (start) shapes.set(key(start.start, start.decodedAt, Math.round((start.end - start.start) * start.decodedAt)), { start: start.start, rate: start.decodedAt, length: Math.round((start.end - start.start) * start.decodedAt) })
  for (const m of data.messages) {
    if (m.type !== 'window') continue
    const shape = { start: m.start as number, rate: m.rate as number, length: m.length as number }
    shapes.set(key(shape.start, shape.rate, shape.length), shape)
  }
  const decoded = new Map<string, Float32Array[]>()
  for (const [name, shape] of shapes) {
    try {
      const channels = await decodeAt(signalWindow(signal, shape.start, WINDOW_S).bytes, data.sampleRate)
      decoded.set(name, channels)
    } catch {
      //? a window that won't decode here: the replay goes on without it (and says so in its numbers)
    }
  }
  const windowFor = (s: number, rate: number, length: number) => decoded.get(key(s, rate, length)) ?? null
  const windowAtStart = start ? (() => {
    const length = Math.round((start.end - start.start) * start.decodedAt)
    const channels = windowFor(start.start, start.decodedAt, length)
    return channels ? { channels, start: start.start, rate: start.decodedAt } : null
  })() : null
  //? a motion's exact path for C: its knots at the times the deck stamped its samples
  const result = what.motion?.result
  const exact: ExactMotion | null = what.motion && result
    ? exactKnots(data.messages as RecordedMessage[], result.samples, result.from, result.anchor, what.made.song.seconds, what.motion.def.path, what.motion.def.speed)
    : null
  const knots = exact?.knots
  return compare({
    recording: data, exact: signal.exact, measure: signal.tonal ? 'tonal' : signal.id === 'silence' ? 'silence' : 'none',
    windowAtStart, windowFor, motion: exact, span: knots ? { from: knots[0]!.time, to: knots[knots.length - 1]!.time } : null, pictures, pause: breathe,
  })
}

/** What a recording the page was hidden through says: thrown away, not measured. */
const HIDDEN_RECORDING = 'The page was hidden while it recorded - the record\'s sound stops with it - so the recording was thrown away. Keep the page in view, and record again.'
/** What a run of the check the page was hidden through says, waiting for a tap to carry on. */
const HIDDEN_CHECK = 'The page was hidden, so that run was thrown away - the record\'s sound stops with it. Keep the page in view and the screen awake, and tap Carry on to run it again.'

function Rows({ rows }: { rows: DebugRow[] }) {
  return (
    <dl class="app-group app-kv">
      {rows.map((row) => (
        <div key={row.label} class="app-kv-row">
          <dt class="app-kv-label">{row.label}</dt>
          <dd class={`app-kv-value${row.mono ? ' app-mono' : ''}`}>{row.value}</dd>
          {row.note && <dd class="app-kv-note">{row.note}</dd>}
        </div>
      ))}
    </dl>
  )
}

function Spectrogram({ image, label }: { image: SpectrogramImage; label: string }) {
  const canvas = useRef<HTMLCanvasElement>(null)
  useEffect(() => {
    const context = canvas.current?.getContext('2d')
    if (!context) return
    context.putImageData(new ImageData(image.data, image.width, image.height), 0, 0)
  }, [image])
  return (
    <figure class="lab-figure">
      <canvas ref={canvas} class="lab-canvas" width={image.width} height={image.height} role="img" aria-label={`Spectrogram of ${label}: time across, frequency up, 20 Hz to 20 kHz`} />
      <figcaption class="lab-caption">{label}</figcaption>
    </figure>
  )
}

/** Which voice plays the record's sound, in a line. */
function voiceLine(report: DeckReport | null): string {
  return report?.voice === 'worklet'
    ? 'The record\'s sound: on its own audio thread (an AudioWorklet).'
    : report?.voice === 'script' ? `The record's sound: on the main thread - ${report.voiceWhy ?? "this page isn't on HTTPS"}.` : 'The record\'s sound: not started - press Start the sound (or Play).'
}

/** Debug's two turntable rows, and which voice runs. */
function Voice({ report }: { report: DeckReport | null }) {
  return <Rows rows={[{ label: 'The voice', value: voiceLine(report) }, turntableRow(report), turntableTimingRow(report)]} />
}

/**
 * THE LIVE SPECTROGRAM: a scrolling picture of the record's sound - an AnalyserNode on the voice's own
 * node in the deck's own context (deckSoundAnalyser), never the song's element - log frequency, 20 Hz to
 * 20 kHz. It moves only while something sounds, and stops while the page is hidden.
 */
function LiveSpectrum() {
  const canvas = useRef<HTMLCanvasElement>(null)
  const [moving, setMoving] = useState(false)
  useEffect(() => {
    let raf = 0
    let poll: ReturnType<typeof setTimeout> | undefined
    let quiet = 0
    let data: Float32Array<ArrayBuffer> | null = null
    let column: ImageData | null = null
    const stop = () => {
      cancelAnimationFrame(raf)
      raf = 0
      clearTimeout(poll)
      poll = undefined
    }
    //? whether the record sounds, looked at four times a second while it doesn't
    const look = () => {
      poll = undefined
      if (document.visibilityState === 'hidden') return
      const analyser = deckSoundAnalyser()
      if (analyser) {
        data = data && data.length === analyser.frequencyBinCount ? data : new Float32Array(analyser.frequencyBinCount)
        analyser.getFloatFrequencyData(data)
        let loudest = -Infinity
        for (const value of data) if (value > loudest) loudest = value
        if (loudest > -140) {
          quiet = 0
          setMoving(true)
          raf = requestAnimationFrame(draw)
          return
        }
      }
      poll = setTimeout(look, 250)
    }
    const draw = () => {
      raf = 0
      const analyser = deckSoundAnalyser()
      const target = canvas.current
      const context = target?.getContext('2d')
      if (!analyser || !target || !context || document.visibilityState === 'hidden') {
        setMoving(false)
        look()
        return
      }
      data = data && data.length === analyser.frequencyBinCount ? data : new Float32Array(analyser.frequencyBinCount)
      analyser.getFloatFrequencyData(data)
      const { width, height } = target
      column = column && column.height === height ? column : context.createImageData(1, height)
      const rate = analyser.context.sampleRate
      const binHz = rate / analyser.fftSize
      const top = Math.min(20000, rate / 2)
      let loudest = -Infinity
      for (let y = 0; y < height; y++) {
        const hz = 20 * Math.pow(top / 20, (height - 1 - y) / (height - 1))
        const bin = Math.min(data.length - 1, Math.max(1, Math.round(hz / binHz)))
        const db = data[bin]!
        if (db > loudest) loudest = db
        const [r, g, b] = heat((db + 140) / 120)
        column.data[y * 4] = r
        column.data[y * 4 + 1] = g
        column.data[y * 4 + 2] = b
        column.data[y * 4 + 3] = 255
      }
      context.drawImage(target, -1, 0)
      context.putImageData(column, width - 1, 0)
      quiet = loudest > -140 ? 0 : quiet + 1
      if (quiet > 30) {
        //? nothing sounding for half a second: it stops, and looks now and then
        setMoving(false)
        look()
        return
      }
      raf = requestAnimationFrame(draw)
    }
    const onVisible = () => {
      stop()
      if (document.visibilityState === 'hidden') {
        releaseDeckSoundAnalyser()
        setMoving(false)
      } else look()
    }
    document.addEventListener('visibilitychange', onVisible)
    look()
    return () => {
      document.removeEventListener('visibilitychange', onVisible)
      stop()
      releaseDeckSoundAnalyser()
    }
  }, [])
  return (
    <figure class="lab-figure">
      <canvas ref={canvas} class="lab-canvas lab-live" width={720} height={180} role="img" aria-label="The record's sound as it plays: time across, frequency up, 20 Hz to 20 kHz" />
      <figcaption class="lab-caption">{moving ? 'Moving: the record is sounding' : 'Still: it moves while the record sounds'}</figcaption>
    </figure>
  )
}

/**
 * THE TEST BENCH for the turntable (2.0.0-player.36), at /player/lab/. James, after seven fixes and three
 * blind renders: "maybe my expectations are skewed, so a test suite may be in order ... I want to be able
 * to use the turntable on a few different samples". The REAL turntable - Turntable.tsx, its deck and its
 * voice, exactly the app's - over simple signals the page makes (lab/signals.ts), with its own player and
 * its own windows; turned by a hand, or for one at perfect speeds (lab/motions.ts, lab/runner.ts);
 * recorded, and set beside an ideal turntable turned the same way (lab/compare.ts) - to listen to, blind if
 * he likes, and to measure; and a check of the device that gives a file to send.
 */
export function Bench() {
  const [signalId, setSignalId] = useState<SignalId>('sine440')
  const [rate, setRate] = useState<SourceRate>(44100)
  const [picked, setPicked] = useState<{ name: string; bytes: ArrayBuffer } | null>(null)
  const [made, setMade] = useState<Made | null>(null)
  const [making, setMaking] = useState<string | null>('Making the song…')
  const builds = useMemo(latestOnly, [])
  const madeRef = useRef(made)
  madeRef.current = made

  const player = useBenchPlayer(made?.song ?? null)
  const playerRef = useRef<BenchPlayer>(player)
  playerRef.current = player
  const deckRef = useRef<Deck | null>(null)
  const [previewing, setPreviewing] = useState<TurntablePreview>(null)
  const [windDown, setWindDown] = useState(true)
  const [report, setReport] = useState<DeckReport | null>(deckReport())
  const [status, setStatus] = useState('')
  const deckBox = useRef<HTMLDivElement>(null)

  const [jitter, setJitter] = useState(false)
  const [armed, setArmed] = useState(false)
  const [running, setRunning] = useState<{ id: MotionId; run: MotionRun } | null>(null)
  //? a motion from its tap until it has done - its making ready included (a seek, waiting for the record
  //? to sound), before `running` says it turns: the ref for the tap that comes before the render
  const [preparing, setPreparing] = useState(false)
  const motionGoing = useRef(false)

  const [recorded, setRecordedState] = useState<DeckRecorded | null>(deckRecorded())
  //? a Record waiting for the sound to start before it records
  const [startingRecord, setStartingRecord] = useState(false)
  const pending = useRef<Recorded | null>(null)
  const checking = useRef(false)
  const [compared, setCompared] = useState<Compared | null>(null)
  const [comparing, setComparing] = useState<string | null>(null)

  const room = useMemo(() => new ListeningRoom(), [])
  const [, setRoomTick] = useState(0)
  const [mode, setMode] = useState<'compare' | 'abx'>('compare')
  const [pair, setPair] = useState<[Clip, Clip]>(['A', 'C'])
  const [trials, setTrials] = useState(10)
  const [abx, setAbx] = useState<{ pair: [Clip, Clip]; trials: number; x: 0 | 1; answers: boolean[]; guessed: 0 | 1 | null } | null>(null)

  const [check, setCheck] = useState<CheckState | null>(null)
  const checkStop = useRef(false)
  //? a check waiting for a tap to carry on after the page was hidden: how it goes on, or stops
  const carryOn = useRef<{ go: () => void; stop: (error: Error) => void } | null>(null)

  //? where focus goes once what had it has gone (a control the bench takes away, or a comparison landing):
  //? a control's `data-focus` name - and, `force`d, even from a control still there
  const focusNext = useRef<{ name: string; force: boolean } | null>(null)

  /* ----- the song ----- */

  useEffect(() => {
    const ticket = builds.begin()
    if (signalId === 'file' && !picked) {
      setMaking('Choose a file below to make it the song')
      return
    }
    setMaking('Making the song…')
    void (async () => {
      try {
        const file = signalId === 'file' && picked ? { name: picked.name, channels: await decodeAt(picked.bytes.slice(0), rate) } : null
        if (!ticket.current()) return
        const signal = await makeSignal(signalId, rate, { file, pause: breathe })
        if (!ticket.current()) return
        songs += 1
        const url = URL.createObjectURL(new Blob([wavBytes(signal.channels, signal.rate)], { type: 'audio/wav' }))
        setMade({ signal, song: { id: `lab-${signalId}-${rate}-${songs}`, title: signal.name, seconds: signal.length / signal.rate, rate, channels: signal.channels.length, url } })
        setMaking(null)
      } catch (error) {
        if (ticket.current()) setMaking(`That couldn't be made into a song - ${message(error)}`)
      }
    })()
  }, [signalId, rate, picked])

  //? a song's address let go of once its player has moved on to the next
  useEffect(() => {
    const url = made?.song.url
    return () => {
      if (url) setTimeout(() => URL.revokeObjectURL(url), 2000)
    }
  }, [made])

  //? the deck's windows, the bench's own: exactly the song's samples, as a WAV it decodes
  const windowSource = useCallback<WindowSource>((song, from, seconds) => new Promise((resolve, reject) => {
    const now = madeRef.current
    if (!now || now.song.id !== song.id) {
      reject(new Error('another song'))
      return
    }
    resolve(signalWindow(now.signal, from, seconds))
  }), [])

  useEffect(() => onDeckReport(setReport), [])
  useEffect(() => () => room.close(), [])
  useEffect(() => room.onChange(() => setRoomTick((n) => n + 1)), [])

  //? the transport's line kept to what is so: Ready once the sound runs - after it was starting, or a hidden
  //? page had stopped it (the deck suspends its sound; a tap brings it back) - and said so when a hidden page
  //? stopped it (reading.ts)
  const soundWas = useRef<DeckReport['context'] | null>(null)
  useEffect(() => {
    const now = report?.context ?? null
    const was = soundWas.current
    soundWas.current = now
    const hidden = document.visibilityState === 'hidden'
    setStatus((line) => transportLine(line, was, now, hidden))
  }, [report?.context])

  /* ----- recordings ----- */

  const analyse = async (data: DeckRecordingData | null, what: Recorded) => {
    if (!data) {
      setComparing('The recording was lost')
      return
    }
    //? nothing took the record while it recorded (Record pressed and the record not turned, or a turn
    //? already under way): nothing to set beside an ideal turntable - said so, never taken for a stall
    if (!tookTheRecord(data.messages)) {
      setComparing(NOT_TAKEN)
      return
    }
    setComparing('Working it out: replaying the voice, reading the ideal turntables…')
    await breathe()
    try {
      const result = await compareRecording(data, what, true)
      setCompared({ label: what.label, signal: what.made.signal, result })
      setAbx(null)
      setMode('compare')
      room.load([result.clips.A, result.clips.B, result.clips.C], result.rate, 0)
      setComparing(null)
      //? the comparison takes the focus as it lands - its Play - so Space plays it, wherever the tap that
      //? recorded it left the focus (a field being typed in is left alone)
      focusNext.current = { name: 'compare-play', force: true }
    } catch (error) {
      setComparing(`It couldn't be worked out - ${message(error)}`)
    }
  }
  const saved = useRef(() => {})
  saved.current = () => {
    const what = pending.current
    if (!what || checking.current) return
    pending.current = null
    what.watch?.stop()
    if (what.watch?.hidden) {
      setComparing(HIDDEN_RECORDING)
      return
    }
    //? the song is held still while it records (its controls locked) - but should it have changed, the
    //? recording is of two songs, and nothing to measure against one
    if (madeRef.current?.song.id !== what.made.song.id) {
      setComparing('The song changed while it recorded, so the recording was thrown away - record again')
      return
    }
    void analyse(deckRecordingData(), what)
  }
  useEffect(() => onDeckRecorded((state) => {
    setRecordedState(state)
    if (state?.state === 'saved') saved.current()
  }), [])

  /* ----- what the buttons do: the deck's sound only ever from one of them ----- */

  const onStart = () => {
    wakeDeckAudio()
    setStatus(STARTING)
  }

  const onPlay = () => {
    //? not under a motion or the check: played under the hand, the song and the record's sound would be
    //? heard together, and the release seek the playing song on over the coast and leave the record still
    //? beside it (review of 2.0.0-player.36)
    if (!madeRef.current || busy) return
    wakeDeckAudio()
    const deck = deckRef.current
    if (player.playing) {
      //? as Now Playing's pause on the turntable: winding down when the deck can, the song sought there
      const landing = deck?.pausing() ?? null
      player.toggle()
      if (landing !== null) player.seek(landing)
      return
    }
    const from = deck?.resuming() ?? null
    if (from !== null) player.seek(from)
    player.toggle()
  }

  const onRecord = () => {
    if (!madeRef.current || busy || recording) return
    //? in the tap: the deck's sound may need making, or waking - which only a tap may do - and then the
    //? recording waits for it to run (it records nothing till then: the first tap on a cold page used to
    //? say "the sound has not started" though that very tap had started it)
    wakeDeckAudio()
    void startRecording()
  }

  const startRecording = async () => {
    const made = madeRef.current
    if (!made) return
    setStartingRecord(true)
    try {
      if (deckReport()?.context !== 'running') {
        setComparing('Starting the sound…')
        if (!(await until(() => deckReport()?.context === 'running', 6000))) {
          setComparing("The record's sound didn't start - press Start the sound, wait for Ready, and record again")
          return
        }
      }
      if (madeRef.current !== made) {
        setComparing(null)
        return
      }
      const windowAtStart = deckReport()?.window ?? null
      const problem = recordDeckSound(RECORD_SECONDS, true)
      if (problem) {
        setComparing(`It couldn't record - ${problem}`)
        return
      }
      //? a hide stops the recording, and saved.current throws it away
      const watch = watchForHide(() => stopDeckRecording())
      pending.current = { label: `${RECORD_SECONDS} s of your turning, on ${made.signal.name}`, made, windowAtStart, motion: null, watch }
      setComparing(`Recording ${RECORD_SECONDS} s - turn the record`)
    } finally {
      setStartingRecord(false)
    }
  }

  //? the record's face under a motion: the deck holds it still under a hand, and Turntable turns it there -
  //? but only for a hand of its own. So the motions' turn is kept where nothing of Turntable's writes: a
  //? property on the bench's own box, which lab.css turns the record by (the individual `rotate`, added to
  //? the transform Turntable writes on the same element). Written into that transform, it was undone by
  //? the next hand's turn - the record jumping back by the motion's whole turn (review of 2.0.0-player.36)
  const motionTurn = useRef(0)
  const turnFace = () => {
    const from = motionTurn.current
    return (turned: number) => {
      motionTurn.current = (from + turned * DEG) % 360
      deckBox.current?.style.setProperty('--lab-motion-turn', `${motionTurn.current.toFixed(2)}deg`)
    }
  }

  /**
   * A motion run on the deck - recorded when `record` - once the record can sound where it is. A hide
   * stops it there (and its recording): what came of it is `interrupted`, and nothing to measure.
   */
  const motion = async (id: MotionId, record: boolean, random: (() => number) | null): Promise<MotionDone | null> => {
    const deck = deckRef.current
    const def = MOTIONS.find((one) => one.id === id)!
    const now = madeRef.current
    if (!deck || !now) return null
    //? room in the song for it, either way - or none, for a file too short for it
    const at = playerRef.current.position()
    const start = motionStart(def, now.song.seconds, at)
    if (start === null) {
      setStatus(`This song is too short for ${def.label} - it needs ${Math.ceil(motionNeeds(def))} s, and it is ${Math.floor(now.song.seconds)} s`)
      return null
    }
    let run: MotionRun | null = null
    let recordingIt = false
    //? from here a hide stops it - the run, and its recording
    const watch = watchForHide(() => {
      run?.stop()
      if (recordingIt) stopDeckRecording()
    })
    try {
      if (start !== at) {
        playerRef.current.seek(start)
        await sleep(250)
      }
      setStatus('Waiting for the record\'s sound…')
      //? a paused record sought where its window doesn't reach has no window there until it is pressed: a
      //? press for a moment, as a finger's that can't be the deck's (Turntable's holdStill), asks for it
      if (!(await until(() => deck.live(), 1000))) {
        deck.holdStill(true)
        deck.holdStill(false)
      }
      if (!(await until(() => deck.live(), 8000))) {
        //? hidden meanwhile, the sound suspended with the page: that is why
        if (watch.hidden) return null
        setStatus("The record's sound hasn't started - press Start the sound, wait for Ready, and try again")
        return null
      }
      const windowAtStart = deckReport()?.window ?? null
      if (record) {
        const problem = recordDeckSound(def.seconds + MOTION_TAIL_MS / 1000 + 2, true)
        if (problem) {
          setStatus(`It couldn't record - ${problem}`)
          return null
        }
        recordingIt = true
        if (!checking.current) pending.current = { label: `${def.label}${random ? ', with a finger\'s jitter' : ''}, on ${now.signal.name}`, made: now, windowAtStart, motion: null, watch }
      }
      //? the player as it is when asked - at the release too, after the take paused it (a new object each time)
      run = runMotion(deck, () => playerRef.current, def, { random, onTurn: turnFace() })
      if (watch.hidden) run.stop()
      setRunning({ id, run })
      setStatus(`Turning it: ${def.label}`)
      const result = await run.done
      setRunning(null)
      if (watch.hidden) {
        setStatus('Stopped - the page was hidden')
        return { result, data: null, windowAtStart, interrupted: true }
      }
      setStatus(result.stopped ? 'Stopped' : `Turned: ${def.label}`)
      if (!record) return { result, data: null, windowAtStart, interrupted: false }
      if (pending.current) pending.current = { ...pending.current, motion: { def, result } }
      await sleep(MOTION_TAIL_MS)
      stopDeckRecording()
      return { result, data: watch.hidden ? null : deckRecordingData(), windowAtStart, interrupted: watch.hidden }
    } finally {
      watch.stop()
    }
  }

  const onMotion = (id: MotionId) => {
    if (busy || !made || motionGoing.current) return
    motionGoing.current = true
    setPreparing(true)
    wakeDeckAudio()
    const record = armed
    setArmed(false)
    if (record) setComparing('Recording the motion')
    void motion(id, record, jitter ? seeded(Math.floor(Math.random() * 2 ** 31)) : null).then((done) => {
      //? a motion that couldn't run (a song too short, the sound not starting) recorded nothing
      if (record && !done) setComparing(null)
    }).finally(() => {
      motionGoing.current = false
      setPreparing(false)
    })
  }

  const onStopMotion = () => running?.run.stop()

  const onListen = () => {
    room.toggle()
  }

  /* ----- "Check this device" ----- */

  const onCheck = () => {
    if (locked) return
    wakeDeckAudio()
    void runCheck()
  }

  //? after a hide: the tap that carries on brings the sound back (only a tap may)
  const onCarryOn = () => {
    const waiting = carryOn.current
    if (!waiting) return
    wakeDeckAudio()
    carryOn.current = null
    waiting.go()
  }

  const onStopCheck = () => {
    if (!check?.running) return
    checkStop.current = true
    running?.run.stop()
    const waiting = carryOn.current
    carryOn.current = null
    waiting?.stop(new Error(STOPPED))
  }

  const runCheck = async () => {
    checking.current = true
    checkStop.current = false
    const runs: CheckRun[] = []
    const of = checkRuns(CHECK_SIGNALS.length, CHECK_MOTIONS.length)
    const state = (step: string, more: Partial<CheckState> = {}): CheckState => ({ running: true, step, runs: [...runs], error: null, stoppedByYou: false, waiting: false, href: null, of, ...more })
    setCheck(state('Starting the sound…'))
    //? the file: of every run done, whole or not
    const save = async (stop: { complete: boolean; why: string | null }) => {
      if (!runs.length) return null
      //? which deadwax ran it: its health route says (no route of the bench's own)
      const deadwax = await fetch('/deadwax/health').then((r) => r.json() as Promise<{ version?: string }>).then((j) => j.version ?? null).catch(() => null)
      const file = checkFile(runs, {
        deadwax, when: new Date().toISOString(), userAgent: navigator.userAgent, secure: (globalThis as { isSecureContext?: boolean }).isSecureContext ?? null,
        voice: deckReport()?.voice ?? null, contextRate: deckRecordingData()?.sampleRate ?? null,
      }, stop)
      return URL.createObjectURL(new Blob([JSON.stringify(file)], { type: 'application/json' }))
    }
    try {
      if (!(await until(() => !!deckReport()?.voice, 6000))) throw new Error("the record's sound didn't start")
      for (const signalNow of CHECK_SIGNALS) {
        for (const id of CHECK_MOTIONS) {
          const def = MOTIONS.find((one) => one.id === id)!
          let done: MotionDone | null = null
          let before: DeckReport['health'] | undefined
          //? a run the page was hidden through is thrown away and made again, once a tap carries on
          for (;;) {
            if (checkStop.current) throw new Error(STOPPED)
            setCheck(state(`${SIGNALS.find((s) => s.id === signalNow)!.name}: ${def.label}`))
            //? the run's watch, its making ready included: a hide then leaves the sound suspended for it
            const hiding = watchForHide()
            try {
              if (madeRef.current?.signal.id !== signalNow || madeRef.current.signal.rate !== 44100) {
                setSignalId(signalNow)
                setRate(44100)
                if (!(await until(() => madeRef.current?.signal.id === signalNow && madeRef.current.signal.rate === 44100, 30000))) throw new Error('the song wasn\'t made')
              }
              if (playerRef.current.playing) playerRef.current.toggle()
              playerRef.current.seek(20)
              await sleep(400)
              before = deckReport()?.health
              done = await motion(id, true, null)
            } finally {
              hiding.stop()
            }
            if (checkStop.current) throw new Error(STOPPED)
            if (!done?.interrupted && !hiding.hidden) break
            setCheck(state(HIDDEN_CHECK, { waiting: true }))
            await new Promise<void>((go, stop) => { carryOn.current = { go, stop } })
          }
          if (!done?.data) throw new Error("a run couldn't be recorded")
          const after = deckReport()
          //? the window the voice had as the recording began - and any it was sent since are in its messages
          const what: Recorded = { label: def.label, made: madeRef.current!, windowAtStart: done.windowAtStart, motion: { def, result: done.result }, watch: null }
          const result = await compareRecording(done.data, what, false)
          runs.push({
            signal: madeRef.current!.signal.name, motion: def.label, voice: done.data.voice,
            clockStepMs: after?.clockStep ? after.clockStep * 1000 : null,
            //? the deck counts since the turntable showed - and from 0 again each time it shows: a run's
            //? are the difference (check.ts)
            ...runCounts(done.data.voice, before, after?.health),
            replayHeld: replayHeld(result.numbers),
            numbers: result.numbers, file: done.data.file,
          })
          setCheck(state(`${def.label}: done`))
          await sleep(300)
        }
      }
      setCheck({ ...state('Done'), running: false, href: await save({ complete: true, why: null }) })
    } catch (error) {
      const why = message(error)
      const byYou = why === STOPPED
      setCheck({ ...state('Stopped'), running: false, stoppedByYou: byYou, error: byYou ? null : why, href: await save({ complete: false, why: byYou ? 'stopped' : why }) })
    } finally {
      checking.current = false
      carryOn.current = null
    }
  }

  /* ----- the comparison's keys: Space plays or pauses, 1-3 switch - anywhere on the page ----- */

  //? while there is a comparison, wherever the focus is - but not where something else is typed into, and
  //? Space not on a control of something else (a button's own Space presses it); on the comparison's own
  //? controls (`data-room`) Space plays or pauses it. Played on the key's release: WebKit counts a keyup
  //? as a gesture, not a keydown
  useEffect(() => {
    if (!compared) return
    const typing = (target: EventTarget | null) => target instanceof HTMLElement && (/^(INPUT|SELECT|TEXTAREA)$/.test(target.tagName) || target.isContentEditable)
    const another = (target: EventTarget | null) =>
      target instanceof Element && !target.closest('[data-room]') && !!target.closest('button, a[href], summary, [role="button"], [role="radio"], [role="checkbox"]')
    const plain = (event: KeyboardEvent) => !event.altKey && !event.ctrlKey && !event.metaKey
    const down = (event: KeyboardEvent) => {
      if (event.defaultPrevented || !plain(event) || typing(event.target)) return
      if (event.key === ' ') {
        if (!another(event.target)) event.preventDefault()
        return
      }
      const index = ['1', '2', '3'].indexOf(event.key)
      if (index >= 0) {
        event.preventDefault()
        room.select(index)
      }
    }
    const up = (event: KeyboardEvent) => {
      if (event.key !== ' ' || !plain(event) || typing(event.target) || another(event.target)) return
      event.preventDefault()
      room.toggle()
    }
    document.addEventListener('keydown', down)
    document.addEventListener('keyup', up)
    return () => {
      document.removeEventListener('keydown', down)
      document.removeEventListener('keyup', up)
    }
  }, [compared])

  //? the arrow keys in a group of A, B and C (or A, B and X): the next one heard, and focused - one tab
  //? stop for the group, the one heard
  const onChipKey = (event: KeyboardEvent) => {
    const count = room.count
    const at = room.selected
    const next = event.key === 'ArrowRight' || event.key === 'ArrowDown' ? (at + 1) % count
      : event.key === 'ArrowLeft' || event.key === 'ArrowUp' ? (at + count - 1) % count
        : event.key === 'Home' ? 0 : event.key === 'End' ? count - 1 : -1
    if (next < 0 || !count) return
    event.preventDefault()
    room.select(next)
    ;(event.currentTarget as HTMLElement).querySelector<HTMLElement>(`[data-chip="${next}"]`)?.focus()
  }

  //? focus handed on once what had it went - never left on the page itself, where no key reaches the
  //? bench's controls (review of 2.0.0-player.36)
  useLayoutEffect(() => {
    const next = focusNext.current
    if (!next) return
    const target = document.querySelector<HTMLElement>(`[data-focus="${next.name}"]`)
    if (!target) return
    focusNext.current = null
    const active = document.activeElement
    const fell = !active || active === document.body || !active.isConnected
    const typing = active instanceof HTMLElement && /^(INPUT|SELECT|TEXTAREA)$/.test(active.tagName)
    if (fell || (next.force && !typing)) target.focus()
  })

  /* ----- the blind test ----- */

  const clipOf = (name: Clip) => compared!.result.clips[name]
  const startAbx = () => {
    if (!compared) return
    const x: 0 | 1 = Math.random() < 0.5 ? 0 : 1
    setAbx({ pair, trials, x, answers: [], guessed: null })
    setMode('abx')
    room.load([clipOf(pair[0]), clipOf(pair[1]), clipOf(pair[x])], compared.result.rate, 2)
    focusNext.current = { name: 'abx-play', force: false }
  }
  const guess = (which: 0 | 1) => {
    if (!abx || abx.guessed !== null) return
    const answers = [...abx.answers, which === abx.x]
    setAbx({ ...abx, guessed: which, answers })
    focusNext.current = { name: answers.length >= abx.trials ? 'abx-back' : 'abx-next', force: false }
  }
  const nextTrial = () => {
    if (!abx || !compared) return
    const x: 0 | 1 = Math.random() < 0.5 ? 0 : 1
    setAbx({ ...abx, x, guessed: null })
    room.load([clipOf(abx.pair[0]), clipOf(abx.pair[1]), clipOf(abx.pair[x])], compared.result.rate, 2)
    focusNext.current = { name: 'abx-play', force: false }
  }
  const backToCompare = () => {
    if (!compared) return
    setMode('compare')
    setAbx(null)
    room.load([compared.result.clips.A, compared.result.clips.B, compared.result.clips.C], compared.result.rate, 0)
    focusNext.current = { name: 'compare-play', force: false }
  }

  const signal = made?.signal ?? null
  const info = SIGNALS.find((one) => one.id === signalId)!
  //? a motion or the check running (a motion from its tap, its making ready included): the record can't be
  //? grabbed, nor the song played or paused, nor another started
  const busy = !!running || preparing || !!check?.running
  //? a recording under way (or waiting for the sound to start): the song held still while it records
  const recording = recorded?.state === 'recording' || startingRecord
  //? what changes the song, or records: none of it while either is under way
  const locked = busy || recording
  const abxDone = abx && abx.answers.length >= abx.trials
  const right = abx ? abx.answers.filter(Boolean).length : 0
  const chance = abx ? guessingChance(right, abx.answers.length) : 1

  return (
    <main class="lab">
      <header class="lab-head">
        <h1 class="lab-title">Turntable test bench</h1>
        <p class="lab-lead">
          The real turntable - the same record, deck and sound your phone runs - over simple signals this page makes. Turn it, or have it turned for
          you at perfect speeds; record what it played, and hear it beside an ideal turntable turned the same way.
        </p>
      </header>

      <section class="lab-section" aria-labelledby="lab-deck-title">
        <h2 id="lab-deck-title" class="app-section-title">The turntable</h2>
        <div ref={deckBox} class="lab-deck" inert={busy}>
          <Turntable player={player} open={true} discArt={null} onPreview={setPreviewing} windDown={windDown} deck={deckRef} windowSource={windowSource} />
        </div>
        <p class="lab-now">{signal ? signal.name : 'No song yet'}</p>
        <TurntableTime player={player} previewing={previewing} />
        <div class="lab-actions">
          <button type="button" class="app-button is-primary-lab" onClick={onPlay} aria-disabled={!made || busy}>
            {player.playing ? 'Pause' : 'Play'}
          </button>
          <button type="button" class="app-button" onClick={onStart}>Start the sound</button>
          <label class="lab-check">
            <input type="checkbox" checked={windDown} onChange={(event) => setWindDown((event.currentTarget as HTMLInputElement).checked)} />
            <span>Pause winds the record down</span>
          </label>
        </div>
        <p class="lab-status" role="status" aria-live="polite">{status}</p>
        <p class="lab-note">{voiceLine(report)}</p>
      </section>

      <section class="lab-section" aria-labelledby="lab-turn-title">
        <h2 id="lab-turn-title" class="app-section-title">Turn it for me</h2>
        <p class="lab-note">Each turns the record through the deck's own steps - a press, the take, 60 samples a second, the release - with nothing of a hand's unevenness unless you ask for it.</p>
        <div class="lab-motions">
          {MOTIONS.map((one) => (
            <button key={one.id} type="button" class={`app-button lab-motion${running?.id === one.id ? ' is-on' : ''}`} onClick={() => onMotion(one.id)} aria-disabled={busy || !made}>
              {one.label}
            </button>
          ))}
        </div>
        <div class="lab-actions">
          <label class="lab-check">
            <input type="checkbox" checked={jitter} disabled={busy} onChange={(event) => setJitter((event.currentTarget as HTMLInputElement).checked)} />
            <span>With a finger's jitter</span>
          </label>
          <button type="button" class="app-button" onClick={onStopMotion} aria-disabled={!running}>Stop the motion</button>
        </div>
      </section>

      <section class="lab-section" aria-labelledby="lab-song-title">
        <h2 id="lab-song-title" class="app-section-title">The song</h2>
        <fieldset class="lab-fieldset" disabled={locked}>
          <legend class="lab-legend">Signal</legend>
          <div class="lab-options">
            {SIGNALS.map((one) => (
              <label key={one.id} class={`lab-option${one.reference ? ' is-reference' : ''}`}>
                <input type="radio" name="lab-signal" value={one.id} checked={one.id === signalId} onChange={() => setSignalId(one.id)} />
                <span class="lab-option-words">
                  <span class="lab-option-name">{one.name}</span>
                  <span class="lab-option-note">{one.shows}</span>
                </span>
              </label>
            ))}
          </div>
        </fieldset>
        {signalId === 'file' && (
          <label class="lab-file">
            <span class="lab-file-label">A file on this device</span>
            <input
              type="file"
              accept="audio/*"
              disabled={locked}
              onChange={(event) => {
                const file = (event.currentTarget as HTMLInputElement).files?.[0]
                if (file) void file.arrayBuffer().then((bytes) => setPicked({ name: file.name, bytes }))
              }}
            />
          </label>
        )}
        <fieldset class="lab-fieldset" disabled={locked}>
          <legend class="lab-legend">Made at</legend>
          <div class="lab-options is-row">
            {SOURCE_RATES.map((one) => (
              <label key={one} class="lab-option is-short">
                <input type="radio" name="lab-rate" value={one} checked={one === rate} onChange={() => setRate(one)} />
                <span class="lab-option-name">{one / 1000} kHz{one === 44100 ? ' (a CD rip)' : one === 96000 ? ' (a hi-res song)' : ''}</span>
              </label>
            ))}
          </div>
        </fieldset>
        <p class="lab-note">
          {making ?? `${signal?.name ?? info.name}: ${clock(made?.song.seconds ?? 0)}, made at ${rate / 1000} kHz, a 24-bit WAV. ${info.shows}`}
        </p>
      </section>

      <section class="lab-section" aria-labelledby="lab-record-title">
        <h2 id="lab-record-title" class="app-section-title">Record, and compare</h2>
        <div class="lab-actions">
          <button type="button" class="app-button" onClick={onRecord} aria-disabled={busy || !made || recording}>Record {RECORD_SECONDS} s</button>
          <button type="button" class="app-button" aria-pressed={armed} onClick={() => !(busy || recording) && setArmed(!armed)} aria-disabled={busy || recording}>
            Record the next motion
          </button>
          {recorded?.state === 'saved' && recorded.href && (
            <a class="app-button" href={recorded.href} download={recorded.name ?? 'deadwax-turntable.json'}>Save the recording</a>
          )}
        </div>
        <p class="lab-status" role="status" aria-live="polite">{comparing ?? (armed ? 'The next motion is recorded' : '')}</p>
        {compared && (
          <div class="lab-compare">
            <p class="lab-note">Of: {compared.label}. Space plays or pauses, 1-3 switch - at the same moment of the recording, through a moment's silence that is the same whichever you switch to.</p>
            {mode === 'compare' ? (
              <>
                <div class="lab-actions">
                  <button type="button" class="app-button" data-room data-focus="compare-play" onClick={onListen}>{room.playing ? 'Pause' : 'Play'} the comparison</button>
                  <button type="button" class="app-button" data-room onClick={() => room.restart()}>From the start</button>
                </div>
                <div class="lab-choices" role="radiogroup" aria-label="Which to hear" onKeyDown={onChipKey}>
                  {CLIPS.map((name, index) => (
                    <button key={name} type="button" role="radio" aria-checked={room.selected === index} tabIndex={room.selected === index ? 0 : -1} data-room data-chip={index} class={`app-chip lab-choice${room.selected === index ? ' is-on' : ''}`} onClick={() => room.select(index)}>
                      {CLIP_NAMES[name]}
                    </button>
                  ))}
                </div>
                <ul class="lab-clip-notes">
                  {CLIPS.map((name) => <li key={name}><strong>{name}</strong>: {CLIP_NOTES[name]}</li>)}
                </ul>
                {compared.result.images && (
                  <div class="lab-figures">
                    {CLIPS.map((name) => <Spectrogram key={name} image={compared.result.images![name]} label={CLIP_NAMES[name]} />)}
                  </div>
                )}
                <Rows rows={numberRows(compared.result.numbers)} />
                <p class="lab-meaning">{meaning(compared.result.numbers)}</p>
                <div class="lab-abx-setup">
                  <h3 class="lab-subtitle">Blind</h3>
                  <label class="lab-field">
                    <span>Compare</span>
                    <select value={pair.join('')} onChange={(event) => setPair((event.currentTarget as HTMLSelectElement).value.split('') as [Clip, Clip])}>
                      <option value="AB">A and B</option>
                      <option value="AC">A and C</option>
                      <option value="BC">B and C</option>
                    </select>
                  </label>
                  <label class="lab-field">
                    <span>Trials</span>
                    <input type="number" min={4} max={40} value={trials} onChange={(event) => setTrials(Math.max(4, Math.min(40, Number((event.currentTarget as HTMLInputElement).value) || 10)))} />
                  </label>
                  <button type="button" class="app-button" onClick={startAbx}>Start the blind test</button>
                </div>
              </>
            ) : abx && (
              <div class="lab-abx">
                <p class="lab-note">
                  Trial {Math.min(abx.answers.length + (abx.guessed === null ? 1 : 0), abx.trials)} of {abx.trials}: is X {abx.pair[0]} or {abx.pair[1]}?
                </p>
                <div class="lab-actions">
                  <button type="button" class="app-button" data-room data-focus="abx-play" onClick={onListen}>{room.playing ? 'Pause' : 'Play'} the trial</button>
                </div>
                <div class="lab-choices" role="radiogroup" aria-label="Which to hear" onKeyDown={onChipKey}>
                  {[abx.pair[0], abx.pair[1], 'X'].map((name, index) => (
                    <button key={name} type="button" role="radio" aria-checked={room.selected === index} tabIndex={room.selected === index ? 0 : -1} data-room data-chip={index} class={`app-chip lab-choice${room.selected === index ? ' is-on' : ''}`} onClick={() => room.select(index)}>
                      {name}
                    </button>
                  ))}
                </div>
                {!abxDone && abx.guessed === null && (
                  <div class="lab-actions">
                    <button type="button" class="app-button" onClick={() => guess(0)}>X is {abx.pair[0]}</button>
                    <button type="button" class="app-button" onClick={() => guess(1)}>X is {abx.pair[1]}</button>
                  </div>
                )}
                {abx.guessed !== null && (
                  <p class="lab-status" role="status" aria-live="polite">
                    {abx.answers[abx.answers.length - 1] ? 'Right' : 'Wrong'}: X was {abx.pair[abx.x]}.
                  </p>
                )}
                {abx.guessed !== null && !abxDone && <button type="button" class="app-button" data-focus="abx-next" onClick={nextTrial}>Next trial</button>}
                {abxDone && (
                  <p class="lab-meaning">
                    {right} of {abx.trials} right. The chance of doing that well by guessing: {chance < 0.001 ? 'under 1 in 1,000' : `${(chance * 100).toFixed(1)}%`}
                    {chance < 0.05 ? ' - you can hear the difference.' : ' - that could be guessing.'}
                  </p>
                )}
                <button type="button" class="app-button" data-focus="abx-back" onClick={backToCompare}>Back to A, B and C</button>
              </div>
            )}
          </div>
        )}
      </section>

      <section class="lab-section" aria-labelledby="lab-check-title">
        <h2 id="lab-check-title" class="app-section-title">Check this device</h2>
        <p class="lab-note">
          Runs, on the 1 kHz and 440 Hz sines, steady 1x, 0.5x, 2x, backwards 1x and the wobble, recording each - about a minute and a half - and
          gives you a file of the numbers and the recordings to send. Keep the page in view and the screen awake while it runs: a hidden page
          stops the record's sound, and a run it stops is made again once you tap Carry on.
        </p>
        <div class="lab-actions">
          <button type="button" class="app-button" onClick={onCheck} aria-disabled={locked}>Check this device</button>
          <button type="button" class="app-button" onClick={onStopCheck} aria-disabled={!check?.running}>Stop the check</button>
          {check?.waiting && <button type="button" class="app-button is-primary-lab" onClick={onCarryOn}>Carry on</button>}
          {check?.href && <a class="app-button" href={check.href} download="deadwax-turntable-check.json">Save results</a>}
        </div>
        <p class="lab-status" role="status" aria-live="polite">{check ? checkLine(check) : ''}</p>
        {check && check.runs.length > 0 && (
          <ol class="lab-runs">
            {check.runs.map((run, index) => (
              <li key={index} class="app-card lab-run">
                <p class="lab-run-title">{run.signal}, {run.motion}</p>
                <Rows rows={[
                  { label: 'Voice', value: run.voice === 'script' ? 'The main thread' : 'An AudioWorklet' },
                  { label: 'Clock step', value: run.clockStepMs === null ? 'Not known' : `${run.clockStepMs.toFixed(1)} ms` },
                  { label: 'Blocks late', value: blocksLine(run) },
                  { label: 'Frames late', value: framesLine(run) },
                  //? where the replay didn't hold, what it measured is the stall's: none of it shown
                  ...(run.replayHeld ? [
                    { label: 'Speed wobble above 20 Hz', value: `${percent(run.numbers.wobble.deadwax)} (smooth path ${percent(run.numbers.wobble.smooth)})` },
                    {
                      label: "What isn't the signal",
                      value: run.numbers.stray ? `${dbText(run.numbers.stray.db)}${run.numbers.stray.loudest ? `, the loudest at ${Math.round(run.numbers.stray.loudest.hz)} Hz (${dbText(run.numbers.stray.loudest.db)})` : ''}` : 'Not measured',
                    },
                  ] : [{ label: 'Record it again', value: againLine(run.numbers) ?? NOT_HELD }]),
                ]} />
              </li>
            ))}
          </ol>
        )}
      </section>

      <section class="lab-section" aria-labelledby="lab-live-title">
        <h2 id="lab-live-title" class="app-section-title">The record's sound, live</h2>
        <LiveSpectrum />
      </section>

      <section class="lab-section" aria-labelledby="lab-voice-title">
        <h2 id="lab-voice-title" class="app-section-title">How the sound is running</h2>
        <p class="lab-note">Info &gt; Debug's turntable rows, as the app shows them.</p>
        <Voice report={report} />
      </section>
    </main>
  )
}
