import { useEffect, useLayoutEffect, useRef, useState } from 'preact/hooks'

import { entryAt, fitIndex, type IndexEntry, type IndexSlot } from '../lib/shelves'

/** The least height an entry is drawn at, when the token can't be read (a test's page). */
const ENTRY_FALLBACK_PX = 16

/**
 * The index down the shelf's right edge (2.0.0-player.59, Apple's A-Z; the decades for Year): a jump to a group's
 * header. Sticky beside the shelf, its height the view's between the bars, so it stays in view as the page scrolls
 * and never lies over a panel (app.css `.app-index`).
 *
 * It fits the height: when the entries don't fit at their least height (--app-index-entry - 27 letters at 320×568),
 * lib/shelves.ts fitIndex keeps as many as fit with a dot between each two, aria-hidden and inert.
 *
 * TOUCH: `touch-action: none`, so a drag on it never scrolls the page; pointerdown captures the pointer and jumps to
 * the entry under the finger - the drawn slot under it, a letter's own or, over a dot, one of the letters it stands
 * for (lib/shelves.ts entryAt), so a drawn letter always lands on itself and a letter drawn as a dot is still reached
 * by dragging - and pointermove jumps again whenever the entry under the finger changes, at most once a
 * frame; pointerup and pointercancel let go. The position is read over the DRAWN slots - the first slot's top to the
 * last's bottom (`extent`) - never the strip's own box: the strip is the view's height and centres its letters, so
 * its box is far taller than they are, and a finger on A read over it jumped to G (the review of .59). And it is read
 * over the slots AS THEY WERE at pointerdown, for the whole of that press (`held`): a first tap before the strip is
 * stuck scrolls the page and the strip moves up under a finger that hasn't, and reading the moved strip would take a
 * twitch for a drag to another letter.
 *
 * A pointer's jump is the jump: the click its pointerup leaves (`detail` above 0) is let go (`pressed`) - with the
 * pointer captured it reaches the strip, not the button, and before the strip is stuck the button under the finger is
 * another letter's by then. A click with no pointerdown before it - Enter or Space (`detail` 0), a screen reader's
 * activation - jumps to its own entry.
 *
 * KEYBOARD AND VOICEOVER: a toolbar, vertical, with a roving tabindex - one tab stop; Up and Down move between the
 * entries drawn, Home and End to the ends, Enter or Space jumps. Each entry says where it goes ("Jump to A", "Jump to
 * numbers and symbols", "Jump to the 1990s"). Nothing here plays.
 */
