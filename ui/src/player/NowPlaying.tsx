import { useEffect, useLayoutEffect, useRef, useState } from 'preact/hooks'

import { useSheet } from '../app/useSheet'
import { clock, dragEnd, dragFor, dragMove, dragStart, keyTarget, shownTime, timeAt, type Drag } from '../lib/scrub'
import { lookButtonLabel, otherLook, playingDisc, type Look } from '../lib/turntable'
import { discArtUrl, playedAlbum } from './api'
import { Cover } from './Cover'
import { wakeDeckAudio, type Deck } from './deck'
import { SpeedChip } from './SpeedChip'
import {
  AirPlayIcon, ChevronDownIcon, MoreIcon, NextIcon, PauseIcon, PlayIcon, PreviousIcon, RecordIcon, SquareIcon,
} from './icons'
import { Turntable, TurntableTime, type TurntablePreview } from './Turntable'
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
 *
 * The desktop's player bar draws this same bar (2.0.0-player.19, PlayerBar.tsx): one way to seek.
 */
export function Scrubber({ player }: { player: Player }) {
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
 * The full player, as a sheet over everything. Dragged down by its top half to close, like the
 * one it copies; the bar and the buttons below are left to their own gestures.
 *
 * As the Now Playing board draws it (2.0.0-player.10): the cover, the song, "Artist — Album" as one
 * line that goes to the album, the scrubber, the transport, and a row of icons - AirPlay when
 * there is a speaker to send to, and ••• for Info and "Go to album". No readout and no Gapless
 * control: how the song was sent and how the last changes and seek went are in Info > Debug
 * (app/InfoSheet.tsx), and Gapless is a setting, in You > Playback (app/GaplessChoice.tsx). The
 * board's Lyrics and Up next icons aren't drawn until there is something for them to open.
 *
 * THE BODY IS ANCHORED TO THE BOTTOM of the sheet, so a change in the height of anything in it
 * moves what is above it and nothing below. Everything from the title down is therefore a fixed
 * height - one line each, and the icon row a tap target tall with or without AirPlay in it - and
 * the one thing that comes and goes, a song's failure, is ABOVE the title: it moves the cover and
 * nothing a finger goes to. Anything added here whose height can change goes up there too.
 *
 * A sheet like the others (app/useSheet.ts): its own scroll lock, focus in to the close button and
 * back to what opened it, Escape. It is inert while closed, and while Info or the menu is over it
 * (`covered`).
 *
 * TWO LOOKS (2.0.0-player.11): the cover and the bar, or the turntable (Turntable.tsx) - the
 * record in the cover's place and a time line in the bar's. It opens as You > Playback's "Now
 * Playing opens as" says (`openAs`), every time, and the button at the top right switches for as
 * long as it stays open, leaving the setting alone. The look is chosen here, below App, so
 * switching it re-renders this sheet and never the engine. The sheet still closes only from its
 * grip - the top row alone on the turntable, whose record and arm sit OUTSIDE the grip, so neither
 * starts the sheet's drag and the sheet's drag never starts from them.
 *
 * THE TURNTABLE'S SOUND (2.0.0-player.14, player/deck.ts): every tap on the turntable's look - the
 * transport's three buttons, the look button switching to it - wakes the deck's audio context, which
 * may only start in a gesture. The transport's pause on the turntable winds the record down as the
 * record's own tap does (`windDown`, You's "Pause winds the record down"), and its play starts from
 * where a coasting or winding-down record is; the cover's pause is always instant, and nothing of
 * the deck runs while the cover shows - its previous and next wake nothing.
 *
 * THE SPEED (2.0.0-player.39): the turntable has its fader (player/SpeedFader.tsx, inside Turntable); the
 * cover has the speed's chip (player/SpeedChip.tsx), "1.25x" at the left of the icon row wherever the
 * speed isn't 1x, a tap back to 1x - in the row that is one fixed height, so it moves nothing. On the
 * turntable it is drawn too, and app.css shows it only on a phone on its side, where the plinth is too
 * small to read the fader's own readout.
 */
