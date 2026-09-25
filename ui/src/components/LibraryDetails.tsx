import { Fragment, type ComponentChildren } from 'preact'
import { useEffect, useMemo, useRef, useState } from 'preact/hooks'

import * as libraryApi from '../api/library'
import type { LibraryAlbum, LibraryTrack, MetadataIssueType, TrackDetails, TrackLyrics } from '../api/types'
import type { TrackDetailsState } from '../hooks/useTrackDetails'
import { useTrackFields, type TrackFieldsState } from '../hooks/useTrackFields'
import { discArtUrl, formatAge, formatDuration, formatSize, trackPictureUrl, trackTime } from '../lib/format'
import type { AlbumGroup } from '../lib/groupAlbums'
import {
  editionNodeId, groupAddedAt, nodeIdForAlbum, trackNodeId, type Selected,
} from '../lib/libraryTree'
import { isNewImport, outstandingIssues } from '../lib/metadataQueue'
import { tickTracks } from '../lib/tagEdit'
import {
  clampWidth, columnLayout, fieldById, FIELD_GROUPS, isFlexible, TITLE_COLUMN, TRACK_FIELDS,
  visibleColumns, type TrackField, type TrackRow,
} from '../lib/trackFields'
import { ArtViewer, type ViewerImage } from './ArtViewer'
import { lyricTime } from '../lib/lyrics'
import { AlbumArt, CoverGrid, coverSources, GetArtButton, GetDiscArtButton, GetLyricsButton } from './LibraryParts'
import { Loading } from './Loading'
import { ArtistDetails } from './ArtistDetails'
import { TrackTagEditor } from './TrackTagEditor'

export interface LibrarySummary {
  albums: number
  artists: number
  tracks: number
  size: number
  duration: number
  libraryPath: string
  scannedAt: number | null
  stale: boolean
}

interface Props {
  selected: Selected
  selectedId: string | null
  /** The selected album's files, read live. */
  details: TrackDetailsState
  issueTypes: Record<string, MetadataIssueType>
  /** Every album, for the overview's "recently changed" shelf. */
  groups: readonly AlbumGroup[]
  summary: LibrarySummary
  onSelect: (id: string) => void
  onEdit: (album: LibraryAlbum) => void
  onDelete: (album: LibraryAlbum) => void
  onArtFetched: () => void
  /** a fetch wrote .lrc files, so the scan's lyrics count - and the track view - want a reload */
  onLyricsFetched: () => void
  /** a fetch wrote disc art, which the scan lists, so it wants a reload */
  onDiscArtFetched: () => void
  /** After tags were edited by hand, so the library reloads what changed. */
  onTagsEdited: () => void
  onSearchArtist: (artist: string) => void
  onSearchAlbum: (group: AlbumGroup) => void
  /** Phones only: the pane is a sheet over the tree there, and this closes it. */
  onBack: () => void
}

/** Tracks ticked for editing together. They belong to one album - see LibraryDetails. */
interface Ticked {
  album: string
  files: ReadonlySet<string>
  /** The last track clicked, which a shift-click runs from. */
  anchor: string | null
}

const NO_FILES: ReadonlySet<string> = new Set()
const NOTHING_TICKED: Ticked = { album: '', files: NO_FILES, anchor: null }

/**
 * The right-hand pane: whatever is selected in the tree, in detail.
 *
 * This is where the space went. The old list gave every album a full-width row whose middle was
 * empty; the tree now carries the navigating, and this pane spends the rest of the width on the
 * one thing you are looking at - its cover, its properties, what is wrong with it, and every
 * track with whichever fields you asked to see.
 *
 * Laid out like Explorer on purpose: a command bar across the top whose commands follow the
 * selection, and a details view below it whose columns are yours to choose, order and size.
 */