export function ShelfIndex({ entries, years, onJump }: {
  entries: readonly IndexEntry[]
  /** the decades' strip, a little wider */
  years: boolean
  onJump: (group: number) => void
}) {
  const strip = useRef<HTMLDivElement>(null)
  const [slots, setSlots] = useState(entries.length)
  const [focus, setFocus] = useState(0)
  const dragging = useRef<number | null>(null)
  const last = useRef<number | null>(null)
  const frame = useRef<number | null>(null)
  const pending = useRef<number | null>(null)
  //? the drawn slots and their extent at pointerdown, read for the whole press
  const held = useRef<{ top: number; height: number; slots: readonly IndexSlot[] } | null>(null)
  //? a pointerdown jumped, so the click its pointerup leaves is let go
  const pressed = useRef(false)

  //? how many entries fit: the strip's height over an entry's least height
  useLayoutEffect(() => {
    const element = strip.current
    if (!element) return
    const measure = () => {
      const least = parseFloat(getComputedStyle(element).getPropertyValue('--app-index-entry')) || ENTRY_FALLBACK_PX
      const height = element.clientHeight
      if (height > 0) setSlots(Math.max(1, Math.floor(height / least)))
    }
    measure()
    if (typeof ResizeObserver === 'function') {
      const watching = new ResizeObserver(measure)
      watching.observe(element)
      return () => watching.disconnect()
    }
    window.addEventListener('resize', measure)
    return () => window.removeEventListener('resize', measure)
  }, [])

  useEffect(() => () => {
    if (frame.current !== null && typeof cancelAnimationFrame === 'function') cancelAnimationFrame(frame.current)
  }, [])

  const drawn = fitIndex(entries, slots)
  const kept = drawn.flatMap((slot) => (slot.kind === 'entry' ? [slot.at] : []))
  const focused = kept.includes(focus) ? focus : kept[0] ?? 0

  const leapTo = (at: number) => {
    const entry = entries[at]
    if (entry) onJump(entry.group)
  }

  //? the drawn slots' extent: the first slot's top to the last's bottom - the strip centres them in its own box
  const extent = (): { top: number; height: number; slots: readonly IndexSlot[] } | null => {
    const first = strip.current?.firstElementChild
    const end = strip.current?.lastElementChild
    if (!first || !end) return null
    const top = first.getBoundingClientRect().top
    const height = end.getBoundingClientRect().bottom - top
    return height > 0 ? { top, height, slots: drawn } : null
  }

  //? the entry under the finger, by its position over the drawn slots as they were at pointerdown
  const under = (event: PointerEvent): number | null => {
    const box = held.current
    return box ? entryAt(box.slots, event.clientY, box.top, box.height) : null
  }

  const pointerDown = (event: PointerEvent) => {
    held.current = extent()
    const at = under(event)
    if (at === null) return
    dragging.current = event.pointerId
    pressed.current = true
    try {
      strip.current?.setPointerCapture(event.pointerId)
    } catch {
      //? a pointer the page can't capture still jumps
    }
    last.current = at
    leapTo(at)
  }

  const pointerMove = (event: PointerEvent) => {
    if (dragging.current !== event.pointerId) return
    const at = under(event)
    if (at === null || at === last.current) return
    last.current = at
    pending.current = at
    if (frame.current !== null) return
    if (typeof requestAnimationFrame !== 'function') {
      leapTo(at)
      return
    }
    frame.current = requestAnimationFrame(() => {
      frame.current = null
      if (pending.current !== null) leapTo(pending.current)
      pending.current = null
    })
  }

  const letGo = (event: PointerEvent) => {
    if (dragging.current !== event.pointerId) return
    dragging.current = null
    //? a cancelled press leaves no click to let go
    if (event.type === 'pointercancel') pressed.current = false
    try {
      strip.current?.releasePointerCapture(event.pointerId)
    } catch {
      //? already let go
    }
  }

  const keyDown = (event: KeyboardEvent) => {
    const place = kept.indexOf(focused)
    const to =
      event.key === 'ArrowDown' ? kept[Math.min(kept.length - 1, place + 1)]
        : event.key === 'ArrowUp' ? kept[Math.max(0, place - 1)]
          : event.key === 'Home' ? kept[0]
            : event.key === 'End' ? kept[kept.length - 1]
              : undefined
    if (to === undefined) return
    pressed.current = false
    event.preventDefault()
    setFocus(to)
    strip.current?.querySelector<HTMLElement>(`[data-entry="${to}"]`)?.focus({ preventScroll: true })
  }

  return (
    <div
      ref={strip}
      class={`app-index${years ? ' is-years' : ''}`}
      role="toolbar"
      aria-label="Jump to"
      aria-orientation="vertical"
      onPointerDown={pointerDown}
      onPointerMove={pointerMove}
      onPointerUp={letGo}
      onPointerCancel={letGo}
      onKeyDown={keyDown}
      onClick={() => {
        //? after the button's own: whatever this click was, the press it followed is done with
        pressed.current = false
      }}
    >
      {drawn.map((slot, place) =>
        slot.kind === 'entry' ? (
          <button
            key={`e${slot.at}`}
            type="button"
            class="app-index-entry"
            data-entry={slot.at}
            tabIndex={slot.at === focused ? 0 : -1}
            aria-label={slot.entry.aria}
            onFocus={() => setFocus(slot.at)}
            onClick={(event) => {
              if (event.detail > 0 && pressed.current) return
              leapTo(slot.at)
            }}
          >
            {slot.entry.label}
          </button>
        ) : (
          <span key={`d${place}`} class="app-index-dot" aria-hidden="true">
            •
          </span>
        ),
      )}
    </div>
  )
}
