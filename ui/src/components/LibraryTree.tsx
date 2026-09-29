import { useEffect, useLayoutEffect, useMemo, useRef, useState } from 'preact/hooks'

import type { MetadataIssueType } from '../api/types'
import { trackTime } from '../lib/format'
import { editionName, folderSummary } from '../lib/groupAlbums'
import type { TreeRow } from '../lib/libraryTree'
import { heightKey, rowOffsets, rowsToDraw, siblingPositions, visibleSpan } from '../lib/treeWindow'
import { isNewImport, outstandingIssues } from '../lib/metadataQueue'
import { AlbumArt, ArtistIcon, IssueChips } from './LibraryParts'

export type NodeRow = Exclude<TreeRow, { kind: 'disc' } | { kind: 'heading' }>
type OpenableRow = Extract<TreeRow, { open: boolean }>

const isOpenable = (row: TreeRow): row is OpenableRow =>
  row.kind === 'artist' || row.kind === 'group' || row.kind === 'edition'

interface Props {
  rows: TreeRow[]
  selected: string | null
  /** Bumped when the keyboard moved the selection, so focus follows it. */
  focusToken: number
  /**
   * Bumped when the details pane selected something, so the tree scrolls to it WITHOUT taking
   * focus - clicking a track in the table must not yank the keyboard out of the table.
   */
  revealToken: number
  issueTypes: Record<string, MetadataIssueType>
  /** A click: select it, and open it if it opens. */
  onActivate: (row: NodeRow) => void
  /** The keyboard moved here. Selects without opening, as Explorer does. */
  onSelect: (id: string) => void
  onToggle: (id: string, open: boolean) => void
}

/**
 * The library as an Explorer-style tree: artists, their albums, an album's editions when you
 * hold more than one, and tracks.
 *
 * Drawn as ONE flat list of rows with an indent per level rather than as nested containers.
 * The keyboard walks a flat order anyway, and a flat list keeps every row one element deep -
 * `aria-level` carries the structure for assistive tech, which the ARIA tree pattern allows.
 *
 * Keyboard, as in Explorer: up and down move, right opens (or steps into what is open), left
 * closes (or steps out to the parent), Enter toggles, Home and End jump. Only the selected row
 * is in the tab order, so Tab moves past the tree in one press instead of through every row.
 *
 * Only the rows in view are drawn (v0.9.30), each placed at its own top inside a tree as tall as
 * all of them - see lib/treeWindow.ts. The selected row, the tab stop and the focused row are
 * drawn wherever they are, so focus survives scrolling and `scrollIntoView` still finds them.
 */
/** A row's height before one of its kind has been measured - --control-sm, which rows mostly are. */
const FALLBACK_ROW_HEIGHT = 24
/** How far past the edges of the view rows are drawn, so a fast scroll doesn't show gaps. */
const OVERSCAN_PX = 600
/** The last heights measured, so a tree mounted again starts right. */
let knownHeights: Record<string, number> = {}

