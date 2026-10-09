import { useRef, useState } from 'preact/hooks'

import {
  FADER, FADER_FROM, READOUT, SPEED_MAX, SPEED_MIN, SPEED_NORMAL, faderEnd, faderMove, faderShare, faderStart, faderTravel, speedKey,
  speedLabel, speedWords, type FaderDrag,
} from '../lib/playSpeed'
import { STAGE, placePoint } from '../lib/turntable'
import { useSpeed, type Player } from './usePlayer'

/** What the fader reads of the player, and the one thing it does to it. */
export type SpeedPlayer = Pick<Player, 'speed' | 'onSpeed' | 'setSpeed'>

const pct = (value: number) => `${+(value * 100).toFixed(4)}%`
/** The knob's whole travel in the plinth's units, a knob's height included: what the target covers. */
const SPAN = FADER.bottom - FADER.top + FADER.knob.height
const SPAN_TOP = FADER.top - FADER.knob.height / 2
/** Where the knob's centre is for a speed, in the plinth's units. */
const yFor = (speed: number) => FADER.bottom - faderShare(speed) * (FADER.bottom - FADER.top)

/**
 * The speed fader (2.0.0-player.39), on the turntable's plinth beside the platter, as a record deck's
 * pitch control: up is faster, 0.25x at the bottom, 2x at the top, by octaves (lib/playSpeed - 1x two
 * thirds of the way up, where a mark is drawn, lit while the speed is 1x). The Turntable board has none,
 * so it is drawn in the board's style from the theme's tokens: a sunken slot, a knob in the arm's greys,
 * and under it a readout ("1.00x") in a well, purple while the speed isn't 1x.
 *
 * - LIVE: the speed changes as the finger moves, as a pitch fader's does - each move a setSpeed, which
 *   the player puts on its element at once. It takes hold only once the finger has travelled a tap's
 *   few pixels, from where the speed is then (the arm's rule), so a press or a nudge never jumps it,
 *   and a drag within 2% of 1x lands on 1x exactly - the detent.
 * - Measured in the fader's own box as the press found it; the pointer captured; a second finger
 *   starts and moves nothing; a cancel keeps where it had got to (it was live all along).
 * - The readout puts it back to exactly 1x in one tap.
 * - To the keyboard and to VoiceOver (whose swipe up and down WebKit sends as arrow keys), a vertical
 *   slider: the arrows a hundredth, Page Up and Page Down a tenth, Home 0.25x, End 2x - "1.25 times",
 *   "normal speed".
 * - Every touch on it is its own (touch-action: none), and it is a 44px target unless the plinth is too
 *   small to hold one beside the record - a phone on its side, the arm handle's rule (app.css). It never
 *   reaches the record: centred on the slot only while that keeps it clear of the record's rim, and
 *   otherwise starting just past it (lib/playSpeed's faderTarget) - the record takes every touch on
 *   itself, its rim's too.
 * - OUTSIDE Now Playing's grip, inside the turntable's stage, as the record and the arm are: it never
 *   starts the sheet's drag.
 *
 * ui/test/app-rules.sim.cjs allows this file setSpeed, and nothing else of the player.
 */
