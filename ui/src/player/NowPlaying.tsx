import { useEffect, useRef, useState } from 'preact/hooks'

import { describeGaps } from '../lib/gapless'
import { clock, describeSeek, dragEnd, dragFor, dragMove, dragStart, keyTarget, shownTime, timeAt, type Drag } from '../lib/scrub'
import { describeWrap } from '../lib/streamWrap'
import { Cover } from './Library'
import { AirPlayIcon, ChevronDownIcon, NextIcon, PauseIcon, PlayIcon, PreviousIcon } from './icons'
import { usePosition, type Player } from './usePlayer'

/** How far a drag down has to go before letting go closes the sheet. */
const DISMISS_PX = 110

/**
 * How far a press on the grip has to move before it is taken as a drag. Short of it, it may be a
 * tap on the close button - which the grip must not capture the pointer for, see onPointerMove.
 */
const DRAG_START_PX = 6

/**
 * The bar and the two clocks. The whole bar is the target, 44px tall: a tap seeks to where it
 * lands, and a drag follows the finger and seeks where it lets go - never on the way, so a drag
 * across the song doesn't ask for every part of it. It is not an <input type=range>, which on an
 * iPhone moves only when dragged by its thumb: a tap on the bar, or a drag begun beside the thumb,
 * did nothing there. While a finger is on the bar it shows where the finger is, not where the song
 * is; once let go, the player shows the seek's target until the element has landed (see
 * reportedPosition() in lib/scrub), so the thumb never goes back to the old time meanwhile.
 *
 * A slider to the keyboard and to VoiceOver (whose swipe up and down WebKit sends as arrow keys):
 * arrows move 5 seconds, Page Up and Down 30, Home and End to the ends.
 */
function Scrubber({ player }: { player: Player }) {
  const position = usePosition(player)
  const bar = useRef<HTMLDivElement>(null)
  //? The drag in a ref as well as in state: a move and the release can both arrive before the
  //? render between them, and the release must seek to where the LAST move put it.
  const held = useRef<Drag | null>(null)
  const [drag, setDragShown] = useState<Drag | null>(null)
  const setDrag = (next: Drag | null) => {
    held.current = next
    setDragShown(next)
  }
  const length = player.duration || 0
  const track = player.track?.id ?? ''
  const shown = shownTime(dragFor(drag, track), position, length)
  const done = length ? (shown / length) * 100 : 0

  //? the song changed under the finger: the drag was for the song before, and seeks nowhere
  useEffect(() => {
    if (held.current && !dragFor(held.current, track)) setDrag(null)
  }, [track])

  const timeFor = (event: PointerEvent) => {
    //? The bar's place on screen. Its rect is right here, where the art viewer needs offsetWidth:
    //? nothing scales the bar, and the sheet only ever moves on its y axis (closing, opening).
    const rect = bar.current!.getBoundingClientRect()
    return timeAt(event.clientX, rect.left, rect.width, length)
  }

  const onPointerDown = (event: PointerEvent) => {
    if (!length || !event.isPrimary || (event.pointerType === 'mouse' && event.button !== 0)) return
    //? every move and the release come here wherever the finger goes, off the bar included
    ;(event.currentTarget as HTMLElement).setPointerCapture(event.pointerId)
    setDrag(dragStart(event.pointerId, track, timeFor(event)))
  }
  const onPointerMove = (event: PointerEvent) => {
    if (!held.current) return
    const next = dragMove(held.current, event.pointerId, timeFor(event))
    if (next !== held.current) setDrag(next)
  }
  const onRelease = (how: 'up' | 'cancel') => (event: PointerEvent) => {
    const { drag: next, seek } = dragEnd(held.current, event.pointerId, how)
    if (next === held.current) return
    setDrag(next)
    if (seek !== null) player.seek(seek)
  }
  const onKeyDown = (event: KeyboardEvent) => {
    const target = keyTarget(event.key, shown, length)
    if (target === null) return
    event.preventDefault()
    player.seek(target)
  }

  return (
    <div class="pl-scrubber">
      <div
        ref={bar}
        class={`pl-scrub${drag ? ' is-held' : ''}`}
        role="slider"
        tabIndex={length ? 0 : -1}
        aria-label="Position in the song"
        aria-valuemin={0}
        aria-valuemax={Math.round(length)}
        aria-valuenow={Math.round(shown)}
        aria-valuetext={`${clock(shown)} of ${clock(length)}`}
        aria-disabled={!length}
        style={{ '--done': `${done}%` }}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onRelease('up')}
        onPointerCancel={onRelease('cancel')}
        //? capture lost without an up - the element taken away mid-drag - is a cancel too; after
        //? an up the drag is already gone and this changes nothing
        onLostPointerCapture={onRelease('cancel')}
        onKeyDown={onKeyDown}
      >
        <span class="pl-scrub-track" />
        <span class="pl-scrub-thumb" />
      </div>
      <div class="pl-clocks">
        <span>{clock(shown)}</span>
        <span>-{clock(length - shown)}</span>
      </div>
    </div>
  )
}

/**
 * The gapless switch, iOS's shape. What the last song changes took is in the readouts at the top
 * of the sheet's body, timed with the switch off as well, so the two can be compared on the phone:
 * from one song's end to the next one's sound starting, and how the next one was started - see
 * clockStep() in lib/gapless.
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
        {/* The readouts come FIRST, above everything a finger goes to. The body sits against the
            bottom of the sheet, so a line that grows or shrinks moves whatever is above it and
            nothing below: under the bar, their one to three lines (a seek asked, then judged at
            its song's end) moved the scrubber and the buttons up and down the screen at the
            moment of a tap. Up here the most that moves is the cover. */}
        <div class="pl-readouts">
          <p class="pl-gapless-readout">{describeGaps(player.gaps)}</p>
          {/* ending "· FLAC in MP4" when the song was sent that way - how the phone shows it */}
          <p class="pl-gapless-readout pl-seek-readout">
            {describeSeek(player.lastSeek) + describeWrap(player.wrapped, track.id)}
          </p>
        </div>

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
      </div>
    </div>
  )
}
