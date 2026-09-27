/**
 * Which of the library tree's rows to draw (v0.9.30).
 *
 * The tree was drawn whole, and a broad filter opens everything it touches: 12,720 rows for a
 * song search on a thousand albums, about 340ms to build and lay out each time. Now only the rows
 * in view (and a margin either side) exist; the rest are space. Pure, so ui/test/tree.sim.cjs
 * can pin it - the component only measures and scrolls.
 *
 * Every row of a kind is one height - labels never wrap - so a height per KIND is measured on
 * screen and every row's top follows from those. That is what lets a row far down the list be
 * placed exactly without ever having been drawn.
 */
import type { TreeRow } from './libraryTree'

/** What a row's height depends on: its kind, and for a heading, whether it opens the list. */
export function heightKey(row: TreeRow, index: number): string {
  //? the first heading has less space above it (main.css .tree-heading.is-first)
  return row.kind === 'heading' && index === 0 ? 'heading-first' : row.kind
}

/**
 * Every row's top, and the whole height: `offsets[i]` is where row i starts and
 * `offsets[rows.length]` is the height of the tree. A kind not yet measured takes `fallback`.
 */
export function rowOffsets(
  rows: readonly TreeRow[],
  heights: Readonly<Record<string, number>>,
  fallback: number,
): Float64Array {
  const offsets = new Float64Array(rows.length + 1)
  let top = 0
  rows.forEach((row, i) => {
    top += heights[heightKey(row, i)] ?? fallback
    offsets[i + 1] = top
  })
  return offsets
}

/** The first row whose bottom is below `y` - rows before it end above y. */
function firstEndingBelow(offsets: Float64Array, y: number): number {
  let lo = 0
  let hi = offsets.length - 1
  while (lo < hi) {
    const mid = (lo + hi) >> 1
    if ((offsets[mid + 1] ?? Infinity) > y) hi = mid
    else lo = mid + 1
  }
  return lo
}

/**
 * The span of rows within `margin` px of the view, as [start, end). `top` is how far down the
 * tree the view begins and `height` how much of it shows.
 */
export function visibleSpan(
  offsets: Float64Array,
  top: number,
  height: number,
  margin: number,
): [number, number] {
  const count = offsets.length - 1
  if (count <= 0) return [0, 0]
  const start = firstEndingBelow(offsets, top - margin)
  let end = firstEndingBelow(offsets, top + height + margin)
  //? the row straddling the bottom edge is in view too
  if (end < count && (offsets[end] ?? Infinity) < top + height + margin) end += 1
  return [start, Math.max(start, Math.min(count, end))]
}

/**
 * The rows to draw, in order: the span, and the `pinned` rows wherever they are. A pinned row is
 * one that must exist whether or not it is in view - the selected row and the one with focus.
 * Unmount the focused row and the keyboard is left talking to nothing.
 */
export function rowsToDraw(span: [number, number], pinned: readonly number[], count: number): number[] {
  const [start, end] = span
  const extra = pinned.filter((i) => i >= 0 && i < count && (i < start || i >= end))
  const drawn: number[] = []
  for (let i = start; i < end; i++) drawn.push(i)
  if (!extra.length) return drawn
  return [...new Set([...drawn, ...extra])].sort((a, b) => a - b)
}

/**
 * Each node row's place among its siblings, for aria-posinset and aria-setsize. With most rows
 * not in the page, assistive tech can no longer count them itself. Headings and disc labels are
 * presentation, not tree items, and have none.
 */
export function siblingPositions(rows: readonly TreeRow[]): { posinset: number; setsize: number }[] {
  const counts = new Map<string | null, number>()
  const position: number[] = []
  for (const row of rows) {
    if (row.kind === 'heading' || row.kind === 'disc') {
      position.push(0)
      continue
    }
    const n = (counts.get(row.parent) ?? 0) + 1
    counts.set(row.parent, n)
    position.push(n)
  }
  return rows.map((row, i) => ({
    posinset: position[i] ?? 0,
    setsize: row.kind === 'heading' || row.kind === 'disc' ? 0 : counts.get(row.parent) ?? 0,
  }))
}