export function LibraryDetails(props: Props) {
  const { selected, selectedId, details, issueTypes, groups, summary } = props
  const layout = useTrackFields()
  const [menuOpen, setMenuOpen] = useState(false)
  const [viewing, setViewing] = useState<LibraryAlbum | null>(null)
  //? any other pictures opened full size - a track's embedded ones, an album's disc art
  const [viewingPictures, setViewingPictures] = useState<ViewerImage[] | null>(null)

  const album = selected.kind === 'album' || selected.kind === 'track' ? selected.album : null
  const group = selected.kind === 'group' || selected.kind === 'album' || selected.kind === 'track'
    ? selected.group
    : null

  //? a new selection starts at the top - landing halfway down an artist because the previous
  //? album's tracklist was scrolled would read as the pane showing the wrong thing
  const bodyRef = useRef<HTMLDivElement>(null)
  useEffect(() => bodyRef.current?.scrollTo({ top: 0 }), [selectedId])

  /*
   * Which tracks are ticked, for editing their tags together. They belong to one album: going
   * to another clears them, rather than carrying filenames across that mean nothing there - or
   * that name the same-numbered tracks of a different record.
   */
  const [ticked, setTicked] = useState<Ticked>(NOTHING_TICKED)
  const checked = album && ticked.album === album.path ? ticked.files : NO_FILES

  /*
   * The tag editor, and the files it is editing. The list is fixed when it opens rather than
   * read from the ticks, so its preview is never recomputed against a selection that changed
   * underneath it - and it closes when you go to a different album, whose files it can't see.
   */
  const [editingTags, setEditingTags] = useState<{ album: LibraryAlbum; filenames: string[] } | null>(null)

  useEffect(() => {
    setTicked(NOTHING_TICKED)
    setEditingTags((open) => (open && open.album.path === album?.path ? open : null))
  }, [album?.path])

  const tick = (filename: string, range: boolean) => {
    if (!album) return
    const order = album.tracks.map((track) => track.filename)
    setTicked((current) => {
      const mine = current.album === album.path
      return {
        album: album.path,
        ...tickTracks(order, mine ? current.files : NO_FILES, mine ? current.anchor : null, filename, range),
      }
    })
  }

  const tickAll = (on: boolean) => {
    if (!album) return
    setTicked({
      album: album.path,
      files: on ? new Set(album.tracks.map((track) => track.filename)) : NO_FILES,
      anchor: null,
    })
  }

  //? what Edit tags opens on: this track, the ticked ones, or - with none ticked - all of them
  const tagTargets = !album
    ? []
    : selected.kind === 'track'
      ? [selected.track.filename]
      : album.tracks.map((track) => track.filename).filter((name) => !checked.size || checked.has(name))

  const tagLabel = selected.kind === 'track'
    ? 'Edit tags…'
    : checked.size
      ? `Edit ${checked.size} track${checked.size === 1 ? '' : 's'}…`
      : 'Edit all tracks…'

  const body = (() => {
    switch (selected.kind) {
      case 'none':
        return <Overview summary={summary} groups={groups} onSelect={props.onSelect} />
      case 'artist':
        return (
          <ArtistDetails
            artist={selected.node.artist}
            groups={selected.node.groups}
            onSelect={props.onSelect}
          />
        )
      case 'group':
        return (
          <GroupDetails
            group={selected.group}
            issueTypes={issueTypes}
            onSelect={props.onSelect}
            onSearchArtist={props.onSearchArtist}
            onOpenArt={setViewing}
          />
        )
      case 'album':
        return (
          <AlbumDetails
            album={selected.album}
            group={selected.group}
            details={details}
            layout={layout}
            checked={checked}
            issueTypes={issueTypes}
            onTick={tick}
            onTickAll={tickAll}
            onSelect={props.onSelect}
            onSearchArtist={props.onSearchArtist}
            onOpenArt={setViewing}
            onViewPictures={setViewingPictures}
            onHeaderMenu={() => setMenuOpen(true)}
          />
        )
      case 'track':
        return (
          <TrackDetailsView
            album={selected.album}
            group={selected.group}
            track={selected.track}
            details={details}
            visible={layout.visible}
            onSelect={props.onSelect}
            onOpenArt={setViewing}
            onViewPictures={setViewingPictures}
          />
        )
    }
  })()

  return (
    <>
      <div class="details-commandbar" role="toolbar" aria-label="Commands">
        <button type="button" class="commandbar-button commandbar-back" onClick={props.onBack}>
          ‹ Library
        </button>

        {album && (
          <>
            <button
              type="button"
              class="commandbar-button"
              title="Match this album to a release and correct its tags"
              onClick={() => props.onEdit(album)}
            >
              Edit metadata…
            </button>
            <button
              type="button"
              class="commandbar-button"
              title={
                selected.kind === 'track'
                  ? "Change this track's tags by hand"
                  : checked.size
                    ? 'Change the tags of the ticked tracks by hand, all at once'
                    : 'Change the tags of every track here by hand, all at once. Tick tracks in '
                      + 'the list to edit only those.'
              }
              onClick={() => setEditingTags({ album, filenames: tagTargets })}
            >
              {tagLabel}
            </button>
            <GetArtButton album={album} onDone={props.onArtFetched} class="commandbar-button" />
            <GetLyricsButton album={album} onDone={props.onLyricsFetched} class="commandbar-button" />
            <GetDiscArtButton album={album} onDone={props.onDiscArtFetched} class="commandbar-button" />
          </>
        )}

        {group && (
          <button
            type="button"
            class="commandbar-button"
            title={`search MusicBrainz for ${group.album}`}
            onClick={() => props.onSearchAlbum(group)}
          >
            Find on MusicBrainz
          </button>
        )}

        {selected.kind === 'artist' && (
          <button
            type="button"
            class="commandbar-button"
            title={`search MusicBrainz for ${selected.node.artist}`}
            onClick={() => props.onSearchArtist(selected.node.artist)}
          >
            Find on MusicBrainz
          </button>
        )}

        {album && (
          <button
            type="button"
            class="commandbar-button is-danger"
            title={group && group.editions.length > 1
              ? 'Delete this edition from disk - the others stay'
              : 'Delete this album from disk'}
            onClick={() => props.onDelete(album)}
          >
            Delete…
          </button>
        )}

        <span class="commandbar-spacer" />

        {(selected.kind === 'album' || selected.kind === 'track') && (
          <div class="fields-control">
            <button
              type="button"
              class="commandbar-button"
              aria-expanded={menuOpen}
              aria-haspopup="menu"
              title="Choose which fields the track viewer shows"
              onClick={() => setMenuOpen((open) => !open)}
            >
              Fields ▾
            </button>
            {menuOpen && (
              <FieldsMenu
                visible={layout.visible}
                onToggle={layout.toggle}
                onReset={layout.reset}
                onClose={() => setMenuOpen(false)}
              />
            )}
          </div>
        )}
      </div>

      <div class="details-body scrollable" ref={bodyRef}>{body}</div>

      {viewing && (
        <ArtViewer
          images={[{
            label: viewing.album,
            sources: coverSources(viewing, 'full'),
            missing: 'No cover on disk, and none on the Cover Art Archive for this release',
          }]}
          onClose={() => setViewing(null)}
        />
      )}

      {viewingPictures && (
        <ArtViewer images={viewingPictures} onClose={() => setViewingPictures(null)} />
      )}

      {editingTags && (
        <TrackTagEditor
          album={editingTags.album}
          filenames={editingTags.filenames}
          details={details}
          onClose={() => setEditingTags(null)}
          onApplied={props.onTagsEdited}
        />
      )}
    </>
  )
}

/* ------------------------------------------------------------------ pieces */

