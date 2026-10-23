import type { JSX } from 'preact'
import { useEffect, useLayoutEffect, useMemo, useRef, useState } from 'preact/hooks'

import { blocks, blocksNear, type Block, type Group, type IndexEntry } from '../lib/shelves'
import { useFrame } from './useFrame'
import { ShelfIndex } from './ShelfIndex'

/** What a shelf holds: the albums' grid, or a list of rows (artists). */
export type ShelfKind = 'grid' | 'list'

interface Metrics {
  columns: number
  /** a row's height, its gap included */
  row: number
  /** a header's height, its margins included */
  head: number
  /** a block's own room besides its rows: the grid's padding, less the one row gap it doesn't have */
  extra: number
}

/** The first guesses, before a block has been measured on this frame: 2 columns on a phone, 6 on a desktop, a row
 *  as tall as --app-shelf-row-estimate (or --app-shelf-list-row-estimate for a list), a head as --app-shelf-head-estimate. */
const GUESS: Record<'phone' | 'desktop', number> = { phone: 2, desktop: 6 }
const FALLBACK_ROW_PX = 220
const FALLBACK_LIST_ROW_PX = 64
const FALLBACK_HEAD_PX = 40
/** How far past the view, either way, a block is drawn: a screen - as the IntersectionObserver's root margin, and as
 *  the window a new list draws before the observer has said (in screens). */
const NEAR_MARGIN = '100% 0px'
const NEAR_SCREENS = 1
/** How long an index jump keeps putting its header back at the top as the blocks near it are drawn (ms). */
const JUMP_SETTLES_MS = 700

//? measured once per frame and kind, and kept, so a shelf drawn again sizes its unseen blocks at once
const measured = new Map<string, Metrics>()

const token = (name: string, fallback: number) => {
  if (typeof document === 'undefined' || typeof getComputedStyle !== 'function') return fallback
  return parseFloat(getComputedStyle(document.documentElement).getPropertyValue(name)) || fallback
}

function guess(kind: ShelfKind, frame: 'phone' | 'desktop'): Metrics {
  return kind === 'grid'
    ? { columns: GUESS[frame], row: token('--app-shelf-row-estimate', FALLBACK_ROW_PX), head: token('--app-shelf-head-estimate', FALLBACK_HEAD_PX), extra: 0 }
    : { columns: 1, row: token('--app-shelf-list-row-estimate', FALLBACK_LIST_ROW_PX), head: token('--app-shelf-head-estimate', FALLBACK_HEAD_PX), extra: 0 }
}

const estimateOf = (block: Block<unknown>, metrics: Metrics) =>
  Math.round(Math.ceil(block.items.length / metrics.columns) * metrics.row + metrics.extra + (block.head !== null ? metrics.head : 0))

/**
 * The Library's shelf (2.0.0-player.59, a better Library): a whole list in BLOCKS of at most 60 (lib/shelves.ts
 * blocks), every block in the page with its header, and the tiles drawn only in the blocks near the view.
 *
 * WHY NEAR THE VIEW (the measurement, notes/app-library.md): drawn whole, 3,000 tiles in the page - even with the
 * browser skipping the layout and paint of what is off screen (`content-visibility: auto`) - took 2.8 s to open
 * Albums, 0.7-0.9 s to change the sort and 0.4-0.7 s a Find keystroke on a 4x-throttled Chromium: making 12,000 nodes
 * was the cost, not drawing them. So a block's tiles are made only while it is within a screen of the view
 * (an IntersectionObserver, NEAR_MARGIN), and a block drawn once and left keeps its real height as its place (until
 * the list changes); one holding the focus is never let go. A new list, sort or Find draws at once the blocks within
 * a screen of where the page is, by their estimates (blocksNear), and the observer corrects that. Each block is still
 * `section.app-shelf-block` with `content-visibility: auto`, and a drawn one carries `contain-intrinsic-block-size:
 * auto <estimate>px` inline (a computed size, as the main page's treeWindow's inline `top` was) - a block not drawn its height inline.
 *
 * A labelled group's first block opens with its header, `h2.app-shelf-head`, in the flow (not sticky) - every header
 * always in the page, the headings VoiceOver's rotor walks. A grid's block holds one `div.pl-grid`, so the columns,
 * gaps and padding are the grid's on both frames; a list's is a `ul.app-results.app-library-list`. Focus moving down
 * the tiles scrolls the page, and the blocks ahead are drawn a screen before they are reached.
 *
 * THE ESTIMATE is ceil(items / columns) × a row's height + the grid's own padding (less the last row's gap) + the
 * head: read from the first block drawn after its first paint (its grid's track count, a tile's height plus the row
 * gap), kept per frame and kind, and read again as the window's width changes; before that the tokens' guesses. A
 * close estimate is what lands an index jump on its header: a block between the top and the target is never drawn.
 *
 * THE INDEX (ShelfIndex), when `index` is given: beside the shelf in `div.app-shelf-wrap`'s second column, a jump
 * bringing the target group's header to the top - instantly, so a drag tracks the finger (html's scroll-padding-top
 * keeps it clear of a phone section page's bar), and again as the blocks around it are drawn, until a touch, a wheel
 * or a key of the page's own, or JUMP_SETTLES_MS. Nothing here plays.
 */
