import { useLayoutEffect, useRef, useState } from 'preact/hooks'

import { panelIsModal, type PanelStyle } from '../lib/appFrame'
import { dragOffset, dropIndex } from '../lib/pins'
import { nextRepeat, repeatLabel, upNextView, type UpNextRow } from '../lib/upNext'
import { Cover } from '../player/Cover'
import { ChevronDownIcon, ChevronUpIcon, CloseIcon, GripIcon, RepeatIcon, RepeatOneIcon, ShuffleIcon } from '../player/icons'
import type { Player } from '../player/usePlayer'
import { useSheet } from './useSheet'

/** Which of Up Next's two groups a row is in: the songs added (Playing Next), or the list's. */
type Group = 'added' | 'list'

/** A row being dragged in Edit: which, in which group, from where, how far, by which pointer, the rows' pitch. */
interface Drag {
  key: number
  group: Group
  start: number
  y: number
  dy: number
  pitch: number
  pointer: number
}

/** What Up Next says under the song playing with Repeat One on. */
export const REPEATING_ONE = 'Repeat one: this song plays again until you skip it.'
/** ...and under the Shuffle chip for a whole library's shuffle (Part B), whose order is the shuffle. */
export const SHUFFLING_LIBRARY = 'Shuffling your whole library'

const songLine = (row: { track: { artist: string; album: string } }) => [row.track.artist, row.track.album].filter(Boolean).join(' · ')
const plural = (count: number) => `And ${count.toLocaleString('en-US')} more ${count === 1 ? 'song' : 'songs'}.`

/**
 * Up Next (2.0.0-player.57) - James: "i'd like to be able to see the queue somewhere in the player, but I don't
 * want to disrupt the theme we have going". Opened from Now Playing's Up next button, as a sheet over it on a
 * phone, and from the player bar's Up Next as the side panel on a desktop - Info's shell, so it looks like Info.
 * What it draws is lib/upNext.ts's upNextView: the song playing (and, with Repeat One, that it repeats); Shuffle
 * and Repeat, the iPhone's Music app's place for them, so Now Playing's own screen gets nothing but the button;
 * Playing Next - the songs added, with Clear - when there are any; the rest of the album or list this time round
 * (up to UP_NEXT_DRAWN, then "And N more songs."); and what comes after it. Neither Repeat One's copies nor
 * the later times round are drawn.
 *
 * A ROW'S TAP plays it now (player.jumpTo, straight from the click - a tap, so it may start a stream as a song's
 * tap on an album does): the rows above it in its own group go. Rows are Up Next's own keys, so a song in twice
 * is two rows, and a tap names the row even if the queue moved on under the finger - a key gone does nothing.
 *
 * EDIT, as Home's Pinned does it: each group's rows with Move up, Move down and Remove, and a grip to drag by
 * (lib/pins.ts dropIndex and dragOffset - only the grip takes the pointer, so the sheet still scrolls under a
 * finger elsewhere); a move stays within its group; each change made as it is tapped, nothing to save. Focus is
 * kept as Pinned keeps it - on a move's button where the row went; after a removal on the next row's Remove,
 * the one before at the end, Done with none left - and what changed is read out. The header's Done ends Edit;
 * Escape and the backdrop close the sheet, ending it.
 *
 * A sheet like the others (useSheet.ts) - its own scroll lock, focus in to Done and back to the button that
 * opened it, Escape, the backdrop - and on a desktop the panel, not modal, as Info is. A leaf: props only.
 */