/** Label / value pairs, Explorer's details-pane layout. A null value drops the row; '' reads —. */
function PropertyGrid({ rows }: { rows: [string, ComponentChildren][] }) {
  return (
    <dl class="property-grid">
      {rows.filter(([, value]) => value !== null && value !== undefined).map(([label, value]) => (
        <Fragment key={label}>
          <dt>{label}</dt>
          <dd>{value === '' ? <span class="text white-tertiary">—</span> : value}</dd>
        </Fragment>
      ))}
    </dl>
  )
}

/** A shelf of covers, Explorer's "large icons" view. Each opens its album in the tree. */

function IssueList(
  { album, issueTypes }: { album: LibraryAlbum; issueTypes: Record<string, MetadataIssueType> },
) {
  const issues = outstandingIssues(album)
  if (!issues.length && !album.ignored_issues.length) return null

  return (
    <div class="details-issues">
      {issues.map((code) => (
        <div class="details-issue" key={code}>
          <span class="library-issue-chip">{issueTypes[code]?.label ?? code}</span>
          <span class="text white-tertiary">{issueTypes[code]?.hint}</span>
        </div>
      ))}
      {album.ignored_issues.length > 0 && (
        <div class="details-issue text default-muted">
          {album.ignored_issues.length} issue(s) ignored on this album — the editor can un-ignore them
        </div>
      )}
    </div>
  )
}

/* ------------------------------------------------------------------ an album */

function AlbumDetails(
  {
    album, group, details, layout, checked, issueTypes, onTick, onTickAll, onSelect,
    onSearchArtist, onOpenArt, onViewPictures, onHeaderMenu,
  }:
  {
    album: LibraryAlbum
    group: AlbumGroup
    details: TrackDetailsState
    layout: TrackFieldsState
    checked: ReadonlySet<string>
    issueTypes: Record<string, MetadataIssueType>
    onTick: (filename: string, range: boolean) => void
    onTickAll: (on: boolean) => void
    onSelect: (id: string) => void
    onSearchArtist: (artist: string) => void
    onOpenArt: (album: LibraryAlbum) => void
    onViewPictures: (images: ViewerImage[]) => void
    onHeaderMenu: () => void
  },
) {
  const multiple = group.editions.length > 1

  //? which tracks carry their OWN picture, from the files as read now - a player shows it in
  //? place of the album's cover, so this is where a song's odd sleeve comes from
  const withPictures = details.files
    ? album.tracks.filter((track) => details.files?.get(track.filename)?.pictures.length).length
    : null
  const discArt = album.disc_art ?? []
  const facts = [
    album.original_year && album.original_year !== album.year
      ? `${album.original_year} (this press ${album.year})`
      : album.year,
    album.disc_count > 1 ? `${album.disc_count} discs` : '',
    `${album.track_count} track${album.track_count === 1 ? '' : 's'}`,
    formatDuration(album.duration),
    formatSize(album.total_size),
    album.formats.join(' / ').toUpperCase(),
  ].filter(Boolean)

  return (
    <section class="details-section">
      <div class="details-header">
        {/* the album's OWN art where it has some, so each edition shows its own sleeve */}
        <AlbumArt
          album={album.art || album.release_mbid ? album : group.artFrom}
          size="large"
          class="details-cover"
          onOpen={() => onOpenArt(album.art || album.release_mbid ? album : group.artFrom ?? album)}
        />

        <div class="details-heading">
          <h2 class="details-title">{album.album}</h2>
          <button
            type="button"
            class="library-link details-artist"
            title={`search MusicBrainz for ${album.artist}`}
            onClick={() => onSearchArtist(album.artist)}
          >
            {album.artist}
          </button>
          <div class="details-facts text default-muted">{facts.join(' · ')}</div>

          <div class="details-chips">
            {(multiple || album.edition) && (
              <span class={`library-edition${multiple ? ' has-siblings' : ''}`}>
                {album.edition || 'Standard'}
              </span>
            )}
            {isNewImport(album) && <span class="library-new-chip">New</span>}
          </div>

          {/* the other pressings, one click away, so comparing them doesn't mean going back to the tree */}
          {multiple && (
            <div class="details-editions" role="group" aria-label="Editions">
              {group.editions.map((edition) => (
                <button
                  key={edition.path}
                  type="button"
                  class={`details-edition-pill${edition.path === album.path ? ' is-current' : ''}`}
                  onClick={() => onSelect(editionNodeId(edition))}
                >
                  {edition.edition || 'Standard'}
                  <span class="text white-tertiary"> · {edition.track_count} trk</span>
                </button>
              ))}
            </div>
          )}
        </div>
      </div>

      <IssueList album={album} issueTypes={issueTypes} />

      <h3 class="details-subheading">
        Tracks
        {checked.size > 0 && (
          <span class="details-ticked text default-muted">
            {checked.size} ticked
            <button type="button" class="library-link" onClick={() => onTickAll(false)}>clear</button>
          </span>
        )}
        {details.loading && <Loading label="reading the files" />}
        {details.error && <span class="text yellow"> — {details.error}</span>}
      </h3>
      <TrackTable
        album={album}
        details={details}
        layout={layout}
        checked={checked}
        onTick={onTick}
        onTickAll={onTickAll}
        onSelect={onSelect}
        onHeaderMenu={onHeaderMenu}
      />

      <h3 class="details-subheading">Properties</h3>
      <PropertyGrid
        rows={[
          ['Album', album.album],
          ['Album artist', album.artist],
          ['Year', album.year],
          ['Original year', album.original_year],
          ['Edition', multiple || album.edition ? album.edition || 'Standard' : null],
          ['Discs', album.disc_count > 1 ? String(album.disc_count) : null],
          ['Lyrics', album.lyrics_count
            ? `${album.lyrics_count === album.track_count ? 'Every track' : `${album.lyrics_count} of ${album.track_count} tracks`}, as .lrc files`
            : 'None on disk'],
          ['CD art', discArt.length
            ? (
              <span class="details-disc-art">
                {discArt.map((name) => (
                  <button
                    key={name}
                    type="button"
                    class="details-disc-thumb"
                    title={`${name} - what players show for a song with a disc number. Click to view.`}
                    onClick={() => onViewPictures(discArt.map((file) => ({
                      label: file,
                      sources: [discArtUrl(album.path, file, album.modified_at)],
                    })))}
                  >
                    <img src={discArtUrl(album.path, name, album.modified_at)} alt={name} loading="lazy" />
                    <span>{name}</span>
                  </button>
                ))}
              </span>
            )
            : 'None on disk'],
          ['Embedded art', withPictures === null
            ? (details.loading ? '…' : null)
            : withPictures
              ? (withPictures === album.track_count
                ? 'Every track carries its own picture, which players show instead of the cover'
                : `${withPictures} of ${album.track_count} track${album.track_count === 1 ? '' : 's'} `
                  + `${withPictures === 1 ? 'carries its' : 'carry their'} own picture, which players show instead of the cover`)
              : 'None - every track shows the album\'s cover'],
          ['Cover', album.art === 'file'
            ? 'An image file in the folder'
            : album.art === 'embedded' ? 'Embedded in the audio' : 'None on disk'],
          ['Release', album.release_mbid
            ? (
              <a
                class="details-mbid"
                href={`https://musicbrainz.org/release/${album.release_mbid}`}
                target="_blank"
                rel="noreferrer"
              >
                {album.release_mbid}
              </a>
            )
            : <span class="text yellow">not tagged with a MusicBrainz release</span>],
          ['Folder', <span class="details-path">{album.path}</span>],
          ['First seen', album.first_seen
            ? `${new Date(album.first_seen).toLocaleDateString()}${album.imported ? ', filed by deadwax' : ''}`
            : null],
        ]}
      />
    </section>
  )
}

