import { useLayoutEffect, useMemo, useRef, useState } from 'preact/hooks'

import { useDismiss } from '../hooks/useDismiss'
import type { PressingRow, PressingsView } from '../lib/pressings'
import { CheckIcon, ChevronDownIcon } from '../player/icons'

/**
 * Which pressing the album-you-don't-have page shows (2.0.0-player.13), as Request.dc.html draws it:
 * a button saying the pressing ("Pressing" over "CD · 2008 · GB · Island"), opening a popover of the
 * album's pressings, each with a note of how it differs from the usual tracklist (amber when it
 * does), the chosen one ticked - and "N more pressings with the usual tracklist", which expands,
 * folding the identical ones away (lib/pressings.ts decides which show).
 *
 * A listbox: the button says so (`aria-haspopup`, `aria-expanded`), each pressing is an option with
 * `aria-selected`; opening puts focus on the chosen one, the arrows (and Home, End) move it. Escape
 * and a pick close it with focus back on the button; a tap outside (useDismiss) or Tab out of it
 * just closes it, focus left where it went. The expander sits outside the listbox, since only
 * options belong in one.
 *
 * FOCUS GOING NOWHERE IS NOT FOCUS LEAVING (review). WebKit - Safari, and every browser on an iPhone
 * - focuses no tapped button without a tabindex: a press on "N more" or on the Pressing button
 * blurs the option that had focus with no relatedTarget, and Preact re-renders before the click, so
 * closing on that hid the list under the finger - "N more" could never expand, and the Pressing
 * button closed the list on its press and opened it again on its click. A focusout with no
 * relatedTarget is ignored (a tap outside is useDismiss's to judge), and the expander takes
 * tabIndex -1 so a tap on it keeps focus inside, as the options' does. Chromium blurs a focused
 * element as it is removed, with no relatedTarget either: the expander going as it expands.
 *
 * OPENING BRINGS THE LIST INTO VIEW (review): it opens downward, and on a phone with the mini player
 * up most of it sat under the mini player and the tab bar, the chosen option focused out of sight
 * (`preventScroll`). It is capped to the band between the page's bars (app.css), the chosen option
 * scrolled into the list's own view, then the list into the page's - `scrollIntoView` honours the
 * page's scroll-padding, which already clears the bars.
 *
 * A leaf: what it shows and what a pick does come from the page.
 */
//? each picker's list its own id: a page stays mounted on each tab it was opened on
let pickers = 0

export function PressingPicker({ view, onPick }: { view: PressingsView; onPick: (id: string) => void }) {
  const listId = useMemo(() => `app-pressings-${++pickers}`, [])
  const [open, setOpen] = useState(false)
  const [expanded, setExpanded] = useState(false)
  const root = useRef<HTMLDivElement>(null)
  const button = useRef<HTMLButtonElement>(null)
  const list = useRef<HTMLDivElement>(null)
  const popover = useRef<HTMLDivElement>(null)

  const close = (focus = true) => {
    setOpen(false)
    if (focus) button.current?.focus()
  }
  useDismiss(root, open, () => close(false))

  const all = [...view.shown, ...view.more]
  const chosen = all.find((row) => row.id === view.chosenId) ?? null
  const rows: PressingRow[] = expanded ? all : view.shown

  //? as it opens: focus to the chosen pressing (or the first), so the arrows start from there, and
  //? the list - the chosen one in it - brought into view
  useLayoutEffect(() => {
    if (!open) return
    const options = [...(list.current?.querySelectorAll<HTMLElement>('[role="option"]') ?? [])]
    const target = options.find((option) => option.getAttribute('aria-selected') === 'true') ?? options[0]
    target?.focus({ preventScroll: true })
    reveal(target)
  }, [open])

  //? "N more" opened: the button that said so is gone, so focus goes to the first pressing it showed
  useLayoutEffect(() => {
    if (!expanded || !open) return
    const target = list.current?.querySelectorAll<HTMLElement>('[role="option"]')[view.shown.length]
    target?.focus({ preventScroll: true })
    reveal(target)
  }, [expanded])

  /** An option in the list's own view, then the whole list in the page's, clear of its bars. */
  function reveal(option: HTMLElement | undefined) {
    const box = popover.current
    if (!box || typeof box.scrollIntoView !== 'function') return
    if (option) {
      const top = option.offsetTop
      const bottom = top + option.offsetHeight
      if (top < box.scrollTop) box.scrollTop = top
      else if (bottom > box.scrollTop + box.clientHeight) box.scrollTop = bottom - box.clientHeight
    }
    box.scrollIntoView({ block: 'nearest' })
  }

  const onKeyDown = (event: KeyboardEvent) => {
    if (event.key === 'Escape') {
      event.preventDefault()
      close()
      return
    }
    const options = [...(root.current?.querySelectorAll<HTMLElement>('[role="option"], .app-picker-more') ?? [])]
    const at = options.indexOf(document.activeElement as HTMLElement)
    const to = event.key === 'ArrowDown' ? at + 1 : event.key === 'ArrowUp' ? at - 1
      : event.key === 'Home' ? 0 : event.key === 'End' ? options.length - 1 : null
    if (to === null || !options.length) return
    event.preventDefault()
    options[Math.max(0, Math.min(options.length - 1, to))]?.focus()
  }

  const pick = (id: string) => {
    onPick(id)
    close()
  }

  return (
    <div
      class="app-picker"
      ref={root}
      onKeyDown={open ? onKeyDown : undefined}
      //? Tab out of the list closes it, as a tap outside does - but focus going NOWHERE (no
      //? relatedTarget: WebKit's tap on a button, a focused element removed) is not leaving it
      onFocusOut={open ? (event: FocusEvent) => {
        const to = event.relatedTarget as Node | null
        if (to && !root.current?.contains(to)) close(false)
      } : undefined}
    >
      <button
        ref={button}
        type="button"
        class="app-picker-button"
        aria-haspopup="listbox"
        aria-expanded={open}
        aria-controls={listId}
        onClick={() => setOpen((was) => !was)}
      >
        <span class="app-picker-text">
          <span class="app-picker-label">Pressing</span>
          <span class="app-picker-value">{chosen?.label ?? ''}</span>
        </span>
        <ChevronDownIcon class="app-picker-chevron" />
      </button>
      <div class="app-picker-popover" ref={popover} hidden={!open}>
        <div id={listId} ref={list} role="listbox" aria-label="Pressings">
          {rows.map((row) => {
            const selected = row.id === view.chosenId
            return (
              <button
                key={row.id}
                type="button"
                role="option"
                aria-selected={selected}
                tabIndex={-1}
                class={`app-picker-option${selected ? ' is-selected' : ''}`}
                onClick={() => pick(row.id)}
              >
                <CheckIcon class={`app-picker-tick${selected ? '' : ' is-off'}`} />
                <span class="app-picker-text">
                  <span class="app-picker-option-label">{row.label}</span>
                  <span class={`app-picker-note${row.kind === 'differs' ? ' is-differs' : ''}`}>{row.note}</span>
                </span>
              </button>
            )
          })}
        </div>
        {view.more.length > 0 && !expanded && (
          //? tabIndex -1, as the options: WebKit focuses a tapped button only with one, so a tap on
          //? it keeps focus inside the picker; the arrows reach it as they reach the options
          <button type="button" class="app-picker-more" tabIndex={-1} onClick={() => setExpanded(true)}>
            {view.more.length} more {view.more.length === 1 ? 'pressing' : 'pressings'} with the usual tracklist
          </button>
        )}
      </div>
    </div>
  )
}
