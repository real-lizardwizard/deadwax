import { useEffect, useRef, useState } from 'preact/hooks'

import { describeGaps } from '../lib/gapless'
import { Cover } from './Library'
import { AirPlayIcon, ChevronDownIcon, NextIcon, PauseIcon, PlayIcon, PreviousIcon } from './icons'
import { usePosition, type Player } from './usePlayer'

/** "3:07" - and "0:00" for nothing, which a clock should say where a track list says nothing. */
function clock(seconds: number): string {
  const whole = Math.max(0, Math.floor(seconds || 0))
  return `${Math.floor(whole / 60)}:${String(whole % 60).padStart(2, '0')}`
}

/** How far a drag down has to go before letting go closes the sheet. */
const DISMISS_PX = 110

/**
 * How far a press on the grip has to move before it is taken as a drag. Short of it, it may be a
 * tap on the close button - which the grip must not capture the pointer for, see onPointerMove.
 */
const DRAG_START_PX = 6

/**
 * The bar and the two clocks. While a finger is on the bar it shows where the finger is, not
 * where the song is - otherwise the thumb jumps back under it on every position update.
 */
function Scrubber({ player }: { player: Player }) {
  const position = usePosition(player)
  const [dragging, setDragging] = useState<number | null>(null)
  const length = player.duration || 0
  const shown = Math.min(dragging ?? position, length || Infinity)
  const done = length ? (shown / length) * 100 : 0

  return (
    <div class="pl-scrubber">
      <input
        type="range"
        class="pl-range"
        min={0}
        max={length || 1}
        step="any"
        value={shown}
        disabled={!length}
        aria-label="Position in the song"
        style={{ '--done': `${done}%` }}
        onInput={(event) => setDragging(Number(event.currentTarget.value))}
        onChange={(event) => {
          player.seek(Number(event.currentTarget.value))
          setDragging(null)
        }}
      />
      <div class="pl-clocks">
        <span>{clock(shown)}</span>
        <span>-{clock(length - shown)}</span>
      </div>
    </div>
  )
}

/**
 * The gapless switch, iOS's shape, and what the last song changes took. The readout is timed with
 * the switch off as well, so the two can be compared on the phone: from one song's end to the next
 * one's sound starting, and how the next one was started - see clockStep() in lib/gapless.
 */
function Gapless({ player }: { player: Player }) {
  return (
    <label class="pl-gapless">
      <span class="pl-gapless-label">Gapless</span>
      <button
        type="button"
        role="switch"
        class={`pl-switch${player.gapless ? ' is-on' : ''}`}
        aria-checked={player.gapless}
        aria-label="Gapless"
        //? a click, not a change event: this tap is what unlocks the second audio element on iOS
        onClick={() => player.setGapless(!player.gapless)}
      >
        <span class="pl-switch-track">
          <span class="pl-switch-knob" />
        </span>
      </button>
    </label>
  )
}

/**
 * The full player, as a sheet over everything. Dragged down by its top half to close, like the
 * one it copies; the bar and the buttons below are left to their own gestures.
 */
export function NowPlaying({ player, open, onClose }: { player: Player; open: boolean; onClose: () => void }) {
  const track = player.track
  const [dragY, setDragY] = useState(0)
  const drag = useRef<{ pointer: number; startY: number; captured: boolean } | null>(null)

  //? the page behind must not scroll under a finger on the sheet
  useEffect(() => {
    document.documentElement.classList.toggle('pl-sheet-open', open)
  }, [open])

  if (!track) return null

  const onPointerDown = (event: PointerEvent) => {
    drag.current = { pointer: event.pointerId, startY: event.clientY, captured: false }
  }
  const onPointerMove = (event: PointerEvent) => {
    const held = drag.current
    if (held?.pointer !== event.pointerId) return
    //? let go where the grip never heard it - a mouse released outside before the drag began
    if (!event.buttons) {
      drag.current = null
      setDragY(0)
      return
    }
    const moved = event.clientY - held.startY
    if (!held.captured) {
      if (Math.abs(moved) < DRAG_START_PX) return
      //? Only now, once it is a drag, does the grip take the pointer, so the rest of the drag
      //? reaches it wherever the finger goes. Capturing at the press took the click away from
      //? the close button inside the grip - a captured pointer's click goes to whatever holds
      //? it - and the arrow closed nothing in Chromium.
      held.captured = true
      ;(event.currentTarget as HTMLElement).setPointerCapture(event.pointerId)
    }
    setDragY(Math.max(0, moved))
  }
  const onPointerEnd = () => {
    if (!drag.current) return
    drag.current = null
    if (dragY > DISMISS_PX) onClose()
    setDragY(0)
  }

  return (
    <div
      class={`pl-sheet${open ? ' is-open' : ''}${dragY ? ' is-dragging' : ''}`}
      style={open && dragY ? { transform: `translateY(${dragY}px)` } : undefined}
      aria-hidden={!open}
      inert={!open}
    >
      <Cover id={track.coverArt} size={300} class="pl-sheet-backdrop" />

      <div
        class="pl-sheet-grip"
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onPointerEnd}
        onPointerCancel={onPointerEnd}
        //? A mouse moving on the cover would otherwise start dragging the IMAGE, as a browser does
        //? with any picture, and cancel the pointer - the sheet stopped following it mid-drag.
        onDragStart={(event) => event.preventDefault()}
      >
        <button type="button" class="pl-sheet-close" onClick={onClose} aria-label="Close">
          <ChevronDownIcon class="pl-icon" />
        </button>
        <div class={`pl-sheet-art${player.playing ? '' : ' is-paused'}`}>
          <Cover id={track.coverArt} size={1000} class="pl-sheet-cover" />
        </div>
      </div>

      <div class="pl-sheet-body">
        <div class="pl-sheet-titles">
          <h2 class="pl-sheet-title">{track.title}</h2>
          <p class="pl-sheet-artist">{track.artist}</p>
          {player.error && <p class="pl-sheet-error">{player.error}</p>}
        </div>

        <Scrubber player={player} />

        <div class="pl-transport">
          <button type="button" class="pl-transport-button" onClick={player.previous} aria-label="Previous">
            <PreviousIcon class="pl-transport-icon" />
          </button>
          <button
            type="button"
            class={`pl-transport-button is-main${player.buffering ? ' is-busy' : ''}`}
            onClick={player.toggle}
            aria-label={player.playing ? 'Pause' : 'Play'}
          >
            {player.playing ? <PauseIcon class="pl-transport-icon" /> : <PlayIcon class="pl-transport-icon" />}
          </button>
          <button type="button" class="pl-transport-button" onClick={player.next} aria-label="Next">
            <NextIcon class="pl-transport-icon" />
          </button>
        </div>

        <div class="pl-sheet-footer">
          <span class="pl-sheet-album">{track.album}</span>
          <Gapless player={player} />
          {player.airplay && (
            <button type="button" class="pl-icon-button" onClick={player.showAirPlay} aria-label="AirPlay">
              <AirPlayIcon class="pl-icon" />
            </button>
          )}
        </div>
        <p class="pl-gapless-readout">{describeGaps(player.gaps)}</p>
      </div>
    </div>
  )
}