/** The tick-box column, drawn before every other and never moved or sized. */
const CHECK_COLUMN = '2.4em'

/**
 * Explorer's details view: one row per track, one column per field you chose - in the order you
 * dragged them into, at the widths you dragged them to - and a tick box on each row for editing
 * several tracks' tags at once.
 *
 * A plain click still opens the track, as it always has. Ctrl/Cmd-click and Shift-click tick
 * instead, the way they select in Explorer, and Space ticks the focused row.
 */
function TrackTable(
  { album, details, layout, checked, onTick, onTickAll, onSelect, onHeaderMenu }:
  {
    album: LibraryAlbum
    details: TrackDetailsState
    layout: TrackFieldsState
    checked: ReadonlySet<string>
    onTick: (filename: string, range: boolean) => void
    onTickAll: (on: boolean) => void
    onSelect: (id: string) => void
    onHeaderMenu: () => void
  },
) {
  const columns = visibleColumns(layout.order, layout.visible)
  //? The table is as wide as the pane, and no narrower than its columns' minimums - past that it
  //? scrolls sideways inside its own box rather than squeezing every column into an ellipsis.
  const { template, minWidth } = columnLayout(columns, layout.widths, [CHECK_COLUMN])
  const tableRef = useRef<HTMLDivElement>(null)

  //? a header being dragged, and where it would land: before that column, or last (null)
  const [moving, setMoving] = useState<{ id: string; before: string | null } | null>(null)

  const tickedCount = album.tracks.filter((track) => checked.has(track.filename)).length
  const all = tickedCount > 0 && tickedCount === album.tracks.length
  const some = tickedCount > 0 && !all

  const split = album.disc_count > 1
  let lastDisc: number | null = null

  /**
   * Drag a header sideways to move its column, as in Explorer.
   *
   * Nothing moves until the pointer has travelled a few pixels, so a click - or the start of a
   * right-click for the field menu - never rearranges anything. Where it would land is worked
   * out from the headers' midpoints, the way a list reorders under a drag.
   */
  const startMove = (event: PointerEvent, id: string) => {
    if (event.button !== 0) return
    const head = (event.currentTarget as HTMLElement).parentElement
    if (!head) return

    const startX = event.clientX
    let active = false
    let before: string | null = null
    let shown: string | null | undefined

    function move(e: PointerEvent) {
      if (!active && Math.abs(e.clientX - startX) < 5) return
      active = true

      //? the rect for POSITION is right here - nothing in this table is transformed
      const target = [...(head as HTMLElement).querySelectorAll<HTMLElement>('[data-column]')].find((cell) => {
        const rect = cell.getBoundingClientRect()
        return e.clientX < rect.left + rect.width / 2
      })
      before = target?.dataset['column'] ?? null

      //? a render only when the landing spot changes, not on every pixel of the drag
      if (before !== shown) {
        shown = before
        setMoving({ id, before })
      }
    }

    function stop() {
      window.removeEventListener('pointermove', move)
      window.removeEventListener('pointerup', drop)
      window.removeEventListener('pointercancel', stop)
      setMoving(null)
    }

    function drop() {
      stop()
      if (active) layout.move(id, before)
    }

    window.addEventListener('pointermove', move)
    window.addEventListener('pointerup', drop)
    window.addEventListener('pointercancel', stop)
  }

  /**
   * Drag a header's right edge to size its column, and have that edge stay under the cursor.
   *
   * Which means this column's LEFT edge must not move while the drag is in flight. It used to:
   * every flexible column shares the row's spare space, so widening this one took the space out
   * of the title to its left, the left edge travelled as far as the right edge did, and the
   * column stayed about the size it started while the whole table reflowed under the cursor.
   *
   * So the flexible columns to the LEFT are pinned to the width they are already drawn at, which
   * changes nothing on screen, and are committed along with the drag so the release doesn't
   * reflow either. Columns to the RIGHT still absorb, so the table goes on filling the pane
   * instead of running off the side of it - and when there are none to absorb, it scrolls.
   *
   * While dragging, the new template goes straight onto the table's style - one write a frame
   * rather than a render of every row - and the width is committed once, on release. Committing
   * renders the same template, so the release lands exactly where the drag left it.
   */
  const startResize = (event: PointerEvent, id: string) => {
    if (event.button !== 0) return
    //? the header's own pointerdown would otherwise start moving the column
    event.preventDefault()
    event.stopPropagation()

    const grip = event.currentTarget as HTMLElement
    const cell = grip.parentElement
    const head = cell?.parentElement
    const table = tableRef.current
    if (!cell || !head || !table) return

    grip.setPointerCapture(event.pointerId)
    grip.classList.add('is-active')

    //? read the ids off the cells rather than building a selector - see CLAUDE.md on CSS.escape
    const cells = new Map<string, HTMLElement>()
    for (const el of head.querySelectorAll<HTMLElement>('[data-column]')) {
      const key = el.dataset['column']
      if (key) cells.set(key, el)
    }

    const pinned: Record<string, number> = {}
    for (const columnId of columns.slice(0, columns.indexOf(id))) {
      const el = cells.get(columnId)
      //? SIZE from offsetWidth, not the rect - see CLAUDE.md on transformed boxes
      if (el && !layout.widths[columnId] && isFlexible(columnId)) pinned[columnId] = el.offsetWidth
    }

    const widths = { ...layout.widths, ...pinned }
    const rect = cell.getBoundingClientRect()
    //? POSITION from the rect, read once - the pins above are what keep it true all drag
    const left = rect.left
    //? where in the grip's 7px it was taken hold of, so the column can't jump on the first move
    const grab = rect.right - event.clientX
    const startWidth = cell.offsetWidth
    let width = startWidth

    function move(e: PointerEvent) {
      width = clampWidth(e.clientX + grab - left)
      const next = columnLayout(columns, { ...widths, [id]: width }, [CHECK_COLUMN])
      ;(table as HTMLElement).style.setProperty('--track-columns', next.template)
      ;(table as HTMLElement).style.minWidth = next.minWidth
    }

    function stop() {
      grip.removeEventListener('pointermove', move)
      grip.removeEventListener('pointerup', stop)
      grip.removeEventListener('pointercancel', stop)
      grip.classList.remove('is-active')
      if (width !== startWidth) layout.pin({ ...pinned, [id]: width })
    }

    grip.addEventListener('pointermove', move)
    grip.addEventListener('pointerup', stop)
    grip.addEventListener('pointercancel', stop)
  }

  const last = columns[columns.length - 1]

  return (
    <div class="track-table-scroll">
      <div
        ref={tableRef}
        class="track-table"
        role="grid"
        aria-label="Tracks"
        aria-multiselectable={true}
        style={`--track-columns:${template};min-width:${minWidth}`}
      >
        <div
          class={`track-table-head${moving ? ' is-moving' : ''}`}
          role="row"
          title="Drag a header to move its column, or its right edge to size it. Right-click to choose fields."
          onContextMenu={(event) => {
            event.preventDefault()
            onHeaderMenu()
          }}
        >
          <span role="columnheader" class="track-cell track-check">
            <input
              type="checkbox"
              aria-label={all ? 'Untick every track' : 'Tick every track'}
              title={all ? 'Untick every track' : 'Tick every track'}
              checked={all}
              ref={(box) => {
                if (box) box.indeterminate = some
              }}
              onChange={() => onTickAll(!all)}
            />
          </span>

          {columns.map((id) => {
            const field = id === TITLE_COLUMN ? undefined : fieldById(id)
            const label = field ? field.label : 'Title'
            const dragging = moving?.id === id
            const dropBefore = moving && !dragging && moving.before === id
            const dropAfter = moving && moving.before === null && id === last && !dragging

            return (
              <span
                key={id}
                role="columnheader"
                data-column={id}
                class={[
                  'track-cell',
                  'track-head-cell',
                  dragging ? 'is-dragging' : '',
                  dropBefore ? 'drop-before' : '',
                  dropAfter ? 'drop-after' : '',
                ].filter(Boolean).join(' ')}
                title={label === '#' ? 'Track number' : label}
                onPointerDown={(event) => startMove(event as unknown as PointerEvent, id)}
              >
                {label}
                <span
                  class="track-col-grip"
                  aria-hidden="true"
                  title="Drag to size this column · double-click to put it back"
                  onPointerDown={(event) => startResize(event as unknown as PointerEvent, id)}
                  onDblClick={(event) => {
                    event.stopPropagation()
                    layout.resize(id, null)
                  }}
                />
              </span>
            )
          })}
        </div>

        {album.tracks.map((track) => {
          const row: TrackRow = { track, details: details.files?.get(track.filename) }
          const isTicked = checked.has(track.filename)
          const title = row.details?.tags['title'] ?? track.title
          const disc = track.disc ?? 1
          const divider = split && disc !== lastDisc
          lastDisc = disc

          return (
            <Fragment key={track.filename}>
              {divider && <div class="track-table-disc" role="row">Disc {disc}</div>}
              <div
                role="row"
                aria-selected={isTicked}
                class={`track-table-row${isTicked ? ' is-ticked' : ''}`}
                tabIndex={0}
                //? a shift-click would otherwise start selecting the text of every row in between
                onMouseDown={(event) => { if (event.shiftKey) event.preventDefault() }}
                onClick={(event) => {
                  if (event.metaKey || event.ctrlKey || event.shiftKey) {
                    onTick(track.filename, event.shiftKey)
                    return
                  }
                  onSelect(trackNodeId(album, track))
                }}
                onKeyDown={(event) => {
                  if (event.key === 'Enter') onSelect(trackNodeId(album, track))
                  if (event.key === ' ') {
                    event.preventDefault()
                    onTick(track.filename, event.shiftKey)
                  }
                }}
              >
                {/* the whole cell is the target, not just the box, and it never opens the track */}
                <span
                  role="gridcell"
                  class="track-cell track-check"
                  onClick={(event) => {
                    event.stopPropagation()
                    onTick(track.filename, event.shiftKey)
                  }}
                >
                  <input type="checkbox" tabIndex={-1} checked={isTicked} aria-label={`Tick ${title}`} />
                </span>

                {columns.map((id) => {
                  if (id === TITLE_COLUMN) {
                    return (
                      <span
                        key={id}
                        role="gridcell"
                        class={`track-cell track-title${track.has_title_tag ? '' : ' is-untitled'}`}
                        title={track.has_title_tag ? title : 'No title tag - this is the file name'}
                      >
                        {title}
                      </span>
                    )
                  }
                  const field = fieldById(id)
                  return field ? <Cell key={id} field={field} row={row} pending={details.loading} /> : null
                })}
              </div>
            </Fragment>
          )
        })}
      </div>
    </div>
  )
}