export function LibraryTree(
  { rows, selected, focusToken, revealToken, issueTypes, onActivate, onSelect, onToggle }: Props,
) {
  const treeRef = useRef<HTMLDivElement>(null)

  //? each row kind's height as drawn, measured below; kept for the next mount too
  const [heights, setHeights] = useState<Record<string, number>>(knownHeights)
  //? the rows within OVERSCAN_PX of the view, [start, end)
  const [span, setSpan] = useState<[number, number]>([0, 0])
  const [focusedId, setFocusedId] = useState<string | null>(null)
  //? bumped when the tree's width changes, which can change what a row holds - so measure again
  const [, setMeasureToken] = useState(0)

  const offsets = useMemo(() => rowOffsets(rows, heights, FALLBACK_ROW_HEIGHT), [rows, heights])
  const positions = useMemo(() => siblingPositions(rows), [rows])
  const indexById = useMemo(() => {
    const byId = new Map<string, number>()
    rows.forEach((row, i) => row.id && byId.set(row.id, i))
    return byId
  }, [rows])

  const offsetsRef = useRef(offsets)
  offsetsRef.current = offsets

  //? which rows the scroller shows. The tree sits inside it, maybe below a status line, so the
  //? view is measured from the tree's own top - rects, since nothing here is transformed
  const updateSpan = () => {
    const tree = treeRef.current
    const scroller = tree?.parentElement
    if (!tree || !scroller) return
    const top = scroller.getBoundingClientRect().top - tree.getBoundingClientRect().top
    const next = visibleSpan(offsetsRef.current, top, scroller.clientHeight, OVERSCAN_PX)
    setSpan((current) => (current[0] === next[0] && current[1] === next[1] ? current : next))
  }

  //? a scroll event already comes at most once a frame; a resize, including the tab being shown
  useEffect(() => {
    const tree = treeRef.current
    const scroller = tree?.parentElement
    if (!tree || !scroller) return
    let width = scroller.clientWidth
    const observer = new ResizeObserver(() => {
      updateSpan()
      if (scroller.clientWidth !== width) {
        width = scroller.clientWidth
        setMeasureToken((n) => n + 1)
      }
    })
    const onFocusIn = (event: FocusEvent) => {
      const row = (event.target as HTMLElement).closest<HTMLElement>('[data-node]')
      setFocusedId(row?.dataset['node'] ?? null)
    }
    scroller.addEventListener('scroll', updateSpan, { passive: true })
    tree.addEventListener('focusin', onFocusIn)
    observer.observe(scroller)
    return () => {
      scroller.removeEventListener('scroll', updateSpan)
      tree.removeEventListener('focusin', onFocusIn)
      observer.disconnect()
    }
  }, [])

  //? the rows changed (a filter, something opened or closed): what's in view changed with them
  useLayoutEffect(updateSpan, [offsets])

  //? after every render: has a kind of row turned out another height than assumed? One row of
  //? each kind answers for all of them - labels never wrap, so rows of a kind don't differ.
  //? Fractional heights, because offsetHeight's rounding would add up over 12,000 rows.
  useLayoutEffect(() => {
    const tree = treeRef.current
    if (!tree) return
    let changed: Record<string, number> | null = null
    const seen = new Set<string>()
    for (const element of Array.from(tree.children) as HTMLElement[]) {
      const key = element.dataset['hkey']
      if (!key || seen.has(key)) continue
      seen.add(key)
      const height = element.getBoundingClientRect().height
      //? 0 while the library tab is hidden - nothing to learn from that
      if (height && Math.abs(height - (heights[key] ?? -1)) > 0.01) (changed ??= { ...heights })[key] = height
    }
    if (changed) {
      knownHeights = changed
      setHeights(changed)
    }
  })

  /*
   * Compared, not queried. Node ids carry a NUL - album group keys are built with one, see
   * groupAlbums - and CSS.escape() turns NUL into U+FFFD, as the CSS spec says it must. So a
   * `[data-node="..."]` selector for any album or track can never match, and focus silently
   * stayed on the row you left. Only artist ids escaped cleanly, which is why it half worked.
   */
  const find = (id: string | null) =>
    id
      ? [...(treeRef.current?.querySelectorAll<HTMLElement>('[data-node]') ?? [])]
          .find((row) => row.dataset['node'] === id)
      : undefined

  useEffect(() => {
    if (!focusToken) return
    const row = find(selected)
    row?.focus({ preventScroll: true })
    row?.scrollIntoView({ block: 'nearest' })
  }, [focusToken])

  useEffect(() => {
    if (revealToken) find(selected)?.scrollIntoView({ block: 'nearest' })
  }, [revealToken])

  const nodes = rows.filter((row): row is NodeRow => row.kind !== 'disc' && row.kind !== 'heading')
  const index = nodes.findIndex((row) => row.id === selected)
  //? when the selection has been filtered or collapsed out of view, the first row takes the tab
  //? stop instead - otherwise the tree would have none and be unreachable by keyboard
  const tabStop = index >= 0 ? selected : nodes[0]?.id ?? null

  const pinned = [selected, tabStop, focusedId].map((id) => (id ? indexById.get(id) ?? -1 : -1))
  const drawn = rowsToDraw(span, pinned, rows.length)

  const onKeyDown = (event: KeyboardEvent) => {
    const current = nodes[index]

    const moveTo = (position: number) => {
      const row = nodes[Math.max(0, Math.min(nodes.length - 1, position))]
      if (row) onSelect(row.id)
      event.preventDefault()
    }

    switch (event.key) {
      case 'ArrowDown':
        moveTo(index + 1)
        break
      case 'ArrowUp':
        moveTo(index < 0 ? 0 : index - 1)
        break
      case 'Home':
        moveTo(0)
        break
      case 'End':
        moveTo(nodes.length - 1)
        break
      case 'ArrowRight':
        if (!current) moveTo(0)
        else if (isOpenable(current) && !current.open) {
          onToggle(current.id, true)
          event.preventDefault()
        } else if (isOpenable(current)) moveTo(index + 1)
        break
      case 'ArrowLeft':
        if (current && isOpenable(current) && current.open) {
          onToggle(current.id, false)
          event.preventDefault()
        } else if (current?.parent) {
          onSelect(current.parent)
          event.preventDefault()
        }
        break
      case 'Enter':
        if (current && isOpenable(current)) {
          onToggle(current.id, !current.open)
          event.preventDefault()
        }
        break
    }
  }

  return (
    <div
      ref={treeRef}
      class="library-tree"
      role="tree"
      aria-label="Library"
      onKeyDown={onKeyDown}
      style={`height:${offsets[rows.length] ?? 0}px`}
    >
      {drawn.map((i) => {
        const row = rows[i]
        if (!row) return null
        const hkey = heightKey(row, i)
        const place = `top:${offsets[i] ?? 0}px`
        const { posinset, setsize } = positions[i] ?? { posinset: 0, setsize: 0 }
        return row.kind === 'heading' ? (
          //? Explorer's group header: "1979", "September 2026", "T"
          <div
            key={`heading\u0000${row.label}`}
            class={`tree-heading${i === 0 ? ' is-first' : ''}`}
            role="presentation"
            data-hkey={hkey}
            style={place}
          >
            {row.label}
          </div>
        ) : row.kind === 'disc' ? (
          <div
            key={`${row.parent}\u0000disc${row.disc}`}
            class="tree-disc"
            role="presentation"
            data-hkey={hkey}
            style={`--tree-level:${row.level};${place}`}
          >
            Disc {row.disc}
            {row.title && <span class="disc-title" title={row.title}> · {row.title}</span>}
          </div>
        ) : (
          <TreeItem
            key={row.id}
            row={row}
            place={place}
            hkey={hkey}
            posinset={posinset}
            setsize={setsize}
            selected={row.id === selected}
            tabbable={row.id === tabStop}
            issueTypes={issueTypes}
            onActivate={onActivate}
            onToggle={onToggle}
          />
        )
      })}
    </div>
  )
}