export function SpeedFader({ player }: { player: SpeedPlayer }) {
  const speed = useSpeed(player)
  //? the drag in a ref as well as in state: a move and the release can both come before the render
  const held = useRef<FaderDrag | null>(null)
  const [drag, setDragShown] = useState<FaderDrag | null>(null)
  //? how far the knob travels on screen, measured as the press found the fader
  const travel = useRef(0)

  const setDrag = (next: FaderDrag | null) => {
    held.current = next
    setDragShown(next)
  }

  const onPointerDown = (event: PointerEvent) => {
    if (!event.isPrimary || (event.pointerType === 'mouse' && event.button !== 0)) return
    const target = event.currentTarget as HTMLElement
    target.setPointerCapture(event.pointerId)
    //? its box is the knob's travel and a knob's height: the stage's height from it, and the travel
    travel.current = faderTravel((target.getBoundingClientRect().height / SPAN) * STAGE.height)
    setDrag(faderStart(event.pointerId, event.clientY))
  }
  const onPointerMove = (event: PointerEvent) => {
    const before = held.current
    if (!before) return
    //? the speed it takes hold from is the player's as it is now - every move's set is there at once
    const { drag: next, speed: to } = faderMove(before, event.pointerId, event.clientY, travel.current, player.speed())
    if (next !== before) setDrag(next)
    if (to !== null) player.setSpeed(to)
  }
  const onRelease = (event: PointerEvent) => {
    const next = faderEnd(held.current, event.pointerId)
    if (next !== held.current) setDrag(next)
  }
  const onKeyDown = (event: KeyboardEvent) => {
    const to = speedKey(event.key, player.speed())
    if (to === null) return
    event.preventDefault()
    player.setSpeed(to)
  }

  const knobY = yFor(speed)
  const markY = yFor(SPEED_NORMAL)
  const { knob, mark } = FADER
  const normal = speed === SPEED_NORMAL
  const taken = !!drag?.from
  return (
    <>
      <svg class="app-tt-layer" viewBox={`0 0 ${STAGE.width} ${STAGE.height}`} aria-hidden="true">
        <rect class="app-tt-fader-slot" x={FADER.x - FADER.slot / 2} y={SPAN_TOP} width={FADER.slot} height={SPAN} rx={FADER.slotRadius} />
        <rect
          class={`app-tt-fader-mark${normal ? ' is-on' : ''}`}
          x={FADER.x - knob.width / 2 - mark.overhang}
          y={markY - mark.thick / 2}
          width={knob.width + 2 * mark.overhang}
          height={mark.thick}
        />
        <g class={`app-tt-fader-knob${taken ? ' is-held' : ''}`}>
          <rect x={FADER.x - knob.width / 2} y={knobY - knob.height / 2} width={knob.width} height={knob.height} rx={knob.radius} />
          <rect class="app-tt-fader-grip" x={FADER.x - knob.width / 2 + knob.gripInset} y={knobY - knob.grip / 2} width={knob.width - 2 * knob.gripInset} height={knob.grip} />
        </g>
      </svg>
      {/* the fader to a finger: the knob's whole travel, a tap target wide */}
      <div
        class={`app-tt-fader${taken ? ' is-held' : ''}`}
        role="slider"
        tabIndex={0}
        aria-label="Speed"
        aria-orientation="vertical"
        aria-valuemin={SPEED_MIN}
        aria-valuemax={SPEED_MAX}
        aria-valuenow={speed}
        aria-valuetext={speedWords(speed)}
        //? where it may be: the slot to centre on and the record's rim to keep right of (app.css places it)
        style={{
          '--app-tt-fader-x': pct(FADER.x / STAGE.width),
          '--app-tt-fader-from': pct(FADER_FROM / STAGE.width),
          top: pct(SPAN_TOP / STAGE.height),
          height: pct(SPAN / STAGE.height),
        }}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onRelease}
        onPointerCancel={onRelease}
        //? capture lost without an up is the end of it too; after an up the drag is gone already
        onLostPointerCapture={onRelease}
        onKeyDown={onKeyDown}
      />
      {/* the readout: what plays, and a tap back to exactly 1x */}
      <button
        type="button"
        class={`app-tt-readout${normal ? '' : ' is-off'}`}
        style={placePoint(READOUT)}
        aria-label={normal ? 'Speed: normal' : `Speed ${speedLabel(speed)}: back to normal speed`}
        aria-disabled={normal}
        onClick={() => player.setSpeed(SPEED_NORMAL)}
      >
        <span class="app-tt-readout-face">{speedLabel(speed)}</span>
      </button>
    </>
  )
}