function Cell({ field, row, pending }: { field: TrackField; row: TrackRow; pending: boolean }) {
  const value = field.value(row)
  //? a field only the file itself carries shows that it is still coming, rather than a blank
  //? that would read as "this track has no genre"
  const waiting = !value && !field.fromScan && !row.details && pending
  //? a default rather than a tag - dimmed, and saying why
  const inferred = value ? field.inferred?.(row) ?? null : null

  return (
    <span
      role="gridcell"
      class={[
        'track-cell',
        field.mono ? 'is-mono' : '',
        inferred ? 'is-inferred' : '',
      ].filter(Boolean).join(' ')}
      title={inferred ?? (value || undefined)}
    >
      {waiting ? <span class="text white-tertiary">·</span> : value}
    </span>
  )
}

/* ------------------------------------------------------------------ a multi-edition album */

function GroupDetails(
  { group, issueTypes, onSelect, onSearchArtist, onOpenArt }:
  {
    group: AlbumGroup
    issueTypes: Record<string, MetadataIssueType>
    onSelect: (id: string) => void
    onSearchArtist: (artist: string) => void
    onOpenArt: (album: LibraryAlbum) => void
  },
) {
  return (
    <section class="details-section">
      <div class="details-header">
        <AlbumArt
          album={group.artFrom}
          size="large"
          class="details-cover"
          onOpen={group.artFrom ? () => group.artFrom && onOpenArt(group.artFrom) : undefined}
        />
        <div class="details-heading">
          <h2 class="details-title">{group.album}</h2>
          <button
            type="button"
            class="library-link details-artist"
            onClick={() => onSearchArtist(group.artist)}
          >
            {group.artist}
          </button>
          <div class="details-facts text default-muted">
            {[group.yearRange || group.year, `${group.editions.length} editions`,
              formatSize(group.totalSize)].filter(Boolean).join(' · ')}
          </div>
        </div>
      </div>

      <h3 class="details-subheading">Editions in your library</h3>
      <div class="track-table-scroll">
        <div
          class="track-table editions-table"
          role="grid"
          style="--track-columns:minmax(10em,2fr) 4em 4em 5em 5em 6em minmax(8em,1fr);min-width:44em"
        >
          <div class="track-table-head" role="row">
            {['Edition', 'Year', 'Tracks', 'Length', 'Size', 'Format', 'Needs'].map((label) => (
              <span key={label} role="columnheader" class="track-cell">{label}</span>
            ))}
          </div>
          {group.editions.map((album) => {
            const issues = outstandingIssues(album)
            return (
              <div
                key={album.path}
                role="row"
                class="track-table-row"
                tabIndex={0}
                onClick={() => onSelect(editionNodeId(album))}
                onKeyDown={(event) => { if (event.key === 'Enter') onSelect(editionNodeId(album)) }}
              >
                <span class="track-cell track-title">{album.edition || 'Standard'}</span>
                <span class="track-cell is-mono">{album.year}</span>
                <span class="track-cell is-mono is-right">{album.track_count}</span>
                <span class="track-cell is-mono is-right">{formatDuration(album.duration)}</span>
                <span class="track-cell is-mono is-right">{formatSize(album.total_size)}</span>
                <span class="track-cell">{album.formats.join('/').toUpperCase()}</span>
                <span class="track-cell" title={issues.map((c) => issueTypes[c]?.label ?? c).join(', ')}>
                  {issues.length ? <span class="text yellow">{issueTypes[issues[0] ?? '']?.label ?? issues[0]}{issues.length > 1 ? ` +${issues.length - 1}` : ''}</span> : ''}
                </span>
              </div>
            )
          })}
        </div>
      </div>
    </section>
  )
}