export function Shelf<T>({ kind, groups, index, years = false, item, itemKey }: {
  kind: ShelfKind
  groups: readonly Group<T>[]
  /** the index's entries, or null for none */
  index: readonly IndexEntry[] | null
  years?: boolean
  /** a grid's tile, keyed by the caller; a list's row's content (its `li` keyed by itemKey) */
  item: (value: T) => JSX.Element
  itemKey: (value: T) => string
}) {
  const frame = useFrame().frame
  const place = `${frame}:${kind}`
  const [metrics, setMetrics] = useState<Metrics>(() => measured.get(place) ?? guess(kind, frame))
  const shelf = useRef<HTMLDivElement>(null)
  const cut = useMemo(() => blocks(groups), [groups])
  const estimates = useMemo(() => cut.map((block) => estimateOf(block, metrics)), [cut, metrics])
  //? a block drawn once and let go: its real height, its place while it isn't drawn - for this list only
  const known = useRef(new Map<string, number>())
  //? a new list: the blocks within a screen of where the page is, by the estimates, until the observer says
  const first = useMemo(() => {
    known.current = new Map()
    const element = shelf.current
    const top = element && element.getClientRects().length ? element.getBoundingClientRect().top : 0
    const screen = typeof window === 'undefined' ? 1000 : window.innerHeight
    const [start, end] = blocksNear(estimates, -top - NEAR_SCREENS * screen, -top + (1 + NEAR_SCREENS) * screen)
    return new Set(cut.slice(start, end).map((block) => block.key))
  }, [cut])
  const [near, setNear] = useState<{ cut: readonly Block<T>[]; keys: ReadonlySet<string> }>(() => ({ cut, keys: first }))
  const keys = near.cut === cut ? near.keys : first
  const keysNow = useRef(keys)
  keysNow.current = keys

  //? a block measured after its first paint (an effect runs once the frame is painted) - and again as the window's
  //? width changes, which also lets go of the heights kept (a block's height is its width's)
  useEffect(() => {
    const kept = measured.get(place)
    if (kept) setMetrics(kept)
    const measure = () => {
      const element = shelf.current
      if (!element || element.getClientRects().length === 0) return
      const body = element.querySelector<HTMLElement>(kind === 'grid' ? '.app-shelf-block .pl-grid' : '.app-shelf-block .app-library-list')
      const tile = body?.firstElementChild as HTMLElement | null | undefined
      if (!body || !tile) return
      const style = getComputedStyle(body)
      const columns = kind === 'grid' ? Math.max(1, style.gridTemplateColumns.split(' ').filter(Boolean).length) : 1
      const gap = kind === 'grid' ? parseFloat(style.rowGap) || 0 : 0
      const head = element.querySelector<HTMLElement>('.app-shelf-head')
      const headStyle = head ? getComputedStyle(head) : null
      const next: Metrics = {
        columns,
        row: tile.offsetHeight + gap,
        extra: (parseFloat(style.paddingTop) || 0) + (parseFloat(style.paddingBottom) || 0) - gap,
        head: head && headStyle ? head.offsetHeight + (parseFloat(headStyle.marginTop) || 0) + (parseFloat(headStyle.marginBottom) || 0) : guess(kind, frame).head,
      }
      if (next.row <= 0) return
      measured.set(place, next)
      setMetrics((was) => (was.columns === next.columns && was.row === next.row && was.head === next.head && was.extra === next.extra ? was : next))
    }
    const resized = () => {
      known.current = new Map()
      measure()
    }
    measure()
    window.addEventListener('resize', resized)
    return () => window.removeEventListener('resize', resized)
  }, [place, cut.length > 0])

  //? which blocks are near the view: the observer's word, block by block - nothing changed while the shelf isn't
  //? drawn (a desktop's hidden view, a phone's section under a page), so coming back to it finds its tiles
  useEffect(() => {
    const element = shelf.current
    if (!element) return
    if (typeof IntersectionObserver !== 'function') {
      setNear({ cut, keys: new Set(cut.map((block) => block.key)) })
      return
    }
    const watching = new IntersectionObserver((entries) => {
      if (element.getClientRects().length === 0) return
      const wanted = new Set(keysNow.current)
      for (const entry of entries) {
        const key = (entry.target as HTMLElement).dataset.block
        if (!key) continue
        if (entry.isIntersecting) wanted.add(key)
        else if (wanted.has(key) && !entry.target.contains(document.activeElement)) {
          known.current.set(key, entry.boundingClientRect.height)
          wanted.delete(key)
        }
      }
      const was = keysNow.current
      if (wanted.size !== was.size || Array.from(wanted).some((key) => !was.has(key))) setNear({ cut, keys: wanted })
    }, { rootMargin: NEAR_MARGIN })
    for (const child of Array.from(element.children)) watching.observe(child)
    return () => watching.disconnect()
  }, [cut])

  //? each block's tiles made once for this list and this tile - so drawing one more block leaves the rest alone
  const bodies = useMemo(() => new Map<Block<T>, JSX.Element>(), [cut, item, itemKey, kind])
  const body = (block: Block<T>) => {
    let made = bodies.get(block)
    if (!made) {
      made = kind === 'grid'
        ? <div class="pl-grid">{block.items.map(item)}</div>
        : <ul class="app-results app-library-list">{block.items.map((value) => <li key={itemKey(value)}>{item(value)}</li>)}</ul>
      bodies.set(block, made)
    }
    return made
  }

  const drawn = cut.map((block, at) => {
    const on = keys.has(block.key)
    return (
      <section
        key={block.key}
        data-block={block.key}
        class="app-shelf-block"
        style={on ? { containIntrinsicBlockSize: `auto ${estimates[at]}px` } : { height: `${known.current.get(block.key) ?? estimates[at]}px` }}
      >
        {block.head !== null && (
          <h2 class="app-shelf-head" data-group={block.group}>
            {block.head}
          </h2>
        )}
        {on && body(block)}
      </section>
    )
  })

  //? an index jump: the header to the top, and again as the blocks near it are drawn - until the page is touched
  const jumping = useRef<{ group: number; until: number } | null>(null)
  const align = () => {
    const want = jumping.current
    if (!want || Date.now() > want.until) {
      jumping.current = null
      return
    }
    shelf.current?.querySelector<HTMLElement>(`.app-shelf-head[data-group="${want.group}"]`)?.scrollIntoView({ block: 'start' })
  }
  const jump = (group: number) => {
    jumping.current = { group, until: Date.now() + JUMP_SETTLES_MS }
    align()
  }
  useLayoutEffect(align, [keys])
  useEffect(() => {
    const stop = (event: Event) => {
      if (!(event.target as Element | null)?.closest?.('.app-index')) jumping.current = null
    }
    const events = ['touchstart', 'wheel', 'keydown', 'pointerdown'] as const
    for (const name of events) window.addEventListener(name, stop, { passive: true })
    return () => {
      for (const name of events) window.removeEventListener(name, stop)
    }
  }, [])

  return (
    <div class={`app-shelf-wrap${index ? ' has-index' : ''}${index && years ? ' is-years' : ''}`}>
      <div class="app-shelf-list" ref={shelf}>
        {drawn}
      </div>
      {index && index.length > 0 && <ShelfIndex entries={index} years={years} onJump={jump} />}
    </div>
  )
}
