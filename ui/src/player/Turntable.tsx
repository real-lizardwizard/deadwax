import { useEffect, useRef, useState } from 'preact/hooks'

import { clock, keyTarget } from '../lib/scrub'
import {
  ARM, ARM_PARTS, PLATTER, RECORD, STAGE, across, armAngle, armMove, armStart, dragEnd, dragFor, moved, needleAt,
  placeCircle, placePoint, preview, recordMove, recordStart, shownTime, spinning, timeLine, type Box, type Drag,
  type Preview,
} from '../lib/turntable'
import { Cover } from './Cover'
import { usePosition, type Player } from './usePlayer'

/** What the drag says in place of the song's position - the time line under the song shows it. */
export type TurntablePreview = Preview | null

const DEG = 180 / Math.PI

/** Whether the page is showing: false on a locked phone, or with the app in the background. */
function useVisible(): boolean {
  const [visible, setVisible] = useState(() => document.visibilityState !== 'hidden')
  useEffect(() => {
    const onChange = () => setVisible(document.visibilityState !== 'hidden')
    document.addEventListener('visibilitychange', onChange)
    return () => document.removeEventListener('visibilitychange', onChange)
  }, [])
  return visible
}

/**
 * Now Playing as a turntable (2.0.0-player.11), on the phone: a record on a platter and a tonearm,
 * drawn from the Turntable board's geometry (lib/turntable.ts - the drawing and the finger's maths
 * are one set of numbers). James asked for it, "as long as it has the disc art on the 'record'".
 *
 * - THE RECORD's face is the album's CD art - deadwax's own disc.<ext>, or disc<N>.<ext> for the
 *   playing song's disc of a set, found by /deadwax/library/disc_art/navidrome - and, when there
 *   is none (a 404, or while it loads), plain black vinyl with the album's cover as the label. It
 *   turns at 33 1/3 rpm while the song plays: a CSS animation, paused where it is when the song
 *   pauses, while a finger holds the record, while Now Playing is closed and whenever the page is
 *   hidden (a locked phone) - so nothing is drawn frame by frame for nobody - and stopped for good
 *   under reduced motion. Nothing here runs from the engine's clock.
 * - A TAP on it plays or pauses: the click, in the tap, as the transport's button does. TURNING it
 *   moves the song 1.8 s a turn, backwards too, from wherever the song has got to when it lets go
 *   (it plays on under the finger); the song moves where it lets go, and the click after a turn is
 *   not a tap - however the turn ends.
 * - THE ARM moves in from the outer groove as the song plays, following the song's position
 *   (usePosition, like the scrubber - no timer of its own). Dragged, it goes anywhere in the song,
 *   seeking where it lets go; to the keyboard and VoiceOver it is a slider, stepping as the
 *   scrubber does. Pointer capture on both drags; a cancel seeks nowhere; a second finger starts
 *   nothing.
 * - A drag is measured in the stage's box as the press found it, so nothing that moves the layout
 *   under a still finger moves the song.
 * - Neither starts the sheet's drag to close: they are not inside its grip (NowPlaying.tsx).
 * - No hint and no coach mark (James: "the instructions for how to use it are a little annoying").
 *
 * A leaf: the player and the disc art's address come as props. `onPreview` tells Now Playing what
 * the drag says, for the time line under the song's name.
 */
