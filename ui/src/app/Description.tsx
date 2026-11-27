import { useLayoutEffect, useMemo, useRef, useState } from 'preact/hooks'

import { LESS, MORE, SOURCE_WORDS, type DescribeKind, type Description } from '../lib/describe'

//? each description's words their own id, for the button that opens them (a page stays mounted on each tab)
let described = 0

type Phase = 'words' | 'holding' | 'gone'

/** How tall the block is drawn, to the part of a pixel (offsetHeight rounds, and a block eased to a rounded height
 *  would settle that last part in a step) - null where nothing can be measured (the sims' stand-in for an element). */
function tall(element: HTMLElement | null): number | null {
  return element && typeof element.getBoundingClientRect === 'function' ? element.getBoundingClientRect().height : null
}

//? heights closer than this are the same height: nothing to ease
const SAME = 0.5

/**
 * The block's height eased from `from` to `to` (2.1.52): the room it held to the words' own height, or to nothing.
 * The numbers are measured, never chosen; how long and by what curve is app.css's (`[data-moving]`, a token). `gone`
 * is an end with nothing drawn - the page's own room around the block (an album page's padding over it, the artist
 * body's gap under it) closes or opens with it, so the block coming out of the page afterwards moves nothing.
 * Returns what ends it at once: the next change, or the page going.
 */
function ease(element: HTMLElement, from: number, to: number, gone: 'closing' | 'opening' | null, done?: () => void): () => void {
  element.setAttribute('data-easing', '')
  if (gone === 'opening') element.setAttribute('data-gone', '')
  element.style.height = `${from}px`
  //? the start laid out before the end is set, or there is nothing to ease between
  void element.offsetHeight
  element.setAttribute('data-moving', '')
  if (gone === 'closing') element.setAttribute('data-gone', '')
  else element.removeAttribute('data-gone')
  element.style.height = `${to}px`

  let over = false
  const finish = (settled: boolean) => {
    if (over) return
    over = true
    clearTimeout(timer)
    element.removeEventListener('transitionend', ended)
    //? closed to nothing, and about to leave the page: left closed until it has, or the page's own room around it
    //? would come back for a frame
    if (!(settled && gone === 'closing')) {
      for (const name of ['data-easing', 'data-moving', 'data-gone']) element.removeAttribute(name)
      element.style.height = ''
    }
    if (settled) done?.()
  }
  const ended = (event: TransitionEvent) => {
    if (event.target === element && event.propertyName === 'height') finish(true)
  }
  element.addEventListener('transitionend', ended)
  //? a transition that never says it ended - none under reduced motion, a pane the browser has frozen - ends by the
  //? clock, a moment after it was due
  const due = parseFloat(getComputedStyle(element).transitionDuration) * 1000
  const timer = setTimeout(() => finish(true), (Number.isFinite(due) ? due : 0) + 80)
  return () => finish(false)
}

/**
 * (2.0.13) A short description - an artist's paragraph under their Play row, an album's subtitle and paragraph under
 * its hero. Its words are TEXT, as deadwax sent them, never HTML. The subtitle (an album's - Wikidata's one line,
 * "1994 studio album by Portishead") first, a small line; the paragraph clamped to three lines (app.css
 * `.app-about-text.is-clamped`) with More / Less when it runs past them - a real button, its `aria-expanded` and
 * `aria-controls` saying what it opens; VoiceOver reads the words whole either way, since the clamp only hides what is
 * drawn. Under them, where they came from - "From Wikipedia", "More on Last.fm" - a link opening beside the app (a
 * link followed in the page would unload the player).
 *
 * Whether the words run past three lines is measured once drawn, and again as the page's width changes (a
 * phone turned, the Edit panel opening beside a desktop's page) - a ResizeObserver where there is one, the
 * window's resize otherwise. While open, the last measure stands. Opened is for THESE words: the block drawn for
 * another artist or album (the page component kept, its subject changed) starts clamped again.
 *
 * (2.1.52) ALWAYS IN ITS ONE PLACE, AND NOTHING JUMPS - James: "sometimes the description is at the top and sometimes
 * at the bottom. Let's make it consistently at the top." The page draws this block there whatever it has, and the
 * block is one of three things:
 *  - the WORDS (`description`): drawn at once where an answer was kept; ones that land after the block was first drawn
 *    fade in (`is-arriving`; no fade under reduced motion);
 *  - the ROOM (`holding`, no words yet - lib/describe.ts holdsRoom): empty, as tall as the block usually is - an
 *    album's subtitle line, the clamp's lines, and the line More and the source sit on (app.css `.app-about-room`) -
 *    so what is under it is drawn where it will stay;
 *  - NOTHING: no description. Drawn so from the first frame it is simply absent; reached from the room, the room
 *    closes once, eased, and the block then leaves the page.
 * Words that are not the room's height (two lines, no link, a subtitle run onto a second line) ease to their own
 * from it, the same way. Only a change after the first drawing is eased: a page come back to draws as it was.
 */