export function NowPlaying({
  player,
  open,
  covered,
  opener,
  onClose,
  onMore,
  onAlbum,
  openAs,
  windDown = true,
  pinnable = false,
}: {
  player: Player
  open: boolean
  /** Info or the ••• menu is over it */
  covered: boolean
  /** what opened it, given focus back as it closes */
  opener: { current: HTMLElement | null }
  onClose: () => void
  /** the ••• button's tap - the event, so the button can be given focus back */
  onMore: (event: MouseEvent) => void
  /** close the sheet and open the song's album */
  onAlbum: () => void
  /** You > Playback's "Now Playing opens as": the look it opens in, every time */
  openAs: Look
  /** You > Playback's "Pause winds the record down" - the turntable's pause only */
  windDown?: boolean
  /** the ••• menu will have the album's pin (App's: a song whose album can be pinned) */
  pinnable?: boolean
}) {
  const track = player.track
  const [dragY, setDragY] = useState(0)
  const drag = useRef<{ pointer: number; startY: number; captured: boolean } | null>(null)
  const closeButton = useRef<HTMLButtonElement>(null)
  //? the look showing: the setting's as it opens, switched by the button while it stays open
  const [look, setLook] = useState<Look>(openAs)
  const [previewing, setPreviewing] = useState<TurntablePreview>(null)
  //? the turntable's deck while it shows: the transport's pause winds it down too
  const deck = useRef<Deck | null>(null)

  //? the page behind must not scroll under a finger on the sheet; focus goes to the close button -
  //? the first thing in it - as it opens, since everything behind it is inert now (App)
  useSheet({ open, covered, onClose, lockClass: 'pl-sheet-open', first: closeButton, opener })

  //? every opening starts as the setting says, before the paint - never as the button left it
  useLayoutEffect(() => {
    if (open) setLook(openAs)
  }, [open])

  if (!track) return null
  const turntable = look === 'turntable'

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

  //? "Artist — Album", as the board has it; either alone when the other isn't known
  const byline = [track.artist, track.album].filter(Boolean).join(' — ')

  //? On the turntable, a tap on the transport is a gesture the deck's sound may start from; and its
  //? pause winds the record down, as the record's tap does - the song sought to where that stops.
  //? On the cover, exactly as ever.
  const onPrevious = () => {
    if (turntable) wakeDeckAudio()
    player.previous()
  }
  const onToggle = () => {
    if (!turntable) {
      player.toggle()
      return
    }
    wakeDeckAudio()
    if (player.playing) {
      const landing = deck.current?.pausing() ?? null
      player.toggle()
      if (landing !== null) player.seek(landing)
      return
    }
    //? a play while the record coasts or winds down with its sound: from where the record is
    const from = deck.current?.resuming() ?? null
    if (from !== null) player.seek(from)
    player.toggle()
  }
  const onNext = () => {
    if (turntable) wakeDeckAudio()
    player.next()
  }
  //? switching TO the turntable is a gesture too: its deck's sound can start as it appears
  const onLook = () => {
    if (look === 'cover') wakeDeckAudio()
    setLook(otherLook(look))
  }

  return (
    <div
      class={`pl-sheet${open ? ' is-open' : ''}${dragY ? ' is-dragging' : ''}${turntable ? ' app-is-turntable' : ''}`}
      style={open && dragY ? { transform: `translateY(${dragY}px)` } : undefined}
      aria-hidden={!open || covered}
      inert={!open || covered}
    >
      <Cover id={track.coverArt} size={300} class="pl-sheet-backdrop" />

      {/* the sheet's drag to close starts here and nowhere else: the top row and the cover - and
          on the turntable only the top row, the record and the arm being outside it */}
      <div
        class={`pl-sheet-grip${turntable ? ' app-grip-top' : ''}`}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onPointerEnd}
        onPointerCancel={onPointerEnd}
        //? A mouse moving on the cover would otherwise start dragging the IMAGE, as a browser does
        //? with any picture, and cancel the pointer - the sheet stopped following it mid-drag.
        onDragStart={(event) => event.preventDefault()}
      >
        <div class="app-np-top">
          <button ref={closeButton} type="button" class="pl-sheet-close" onClick={onClose} aria-label="Close">
            <ChevronDownIcon class="pl-icon" />
          </button>
          {/* the other look, for as long as this stays open - the setting is You's */}
          <button type="button" class="app-look-button" onClick={onLook} aria-label={lookButtonLabel(look)}>
            <span class="app-look-face">
              {turntable ? <SquareIcon class="app-look-icon" /> : <RecordIcon class="app-look-icon" />}
            </span>
          </button>
        </div>
        {!turntable && (
          <div class={`pl-sheet-art${player.playing ? '' : ' is-paused'}`}>
            <Cover id={track.coverArt} size={1000} class="pl-sheet-cover" />
          </div>
        )}
      </div>

      {turntable && (
        <Turntable
          player={player}
          open={open}
          discArt={discArtUrl(track.albumId, playingDisc(playedAlbum(track.albumId)?.song, track.id))}
          onPreview={setPreviewing}
          windDown={windDown}
          deck={deck}
          fader={player}
        />
      )}

      <div class="pl-sheet-body">
        <div class="pl-sheet-titles">
          {/* A failure comes and goes, so it is ABOVE the title: the body sits against the bottom
              of the sheet, and a line appearing here moves the cover - never the album line, the
              bar or the buttons under a finger. On the turntable, where that room is the record
              and the arm, app.css lays it over the plinth's foot instead, out of the flow. */}
          {player.error && <p class="pl-sheet-error">{player.error}</p>}
          <h2 class="pl-sheet-title">{track.title}</h2>
          {/* one box either way, so which it is never moves the bar; the ellipsis is the span's,
              since the link's tap target reaches past its own box (player.css) */}
          {track.albumId ? (
            <button type="button" class="pl-sheet-artist is-link" onClick={onAlbum} aria-label={`Go to the album: ${byline}`}>
              <span class="pl-sheet-byline">{byline}</span>
            </button>
          ) : (
            <p class="pl-sheet-artist">
              <span class="pl-sheet-byline">{byline}</span>
            </p>
          )}
        </div>

        {turntable ? <TurntableTime player={player} previewing={previewing} /> : <Scrubber player={player} />}

        <div class="pl-transport">
          <button type="button" class="pl-transport-button" onClick={onPrevious} aria-label="Previous">
            <PreviousIcon class="pl-transport-icon" />
          </button>
          <button
            type="button"
            class={`pl-transport-button is-main${player.buffering ? ' is-busy' : ''}`}
            onClick={onToggle}
            aria-label={player.playing ? 'Pause' : 'Play'}
          >
            {player.playing ? <PauseIcon class="pl-transport-icon" /> : <PlayIcon class="pl-transport-icon" />}
          </button>
          <button type="button" class="pl-transport-button" onClick={onNext} aria-label="Next">
            <NextIcon class="pl-transport-icon" />
          </button>
        </div>

        {/* The icon row, a tap target tall whatever is in it. ••• is always there, at the right
            end; AirPlay comes and goes to its left, so nothing moves when a speaker does - nor the
            speed's chip, at the left end, when the speed leaves 1x and comes back (2.0.0-player.39). */}
        <div class="pl-sheet-footer">
          <SpeedChip player={player} />
          {player.airplay && (
            <button type="button" class="pl-icon-button" onClick={player.showAirPlay} aria-label="AirPlay">
              <AirPlayIcon class="pl-icon" />
            </button>
          )}
          <button
            type="button"
            class="pl-icon-button"
            onClick={onMore}
            //? what the menu holds: "Go to album" only for a song that names its album, and the album's pin
            //? (2.0.0-player.18) only when the menu will have one - App says so
            aria-label={`More: info${track.albumId ? ', go to album' : ''}${track.albumId && pinnable ? ', pin' : ''}`}
            aria-haspopup="dialog"
            aria-expanded={covered}
          >
            <MoreIcon class="pl-icon" />
          </button>
        </div>
      </div>
    </div>
  )
}
