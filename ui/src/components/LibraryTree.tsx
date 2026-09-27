import { useEffect, useRef } from 'preact/hooks'

import type { MetadataIssueType } from '../api/types'
import { trackTime } from '../lib/format'
import { editionName, folderSummary } from '../lib/groupAlbums'
import type { TreeRow } from '../lib/libraryTree'
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
 */
export function LibraryTree(
  { rows, selected, focusToken, revealToken, issueTypes, onActivate, onSelect, onToggle }: Props,
) {
  const treeRef = useRef<HTMLDivElement>(null)

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
    <div ref={treeRef} class="library-tree" role="tree" aria-label="Library" onKeyDown={onKeyDown}>
      {rows.map((row) =>
        row.kind === 'heading' ? (
          //? Explorer's group header: "1979", "September 2026", "T"
          <div key={`heading\u0000${row.label}`} class="tree-heading" role="presentation">
            {row.label}
          </div>
        ) : row.kind === 'disc' ? (
          <div
            key={`${row.parent}\u0000disc${row.disc}`}
            class="tree-disc"
            role="presentation"
            style={`--tree-level:${row.level}`}
          >
            Disc {row.disc}
          </div>
        ) : (
          <TreeItem
            key={row.id}
            row={row}
            selected={row.id === selected}
            tabbable={row.id === tabStop}
            issueTypes={issueTypes}
            onActivate={onActivate}
            onToggle={onToggle}
          />
        ),
      )}
    </div>
  )
}

function TreeItem(
  { row, selected, tabbable, issueTypes, onActivate, onToggle }:
  {
    row: NodeRow
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
      aria-expanded={openable ? open : undefined}
      aria-selected={selected}
      tabIndex={tabbable ? 0 : -1}
      data-node={row.id}
      class={`tree-row tree-${row.kind}${selected ? ' is-selected' : ''}${
        row.kind === 'track' && row.match ? ' is-match' : ''
      }`}
      style={`--tree-level:${row.level}`}
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