export function DescriptionBlock({ kind, description, holding }: { kind: DescribeKind; description: Description | null; holding: boolean }) {
  const paragraph = description?.paragraph ?? null
  const text = paragraph?.text ?? null
  const [openFor, setOpenFor] = useState<string | null>(null)
  const open = text !== null && openFor === text
  const [overflows, setOverflows] = useState(false)
  const words = useRef<HTMLParagraphElement | null>(null)
  const id = useMemo(() => `app-about-text-${++described}`, [])
  //? other words: closed again, whatever was open before
  useLayoutEffect(() => setOpenFor(null), [text])

  useLayoutEffect(() => {
    const element = words.current
    if (!element || open) return
    const measure = () => setOverflows(element.scrollHeight > element.clientHeight + 1)
    measure()
    if (typeof ResizeObserver === 'function') {
      const watching = new ResizeObserver(measure)
      watching.observe(element)
      return () => watching.disconnect()
    }
    if (typeof window === 'undefined') return
    window.addEventListener('resize', measure)
    return () => window.removeEventListener('resize', measure)
  }, [text, open])

  const phase: Phase = description ? 'words' : holding ? 'holding' : 'gone'
  const box = useRef<HTMLDivElement | null>(null)
  //? the block as it was last drawn: what, and how tall - what a change is eased from
  const was = useRef<{ phase: Phase; height: number }>({ phase, height: 0 })
  const easing = useRef(false)
  //? the room still closing: the block stays in the page until it has
  const [leaving, setLeaving] = useState(false)
  const [, redraw] = useState(0)
  //? words that weren't there as the block was first drawn fade in
  const arriving = useRef(false)
  if (phase !== 'words') arriving.current = true

  useLayoutEffect(() => {
    const before = was.current
    const element = box.current
    const height = tall(element)
    was.current = { phase, height: phase === 'gone' ? 0 : height ?? 0 }
    if (before.phase === phase) return
    const eased = (from: number, to: number, gone: 'closing' | 'opening' | null, done?: () => void) => {
      easing.current = true
      const stop = ease(element!, from, to, gone, () => {
        easing.current = false
        done?.()
      })
      return () => {
        easing.current = false
        stop()
      }
    }
    if (phase === 'gone') {
      if (element && height !== null && before.height >= SAME) {
        setLeaving(true)
        return eased(before.height, 0, 'closing', () => setLeaving(false))
      }
      //? nothing to ease: drawn again, without it
      setLeaving(false)
      redraw((n) => n + 1)
      return
    }
    setLeaving(false)
    if (!element || height === null || Math.abs(before.height - height) < SAME) return
    //? drawn before, yet measured as nothing: it was out of sight then (its tab's pane hidden), and how tall it
    //? stood isn't known - set to its new height at once rather than eased from a height it never had
    if (before.phase !== 'gone' && before.height < SAME) return
    return eased(before.height, height, before.phase === 'gone' ? 'opening' : null)
  }, [phase])

  //? ...and how tall it is now, whatever changed it since (More, Less, the page's width) - after the change above
  //? has read how tall it WAS
  useLayoutEffect(() => {
    const height = tall(box.current)
    if (height !== null && !easing.current && phase !== 'gone') was.current.height = height
  })

  if (phase === 'gone') {
    //? the room closing (this drawing is the first without it, or the close is under way): empty, still in the page
    if (was.current.phase === 'gone' && !leaving) return null
    return <div ref={box} class={`app-about is-${kind}`} aria-hidden="true" />
  }

  if (phase === 'holding') {
    return (
      <div ref={box} class={`app-about is-${kind} is-holding`} aria-hidden="true">
        <div class="app-about-room" />
      </div>
    )
  }

  return (
    <div ref={box} class={`app-about is-${kind}${arriving.current ? ' is-arriving' : ''}`}>
      {description!.subtitle && (
        <p class="app-about-subtitle" dir="auto">
          {description!.subtitle}
        </p>
      )}
      {paragraph && (
        <p ref={words} id={id} class={`app-about-text${open ? '' : ' is-clamped'}`} dir="auto">
          {paragraph.text}
        </p>
      )}
      {paragraph && ((overflows || open) || paragraph.url) && (
        <div class="app-about-foot">
          {(overflows || open) && (
            <button
              type="button"
              class="app-text-button app-about-more"
              aria-expanded={open}
              aria-controls={id}
              onClick={() => setOpenFor(open ? null : text)}
            >
              {open ? LESS : MORE}
            </button>
          )}
          {paragraph.url && (
            <a class="app-about-source" href={paragraph.url} target="_blank" rel="noopener">
              {SOURCE_WORDS[paragraph.source]}
            </a>
          )}
        </div>
      )}
    </div>
  )
}
