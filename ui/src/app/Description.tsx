import { useLayoutEffect, useMemo, useRef, useState } from 'preact/hooks'

import { LESS, MORE, SOURCE_WORDS, type DescribePlace, type Description } from '../lib/describe'

//? each description's words their own id, for the button that opens them (a page stays mounted on each tab)
let described = 0

/**
 * (2.0.13) A short description - an artist's paragraph under their Play row, an album's subtitle and paragraph under
 * its hero (lib/describe.ts says where, and why it is sometimes at the foot instead). Its words are TEXT, as deadwax
 * sent them, never HTML. The subtitle (an album's - Wikidata's one line, "1994 studio album by Portishead") first, a
 * small line; the paragraph clamped to three lines (app.css `.app-about-text.is-clamped`) with More / Less when it
 * runs past them - a real button, its `aria-expanded` and `aria-controls` saying what it opens; VoiceOver reads the
 * words whole either way, since the clamp only hides what is drawn. Under them, where they came from - "From
 * Wikipedia", "More on Last.fm" - a link opening beside the app (a link followed in the page would unload the player).
 *
 * Whether the words run past three lines is measured once drawn, and again as the page's width changes (a
 * phone turned, the Edit panel opening beside a desktop's page) - a ResizeObserver where there is one, the
 * window's resize otherwise. While open, the last measure stands. Opened is for THESE words: the block drawn for
 * another artist or album (the page component kept, its subject changed) starts clamped again.
 */
export function DescriptionBlock({ description, at }: { description: Description; at: DescribePlace }) {
  const paragraph = description.paragraph
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

  return (
    <div class={`app-about is-${at}`}>
      {description.subtitle && (
        <p class="app-about-subtitle" dir="auto">
          {description.subtitle}
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