function TreeItem(
  { row, place, hkey, posinset, setsize, selected, tabbable, issueTypes, onActivate, onToggle }:
  {
    row: NodeRow
    /** `top:...px` - where the row sits in the tree (see lib/treeWindow.ts) */
    place: string
    hkey: string
    posinset: number
    setsize: number
    selected: boolean
    tabbable: boolean
    issueTypes: Record<string, MetadataIssueType>
    onActivate: (row: NodeRow) => void
    onToggle: (id: string, open: boolean) => void
  },
) {
  const openable = isOpenable(row)
  const open = openable ? row.open : false

  return (
    <div
      role="treeitem"
      aria-level={row.level}
      aria-posinset={posinset}
      aria-setsize={setsize}
      aria-expanded={openable ? open : undefined}
      aria-selected={selected}
      tabIndex={tabbable ? 0 : -1}
      data-node={row.id}
      data-hkey={hkey}
      class={`tree-row tree-${row.kind}${selected ? ' is-selected' : ''}${
        row.kind === 'track' && row.match ? ' is-match' : ''
      }`}
      style={`--tree-level:${row.level};${place}`}
      onClick={() => onActivate(row)}
      onDblClick={() => openable && onToggle(row.id, !open)}
    >
      {/*
        Explorer's own glyphs: a hollow triangle for closed, a filled corner for open. The
        twisty toggles WITHOUT selecting, as it does there - clicking the row selects and opens.
      */}
      <span
        class="tree-twisty"
        aria-hidden="true"
        onClick={(event) => {
          if (!openable) return
          event.stopPropagation()
          onToggle(row.id, !open)
        }}
      >
        {openable ? (open ? '◢' : '▷') : ''}
      </span>

      <RowContent row={row} issueTypes={issueTypes} />
    </div>
  )
}

function RowContent({ row, issueTypes }: { row: NodeRow; issueTypes: Record<string, MetadataIssueType> }) {
  switch (row.kind) {
    case 'artist': {
      const { node } = row
      return (
        <>
          <ArtistIcon />
          <span class="tree-label">{node.artist}</span>
          {node.hasNew && <span class="library-new-chip">New</span>}
          {node.needsAttention > 0 && (
            <span
              class="tree-attention"
              title={`${node.needsAttention} album(s) here need metadata`}
            >
              {node.needsAttention}
            </span>
          )}
          <span class="tree-count" title={`${node.groups.length} album(s)`}>{node.groups.length}</span>
        </>
      )
    }

    case 'group': {
      const { group } = row
      const multiple = group.editions.length > 1
      const only = group.editions[0]
      return (
        <>
          <AlbumArt album={group.artFrom} class="tree-art" />
          <span class="tree-label">{group.album}</span>
          {/* with no artist level above it, the row says whose album it is */}
          {row.withArtist && <span class="tree-byline">{group.artist}</span>}
          <span class="tree-year">{group.yearRange || group.year}</span>
          {/* the fact this library exists to show, on the row itself rather than behind it */}
          {multiple && (
            <span class="library-edition has-siblings" title={folderSummary(group.editions).title}>
              {folderSummary(group.editions).label}
            </span>
          )}
          {!multiple && only?.edition && <span class="library-edition">{only.edition}</span>}
          {group.editions.some(isNewImport) && <span class="library-new-chip">New</span>}
          <IssueChips issues={group.issues} types={issueTypes} max={1} />
        </>
      )
    }

    case 'edition': {
      const { album } = row
      return (
        <>
          <span class="tree-label">{editionName(album)}</span>
          <span class="tree-year">{album.year}</span>
          <span class="tree-meta">
            {album.track_count} trk · {album.formats.join('/').toUpperCase()}
          </span>
          {isNewImport(album) && <span class="library-new-chip">New</span>}
          <IssueChips issues={outstandingIssues(album)} types={issueTypes} max={1} />
        </>
      )
    }

    case 'track': {
      const { track } = row
      return (
        <>
          <span class="tree-number">
            {track.position === null ? '–' : String(track.position).padStart(2, '0')}
          </span>
          <span
            class={`tree-label${track.has_title_tag ? '' : ' is-untitled'}`}
            title={track.has_title_tag ? undefined : 'No title tag - this is the file name'}
          >
            {track.title}
          </span>
          <span class="tree-time">{trackTime(track.length)}</span>
        </>
      )
    }
  }
}