/* ------------------------------------------------------------------ one track */

function TrackDetailsView(
  { album, group, track, details, visible, onSelect, onOpenArt, onViewPictures }:
  {
    album: LibraryAlbum
    group: AlbumGroup
    track: LibraryTrack
    details: TrackDetailsState
    visible: string[]
    onSelect: (id: string) => void
    onOpenArt: (album: LibraryAlbum) => void
    onViewPictures: (images: ViewerImage[]) => void
  },
) {
  const file = details.files?.get(track.filename)
  const row: TrackRow = { track, details: file }
  const at = album.tracks.findIndex((t) => t.filename === track.filename)
  const previous = album.tracks[at - 1]
  const next = album.tracks[at + 1]

  const where = [
    track.position !== null ? `Track ${track.position}` : 'Unnumbered',
    album.disc_count > 1 && track.disc ? `disc ${track.disc} of ${album.disc_count}` : '',
  ].filter(Boolean).join(', ')

  const shown = TRACK_FIELDS.filter((field) => visible.includes(field.id))

  return (
    <section class="details-section">
      <div class="details-header">
        <AlbumArt album={album} size="large" class="details-cover is-small" onOpen={() => onOpenArt(album)} />
        <div class="details-heading">
          <h2 class="details-title">{file?.tags['title'] ?? track.title}</h2>
          <button
            type="button"
            class="library-link details-artist"
            //? through the tree's own id builder - a group key is not the "artist album" string it
            //? looks like (it carries a NUL), so an id rebuilt by hand resolves to nothing
            onClick={() => onSelect(nodeIdForAlbum(album, group))}
          >
            {album.album}
          </button>
          <div class="details-facts text default-muted">
            {[where, trackTime(track.length), track.format.toUpperCase()].filter(Boolean).join(' · ')}
          </div>
          <div class="details-stepper">
            <button
              type="button"
              class="win-button"
              disabled={!previous}
              onClick={() => previous && onSelect(trackNodeId(album, previous))}
            >
              ◁ Previous
            </button>
            <button
              type="button"
              class="win-button"
              disabled={!next}
              onClick={() => next && onSelect(trackNodeId(album, next))}
            >
              Next ▷
            </button>
          </div>
        </div>
      </div>

      {details.error && <p class="text yellow">{details.error}</p>}

      {FIELD_GROUPS.map((groupName) => {
        const inGroup = shown.filter((field) => field.group === groupName)
        if (!inGroup.length) return null
        return (
          <Fragment key={groupName}>
            <h3 class="details-subheading">{groupName}</h3>
            <PropertyGrid
              rows={inGroup.map((field): [string, ComponentChildren] => {
                const value = field.value(row)
                if (value) {
                  const inferred = field.inferred?.(row) ?? null
                  const classes = [field.mono ? 'is-mono' : '', inferred ? 'is-inferred' : '']
                    .filter(Boolean).join(' ')
                  return [field.label, <span class={classes || undefined} title={inferred ?? undefined}>{value}</span>]
                }
                return [field.label, !file && !field.fromScan && details.loading ? '…' : '']
              })}
            />
          </Fragment>
        )
      })}

      <PicturesView album={album} file={file} loading={details.loading} onView={onViewPictures} />

      <LyricsView album={album} track={track} />

      {/*
        Every tag the file carries, under its container's own name - including the ones the
        field menu has never heard of. The menu decides what gets a proper label; this is where
        you go to see what is actually in the file.
      */}
      <details class="details-raw">
        <summary>All tags in this file{file ? ` (${file.raw.length})` : ''}</summary>
        {!file && details.loading && <Loading label="reading the file" />}
        {file && (
          <dl class="property-grid is-raw">
            {file.raw.map(([key, value], i) => (
              <Fragment key={`${key} ${i}`}>
                <dt title={key}>{key}</dt>
                <dd>{value}</dd>
              </Fragment>
            ))}
          </dl>
        )}
        {file && <p class="text white-tertiary details-raw-note">{track.filename}</p>}
      </details>
    </section>
  )
}