export function Turntable({
  player,
  open,
  discArt,
  onPreview,
}: {
  player: Player
  /** Now Playing is open - closed, the record stops */
  open: boolean
  /** the CD art to draw on the record, or null for the plain one */
  discArt: string | null
  onPreview: (next: TurntablePreview) => void
}) {
  const position = usePosition(player)
  //? the song's position as last drawn: a release seeks from it, so it lands where the time line said
  const drawnAt = useRef(position)
  drawnAt.current = position
  const visible = useVisible()
  //? the stage's own box, where every point of the drawing is placed from
  const frame = useRef<SVGSVGElement>(null)
  //? the drag in a ref as well as in state: a move and the release can both come before the render
  //? between them, and the release must seek where the last move put it (the scrubber's rule)
  const held = useRef<Drag | null>(null)
  const [drag, setDragShown] = useState<Drag | null>(null)
  //? the stage's box as the press found it - the whole drag is measured in it
  const pressBox = useRef<Box | null>(null)
  //? how far the hand has turned the record, degrees - it stays where the hand left it
  const [turn, setTurn] = useState(0)
  //? the click after a turn is not a tap; reset by the next press, since not every turn has a click
  const turned = useRef(false)
  const [failedArt, setFailedArt] = useState<string | null>(null)
  const [loadedArt, setLoadedArt] = useState<string | null>(null)

  //? every opening looks for the CD art again: a failure is remembered only while Now Playing stays
  //? open, so art saved since (Get CD art), or a Navidrome that was down, is found by the next one -
  //? a turntable left mounted across a close (the setting says Turntable) included
  useEffect(() => {
    if (open) setFailedArt(null)
  }, [open])

  const length = player.duration || 0
  const track = player.track?.id ?? ''

  const setDrag = (next: Drag | null) => {
    held.current = next
    setDragShown(next)
    onPreview(preview(next))
  }

  //? the song changed under the finger: the drag was for the song before, and seeks nowhere
  useEffect(() => {
    if (held.current && !dragFor(held.current, track)) setDrag(null)
  }, [track])

  //? gone (the look switched, the song ended with nothing after it): nothing is previewed any more
  useEffect(() => () => onPreview(null), [])

  const previewing = preview(drag)
  const shown = shownTime(previewing, position, length)

  const box = (): Box => {
    const rect = frame.current!.getBoundingClientRect()
    return { left: rect.left, top: rect.top, width: rect.width, height: rect.height }
  }
  const pressable = (event: PointerEvent) => event.isPrimary && !(event.pointerType === 'mouse' && event.button !== 0)

  const onRecordDown = (event: PointerEvent) => {
    if (!pressable(event)) return
    //? a new press: a turn before it that no click followed is forgotten (a second finger is no
    //? press - it would forget the turn the first is still making)
    turned.current = false
    ;(event.currentTarget as HTMLElement).setPointerCapture(event.pointerId)
    pressBox.current = box()
    setDrag(recordStart(event.pointerId, track, event.clientX, event.clientY, pressBox.current))
  }
  const onArmDown = (event: PointerEvent) => {
    if (!length || !pressable(event)) return
    ;(event.currentTarget as HTMLElement).setPointerCapture(event.pointerId)
    pressBox.current = box()
    setDrag(armStart(event.pointerId, track, event.clientX, event.clientY))
  }
  const onMove = (event: PointerEvent) => {
    const now = held.current
    if (!now) return
    const within = pressBox.current ?? box()
    const next = now.kind === 'record'
      ? recordMove(now, event.pointerId, event.clientX, event.clientY, within, length, drawnAt.current)
      : armMove(now, event.pointerId, event.clientX, event.clientY, within, length, drawnAt.current)
    if (next === now) return
    //? a turn past a tap: the click after it is not a tap, however the drag ends - even dropped by
    //? the song changing under it, when no release says so and a mouse's click still comes
    if (next?.kind === 'record' && moved(next)) turned.current = true
    setDrag(next)
  }
  const onRelease = (how: 'up' | 'cancel') => (event: PointerEvent) => {
    const now = held.current
    const { drag: next, seek, wasDrag } = dragEnd(now, event.pointerId, how, drawnAt.current, length)
    if (next === now) return
    //? a turn let go: the record stays turned, and the click that may follow isn't a tap
    if (now?.kind === 'record' && wasDrag && how === 'up') {
      setTurn((before) => before + now.turned * DEG)
      turned.current = true
    }
    setDrag(next)
    if (seek !== null && length) player.seek(seek)
  }
  //? THE TAP: play or pause, straight from the click - nothing awaited before it
  const onRecordClick = () => {
    if (turned.current) {
      turned.current = false
      return
    }
    player.toggle()
  }
  const onArmKey = (event: KeyboardEvent) => {
    const target = keyTarget(event.key, shown, length)
    if (target === null) return
    event.preventDefault()
    player.seek(target)
  }

  const spin = spinning({ playing: player.playing, open, visible, held: drag?.kind === 'record' })
  const handTurn = turn + (drag?.kind === 'record' && moved(drag) ? drag.turned * DEG : 0)
  const needle = needleAt(shown, length)
  const lifted = drag?.kind === 'arm'
  const art = discArt && discArt !== failedArt ? discArt : null
  const { bar, head, weight } = ARM_PARTS

  return (
    <div class="app-tt">
      <div class="app-tt-stage" style={{ '--app-tt-aspect': String(STAGE.width / STAGE.height) }}>
        <svg ref={frame} class="app-tt-layer" viewBox={`0 0 ${STAGE.width} ${STAGE.height}`} aria-hidden="true">
          <circle class="app-tt-platter" cx={PLATTER.x} cy={PLATTER.y} r={PLATTER.r} />
        </svg>

        <button
          type="button"
          class="app-tt-record"
          style={placeCircle(RECORD)}
          aria-label={player.playing ? 'The record: a tap pauses the song' : 'The record: a tap plays the song'}
          onPointerDown={onRecordDown}
          onPointerMove={onMove}
          onPointerUp={onRelease('up')}
          onPointerCancel={onRelease('cancel')}
          //? capture lost without an up is a cancel too; after an up the drag is gone already
          onLostPointerCapture={onRelease('cancel')}
          onClick={onRecordClick}
          //? a mouse on the disc art would otherwise drag the IMAGE away, and cancel the pointer
          onDragStart={(event) => event.preventDefault()}
        >
          <span class="app-tt-turn" style={{ transform: `rotate(${+handTurn.toFixed(2)}deg)` }}>
            <span class={`app-tt-face${spin ? ' is-spinning' : ''}${art && art === loadedArt ? ' has-art' : ''}`}>
              <Cover id={player.track?.coverArt} size={300} class="app-tt-label" />
              {art && (
                <img
                  class="app-tt-disc"
                  src={art}
                  alt=""
                  decoding="async"
                  draggable={false}
                  onLoad={() => setLoadedArt(art)}
                  onError={() => setFailedArt(art)}
                />
              )}
              <span class="app-tt-grooves" />
              <span class="app-tt-spindle" />
            </span>
          </span>
        </button>
        <span class="app-tt-sheen" style={placeCircle(RECORD)} aria-hidden="true" />

        <svg class="app-tt-layer" viewBox={`0 0 ${STAGE.width} ${STAGE.height}`} aria-hidden="true">
          <g class={`app-tt-arm${lifted ? ' is-lifted' : ''}`} transform={`rotate(${+armAngle(shown, length).toFixed(3)} ${ARM.x} ${ARM.y})`}>
            <rect class="app-tt-weight" x={ARM.x + weight.from} y={ARM.y - weight.thick / 2} width={weight.length} height={weight.thick} rx={weight.radius} />
            <rect class="app-tt-bar" x={ARM.x} y={ARM.y - bar.thick / 2} width={ARM.reach} height={bar.thick} rx={bar.radius} />
            <rect
              class="app-tt-head"
              x={ARM.x + head.from}
              y={ARM.y - head.thick / 2 - (lifted ? ARM_PARTS.lift : 0)}
              width={head.length}
              height={head.thick}
              rx={head.radius}
            />
          </g>
          <circle class="app-tt-pivot" cx={ARM.x} cy={ARM.y} r={ARM_PARTS.base - ARM_PARTS.baseEdge / 2} stroke-width={ARM_PARTS.baseEdge} />
        </svg>

        {/* the arm, to a finger: taken by its head, round the needle. To the keyboard and to
            VoiceOver (whose swipe up and down WebKit sends as arrow keys), the song's position,
            stepping as the scrubber does */}
        <div
          class={`app-tt-handle${lifted ? ' is-held' : ''}`}
          role="slider"
          tabIndex={length ? 0 : -1}
          aria-label="Tonearm: position in the song"
          aria-valuemin={0}
          aria-valuemax={Math.round(length)}
          aria-valuenow={Math.round(shown)}
          aria-valuetext={`${clock(shown)} of ${clock(length)}`}
          aria-disabled={!length}
          style={{ ...placePoint(needle), width: across(ARM_PARTS.handle) }}
          onPointerDown={onArmDown}
          onPointerMove={onMove}
          onPointerUp={onRelease('up')}
          onPointerCancel={onRelease('cancel')}
          onLostPointerCapture={onRelease('cancel')}
          onKeyDown={onArmKey}
        />
      </div>
    </div>
  )
}

/**
 * The line under the song's name in the turntable's Now Playing, in place of the scrubber: "2:31 of
 * 7:05", and while the record is turned or the arm held, where letting go will go. One line, a
 * fixed height, so nothing under it moves (see NowPlaying).
 */
export function TurntableTime({
  player,
  previewing,
}: {
  player: Player
  previewing: TurntablePreview
}) {
  const position = usePosition(player)
  const length = player.duration || 0
  return <p class="app-tt-time">{timeLine(shownTime(previewing, position, length), length, previewing?.how ?? null)}</p>
}