export function UpNext({
  open,
  opener,
  onClose,
  player,
  panel = 'sheet',
  covered = false,
}: {
  open: boolean
  opener?: { current: HTMLElement | null } | undefined
  onClose: () => void
  player: Pick<Player, 'queue' | 'track' | 'playing' | 'shuffle' | 'repeat' | 'setShuffle' | 'setRepeat' | 'jumpTo' | 'moveInQueue' | 'removeFromQueue' | 'clearPlayingNext'>
  /** how it is drawn: a sheet over Now Playing (a phone), or a desktop's side panel */
  panel?: PanelStyle
  /** something over it - the desktop's visualizer: inert, out of a screen reader's reach, until it goes */
  covered?: boolean
}) {
  const modal = panelIsModal(panel)
  const done = useRef<HTMLButtonElement>(null)
  const box = useRef<HTMLDivElement>(null)
  const scroller = useRef<HTMLDivElement>(null)
  const shuffleChip = useRef<HTMLButtonElement>(null)
  const [editing, setEditing] = useState(false)
  const [drag, setDrag] = useState<Drag | null>(null)
  const [said, setSaid] = useState('')
  //? where focus goes once a change has drawn - Pinned's rule: a move's button where the row went, the next
  //? row's Remove after a removal, Done with none left, the Shuffle chip after Clear; Done as Edit starts (the
  //? Edit button pressed goes from the head); after a row's tap - that row now the song playing, so gone from the
  //? list - the row after it, or Done with none (focus never left on nothing, where Escape can't reach the panel)
  const refocus = useRef<{ key: number; which: 'up' | 'down' | 'remove' | 'play' } | 'done' | 'shuffle' | null>(null)
  useSheet({ open, covered, onClose, lockClass: 'app-upnext-open', first: done, opener, modal, area: box })

  //? every opening starts at the top, and out of Edit
  useLayoutEffect(() => {
    if (!open) return
    setEditing(false)
    setDrag(null)
    if (scroller.current) scroller.current.scrollTop = 0
  }, [open])

  useLayoutEffect(() => {
    const wanted = refocus.current
    refocus.current = null
    if (!wanted) return
    if (wanted === 'done' || wanted === 'shuffle') {
      ;(wanted === 'done' ? done.current : shuffleChip.current)?.focus()
      return
    }
    //? by the row's own data, never a selector built from it
    const row = scroller.current
      ? [...scroller.current.querySelectorAll<HTMLElement>('[data-key]')].find((each) => each.dataset.key === String(wanted.key))
      : undefined
    const live = (which: string) => row?.querySelector<HTMLButtonElement>(`.app-pin-${which}:not([aria-disabled="true"])`) ?? null
    const target = wanted.which === 'play'
      ? row?.querySelector<HTMLButtonElement>('.app-result') ?? done.current
      : wanted.which === 'remove'
        ? row?.querySelector<HTMLButtonElement>('.app-pin-remove') ?? done.current
        : live(wanted.which) ?? live(wanted.which === 'up' ? 'down' : 'up')
    target?.focus()
  })

  const view = upNextView(player.queue, player.repeat)
  const paged = !!player.queue.upNext?.paged
  const playing = view.playing
  const groups: { group: Group; rows: UpNextRow[] }[] = [
    { group: 'added', rows: view.added },
    { group: 'list', rows: view.list?.rows ?? [] },
  ]
  const editable = view.added.length + (view.list?.rows.length ?? 0) > 0

  const toggleShuffle = () => {
    if (paged) return
    const on = !player.shuffle
    player.setShuffle(on)
    setSaid(on ? 'Shuffle on' : 'Shuffle off')
  }
  const cycleRepeat = () => {
    const mode = nextRepeat(player.repeat)
    player.setRepeat(mode)
    setSaid(mode === 'off' ? 'Repeat off' : repeatLabel(mode))
  }
  const clear = () => {
    refocus.current = 'shuffle'
    player.clearPlayingNext()
    setSaid('Playing Next cleared')
  }

  const move = (row: UpNextRow, rows: readonly UpNextRow[], from: number, by: -1 | 1) => {
    const to = from + by
    if (to < 0 || to >= rows.length) return
    refocus.current = { key: row.key, which: by < 0 ? 'up' : 'down' }
    player.moveInQueue(row.key, to)
    setSaid(`${row.track.title}: ${to + 1} of ${rows.length}`)
  }
  const remove = (row: UpNextRow, rows: readonly UpNextRow[], index: number) => {
    const next = rows[index + 1] ?? rows[index - 1]
    refocus.current = next ? { key: next.key, which: 'remove' } : 'done'
    player.removeFromQueue(row.key)
    setSaid(`${row.track.title} removed`)
  }

  //? the drag: by the grip only, one pointer, the rows' pitch measured as it starts - Pinned's own
  const startDrag = (event: PointerEvent, row: UpNextRow, group: Group, index: number) => {
    if (drag || event.button > 0) return
    const grip = event.currentTarget as HTMLElement
    const item = grip.closest('li')
    if (!item) return
    const after = item.nextElementSibling as HTMLElement | null
    const before = item.previousElementSibling as HTMLElement | null
    const pitch = after ? after.offsetTop - item.offsetTop : before ? item.offsetTop - before.offsetTop : item.offsetHeight
    grip.setPointerCapture?.(event.pointerId)
    event.preventDefault()
    setDrag({ key: row.key, group, start: index, y: event.clientY, dy: 0, pitch, pointer: event.pointerId })
  }
  const followDrag = (event: PointerEvent) => {
    if (drag && event.pointerId === drag.pointer) setDrag({ ...drag, dy: event.clientY - drag.y })
  }
  const endDrag = (event: PointerEvent, rows: readonly UpNextRow[]) => {
    if (!drag || event.pointerId !== drag.pointer) return
    const to = dropIndex(drag.start, event.clientY - drag.y, drag.pitch, rows.length)
    setDrag(null)
    if (to === drag.start) return
    player.moveInQueue(drag.key, to)
    const row = rows[drag.start]
    if (row) setSaid(`${row.track.title}: ${to + 1} of ${rows.length}`)
  }
  const dropDrag = (event: PointerEvent) => {
    if (drag && event.pointerId === drag.pointer) setDrag(null)
  }

  const toggleEditing = () => {
    if (editing) {
      setEditing(false)
      setDrag(null)
      return
    }
    //? the Edit button goes as Edit starts: focus to Done, which now ends it
    refocus.current = 'done'
    setEditing(true)
  }

  /** A row's tap: it plays now, so it leaves the list - focus to the row after it (Playing Next's last: the list's
   *  first), or Done with none. */
  const jump = (group: Group, rows: readonly UpNextRow[], index: number) => {
    const row = rows[index]!
    const after = rows[index + 1] ?? (group === 'added' ? groups[1]!.rows[0] : undefined)
    refocus.current = after ? { key: after.key, which: 'play' } : 'done'
    player.jumpTo(row.key)
  }

  /** One group's rows: to tap (play now), or in Edit to move, remove and drag. */
  const rowsOf = (group: Group, rows: readonly UpNextRow[]) => {
    if (!rows.length) return null
    if (!editing) {
      return (
        <ul class="app-results">
          {rows.map((row, index) => (
            <li key={row.key} data-key={row.key}>
              <button type="button" class="app-result" aria-label={`${row.track.title}, play now`} onClick={() => jump(group, rows, index)}>
                <Cover id={row.track.coverArt} size={96} class="app-result-cover" />
                <span class="app-result-text">
                  <span class="app-result-title">{row.track.title}</span>
                  <span class="app-result-line">{songLine(row)}</span>
                </span>
              </button>
            </li>
          ))}
        </ul>
      )
    }
    const dragging = drag?.group === group ? drag : null
    const landing = dragging ? dropIndex(dragging.start, dragging.dy, dragging.pitch, rows.length) : -1
    return (
      <ol class="app-pins-edit">
        {rows.map((row, index) => {
          const offset = dragging ? dragOffset(index, dragging.start, landing, dragging.dy, dragging.pitch) : 0
          return (
            <li
              key={row.key}
              data-key={row.key}
              class={`app-pin-row app-card${dragging?.key === row.key ? ' is-dragging' : ''}`}
              style={offset ? { transform: `translateY(${offset}px)` } : undefined}
            >
              <span class="app-pin-text">
                <span class="app-pin-title">{row.track.title}</span>
                <span class="app-pin-line">{songLine(row)}</span>
              </span>
              <button type="button" class="app-pin-move app-pin-up" aria-label={`Move ${row.track.title} up`} aria-disabled={index === 0} onClick={() => move(row, rows, index, -1)}>
                <span class="app-pin-move-face">
                  <ChevronUpIcon class="app-pin-move-icon" />
                </span>
              </button>
              <button type="button" class="app-pin-move app-pin-down" aria-label={`Move ${row.track.title} down`} aria-disabled={index === rows.length - 1} onClick={() => move(row, rows, index, 1)}>
                <span class="app-pin-move-face">
                  <ChevronDownIcon class="app-pin-move-icon" />
                </span>
              </button>
              <button type="button" class="app-pin-move app-pin-remove" aria-label={`Remove ${row.track.title}`} onClick={() => remove(row, rows, index)}>
                <span class="app-pin-move-face">
                  <CloseIcon class="app-pin-move-icon" />
                </span>
              </button>
              <span
                class="app-pin-grip"
                aria-hidden="true"
                onPointerDown={(event) => startDrag(event, row, group, index)}
                onPointerMove={followDrag}
                onPointerUp={(event) => endDrag(event, rows)}
                onPointerCancel={dropDrag}
                onLostPointerCapture={dropDrag}
              >
                <GripIcon class="app-pin-grip-icon" />
              </span>
            </li>
          )
        })}
      </ol>
    )
  }

  return (
    <div class={`app-layer app-info-layer app-upnext-layer${open ? ' is-open' : ''}${modal ? '' : ` is-panel is-${panel}`}`} aria-hidden={!open || covered} inert={!open || covered}>
      <div class="app-backdrop" onClick={onClose} />
      {/* a panel's box takes focus from a click on anything in it that can't, so Escape there is still from inside it */}
      <div ref={box} class="app-info app-upnext" role="dialog" aria-modal={modal ? 'true' : 'false'} aria-labelledby="app-upnext-title" tabIndex={modal ? undefined : -1}>
        <header class="app-info-head">
          {!editing && editable && (
            <button type="button" class="app-upnext-edit" onClick={toggleEditing}>
              Edit
            </button>
          )}
          <h2 id="app-upnext-title" class="app-info-title">
            Up Next
          </h2>
          {/* closes - or, while editing, ends Edit: one Done */}
          <button ref={done} type="button" class="app-info-done" onClick={editing ? toggleEditing : onClose}>
            Done
          </button>
        </header>
        {/* what a change made here was, read out - always in the page, as iOS reads only a region already there */}
        <p class="app-visually-hidden" role="status" aria-live="polite" aria-atomic="true">{said}</p>

        <div ref={scroller} class="app-info-scroll" tabIndex={0}>
          {playing && (
            <>
              <div class="app-card app-info-card app-upnext-playing">
                <Cover id={playing.coverArt} size={128} class="app-info-cover" />
                <div class="app-info-text">
                  <p class="app-info-name">{playing.title}</p>
                  <p class="app-info-line">{[playing.artist, playing.album].filter(Boolean).join(' · ')}</p>
                </div>
              </div>
              {view.repeatOne && <p class="app-store-line">{REPEATING_ONE}</p>}

              <div class="app-upnext-modes" role="group" aria-label="Shuffle and repeat">
                <button
                  ref={shuffleChip}
                  type="button"
                  class={`app-chip app-upnext-shuffle${player.shuffle ? ' is-on' : ''}`}
                  aria-pressed={player.shuffle}
                  aria-disabled={paged}
                  onClick={toggleShuffle}
                >
                  <ShuffleIcon class="app-chip-icon" />
                  Shuffle
                </button>
                <button
                  type="button"
                  class={`app-chip app-upnext-repeat${player.repeat === 'off' ? '' : ' is-on'}`}
                  aria-pressed={player.repeat !== 'off'}
                  onClick={cycleRepeat}
                >
                  {player.repeat === 'one' ? <RepeatOneIcon class="app-chip-icon" /> : <RepeatIcon class="app-chip-icon" />}
                  {repeatLabel(player.repeat)}
                </button>
              </div>
              {paged && <p class="app-store-line">{SHUFFLING_LIBRARY}</p>}

              {view.added.length > 0 && (
                <section class="app-upnext-group" aria-labelledby="app-upnext-added">
                  <div class="app-section-head">
                    <h3 id="app-upnext-added" class="app-section-title">Playing Next</h3>
                    <button type="button" class="app-text-button app-upnext-clear" onClick={clear}>
                      Clear
                    </button>
                  </div>
                  {rowsOf('added', groups[0]!.rows)}
                </section>
              )}

              {view.list && (
                <section class="app-upnext-group" aria-labelledby="app-upnext-list">
                  <div class="app-section-head">
                    <h3 id="app-upnext-list" class="app-section-title">{view.list.title}</h3>
                  </div>
                  {rowsOf('list', groups[1]!.rows)}
                  {view.list.more > 0 && <p class="app-store-line">{plural(view.list.more)}</p>}
                </section>
              )}

              {view.then && <p class="app-store-line app-upnext-then">{view.then}</p>}
            </>
          )}
        </div>
      </div>
    </div>
  )
}