/** A picture's size - embedded art is usually tens of KB, which formatSize would call 0 MB. */
function pictureBytes(bytes: number): string {
  return bytes < 1024 * 1024 ? `${Math.max(1, Math.round(bytes / 1024))} KB` : formatSize(bytes)
}

/**
 * The pictures stored inside one track's file.
 *
 * Built because songs in a player showed sleeves that didn't match their album: a player shows
 * a song's OWN picture in place of the album's cover, and a file from a stranger often carries
 * one - another edition's sleeve, a low-resolution copy, a scan of the disc. Each is labelled
 * with its declared type, and its real pixel size once it loads.
 */
function PicturesView(
  { album, file, loading, onView }:
  {
    album: LibraryAlbum
    file: TrackDetails | undefined
    loading: boolean
    onView: (images: ViewerImage[]) => void
  },
) {
  const [sizes, setSizes] = useState<Record<string, string>>({})
  const pictures = file?.pictures ?? []
  const url = (index: number) => trackPictureUrl(album.path, file?.filename ?? '', index, album.modified_at)

  const images = (): ViewerImage[] => pictures.map((picture) => ({
    label: `${picture.label} · ${file?.filename ?? ''}`,
    sources: [url(picture.index)],
  }))

  return (
    <>
      <h3 class="details-subheading">Pictures in this file</h3>
      {!file
        ? (loading ? <Loading label="reading the file" /> : null)
        : !pictures.length
          ? (
            <p class="lyrics-none text white-tertiary">
              None - a player shows the album's cover for this song, or its CD art if the song has a disc number.
            </p>
          )
          : (
            <div class="details-pictures">
              {pictures.map((picture) => {
                const key = `${file.filename}:${picture.index}`
                return (
                  <button
                    key={key}
                    type="button"
                    class="details-picture"
                    title="Click to view full size"
                    onClick={() => onView(images())}
                  >
                    <img
                      src={url(picture.index)}
                      alt={picture.label}
                      onLoad={(event) => {
                        const img = event.currentTarget as HTMLImageElement
                        setSizes((known) => ({ ...known, [key]: `${img.naturalWidth} × ${img.naturalHeight}` }))
                      }}
                    />
                    <span class="details-picture-label">{picture.label}</span>
                    <span class="details-picture-facts text white-tertiary">
                      {[sizes[key], pictureBytes(picture.size), picture.mime.replace('image/', '').toUpperCase()]
                        .filter(Boolean).join(' · ')}
                    </span>
                  </button>
                )
              })}
            </div>
          )}
    </>
  )
}

/**
 * One track's lyrics, read from disk when the track is shown.
 *
 * Read on demand like the track's tags, never carried in the scan - thousands of songs' words in
 * the library-wide payload would tax every visit for text shown one track at a time. Re-read
 * when the album's folder changes, which is what a fetch writing a .lrc does, so lyrics that
 * were just fetched appear without leaving the track.
 */
function LyricsView({ album, track }: { album: LibraryAlbum; track: LibraryTrack }) {
  const [state, setState] = useState<{
    key: string
    lyrics?: TrackLyrics
    error?: string
  } | null>(null)

  const key = `${album.path}\n${track.filename}\n${album.modified_at}\n${album.lyrics_count}`

  useEffect(() => {
    let live = true
    setState({ key })
    libraryApi.trackLyrics(album.path, track.filename).then(
      (lyrics) => { if (live) setState({ key, lyrics }) },
      (caught) => { if (live) setState({ key, error: String(caught?.message ?? caught) }) },
    )
    return () => { live = false }
  }, [key])

  const current = state?.key === key ? state : null
  const lyrics = current?.lyrics

  return (
    <>
      <h3 class="details-subheading">
        Lyrics
        {lyrics?.synced && <span class="lyrics-kind text default-muted">synced</span>}
      </h3>

      {!current || (!current.lyrics && !current.error)
        ? <Loading label="reading lyrics" />
        : current.error
          ? <p class="text yellow">{current.error}</p>
          : !lyrics?.lines.length
            ? (
              <p class="lyrics-none text white-tertiary">
                No lyrics for this track on disk.
                {album.lyrics_count < album.track_count ? ' Get lyrics, above, looks for them on LRCLIB.' : ''}
              </p>
            )
            : (
              <>
                <div class={`lyrics${lyrics.synced ? ' is-synced' : ''}`}>
                  {lyrics.lines.map((line, i) => (
                    //? an empty synced line marks a break in the singing - it gets the space and
                    //? not the time, which beside nothing reads like a line that failed to load
                    line.text
                      ? (
                        <div key={i} class="lyrics-line">
                          {lyrics.synced && (
                            <span class="lyrics-time">{line.time === null ? '' : lyricTime(line.time)}</span>
                          )}
                          <span class="lyrics-text">{line.text}</span>
                        </div>
                      )
                      : <div key={i} class="lyrics-line is-gap" />
                  ))}
                </div>
                <p class="lyrics-source text white-tertiary">
                  {lyrics.source === 'file' ? `From ${lyrics.lyrics_file}` : 'Embedded in the file'}
                </p>
              </>
            )}
    </>
  )
}

/* ------------------------------------------------------------------ nothing selected */

function Overview(
  { summary, groups, onSelect }:
  { summary: LibrarySummary; groups: readonly AlbumGroup[]; onSelect: (id: string) => void },
) {
  //? the question you usually have when you open the library without a particular album in mind
  //? is "what just arrived" - judged by the same clock as the "Date added" arrangement
  const recent = useMemo(
    () => [...groups].sort((a, b) => groupAddedAt(b) - groupAddedAt(a)).slice(0, 12),
    [groups],
  )

  return (
    <section class="details-section">
      <h2 class="details-title">Library</h2>
      <PropertyGrid
        rows={[
          ['Albums', String(summary.albums)],
          ['Artists', String(summary.artists)],
          ['Tracks', String(summary.tracks)],
          ['Length', formatDuration(summary.duration)],
          ['Size', formatSize(summary.size)],
          ['Folder', summary.libraryPath ? <span class="details-path">{summary.libraryPath}</span> : ''],
          ['Last scanned', summary.scannedAt
            ? `${formatAge(summary.scannedAt)}${summary.stale ? ' (saved scan, checking now)' : ''}`
            : ''],
        ]}
      />
      <p class="text white-tertiary details-hint">
        Pick an artist, an album or a track on the left to see it here. The arrow keys move
        through the tree, and right and left open and close it.
      </p>

      {recent.length > 0 && (
        <>
          <h3 class="details-subheading">Recently added</h3>
          <CoverGrid groups={recent} showArtist onSelect={onSelect} />
        </>
      )}
    </section>
  )
}

/* ------------------------------------------------------------------ the field menu */

function FieldsMenu(
  { visible, onToggle, onReset, onClose }:
  {
    visible: string[]
    onToggle: (id: string, on: boolean) => void
    onReset: () => void
    onClose: () => void
  },
) {
  const menuRef = useRef<HTMLDivElement>(null)

  //? closes on a click anywhere else, or Escape - caught in the capture phase and stopped, so
  //? the Escape doesn't also reach anything listening further out
  useEffect(() => {
    const onPointer = (event: MouseEvent) => {
      const control = menuRef.current?.parentElement
      if (control && !control.contains(event.target as Node)) onClose()
    }
    const onKey = (event: KeyboardEvent) => {
      if (event.key !== 'Escape') return
      event.stopPropagation()
      onClose()
    }
    document.addEventListener('mousedown', onPointer)
    window.addEventListener('keydown', onKey, true)
    return () => {
      document.removeEventListener('mousedown', onPointer)
      window.removeEventListener('keydown', onKey, true)
    }
  }, [onClose])

  return (
    <div class="fields-menu" ref={menuRef} role="menu" aria-label="Fields">
      <div class="fields-menu-groups">
        {FIELD_GROUPS.map((group) => (
          <fieldset key={group} class="fields-menu-group">
            <legend>{group}</legend>
            {TRACK_FIELDS.filter((field) => field.group === group).map((field) => (
              <label key={field.id} class="fields-menu-item" role="menuitemcheckbox" aria-checked={visible.includes(field.id)}>
                <input
                  type="checkbox"
                  checked={visible.includes(field.id)}
                  onChange={(event) => onToggle(field.id, (event.target as HTMLInputElement).checked)}
                />
                {field.label === '#' ? 'Track number' : field.label}
              </label>
            ))}
          </fieldset>
        ))}
      </div>
      <div class="fields-menu-footer">
        <span class="text white-tertiary">
          Title is always shown. Drag a header to move its column, or its edge to size it.
        </span>
        <button
          type="button"
          class="win-button"
          title="Put back the default fields, in the default order, at their own widths"
          onClick={onReset}
        >
          Reset
        </button>
      </div>
    </div>
  )
}
