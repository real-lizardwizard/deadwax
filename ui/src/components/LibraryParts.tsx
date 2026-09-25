import { useEffect, useState } from 'preact/hooks'

import * as libraryApi from '../api/library'
import type { LibraryAlbum, LyricsSummary, MetadataIssueType } from '../api/types'
import { albumArtUrl } from '../lib/format'
import type { AlbumGroup } from '../lib/groupAlbums'
import { groupNodeId } from '../lib/libraryTree'
import { describeLyrics, lyricsOnDisk } from '../lib/lyrics'
import { describeIssues, issueLabel } from '../lib/metadataQueue'
import { Loading } from './Loading'

/**
 * Small pieces the library's tree and details pane both draw. They lived in the old album-row
 * component, which the tree replaced.
 */

export type CoverSize = 'thumb' | 'large' | 'full'

/**
 * Where an album's cover can come from, best first.
 *
 *   1. the library's own art endpoint - a cover file beside the tracks, or art embedded in the
 *      audio. Works offline and shows what is actually on disk. It serves the file whole, so
 *      it is already full size.
 *   2. the Cover Art Archive, keyed on the RELEASE id - the edition's own art, not the group's.
 *      `full` asks for the original upload rather than a thumbnail, which is what you want when
 *      deciding between two covers: a 250px preview hides exactly the difference in quality.
 *
 * Fallback is driven by the image failing to load rather than by probing first - the browser
 * reports a failure for free, and a HEAD request per album would double the traffic.
 */
export function coverSources(album: LibraryAlbum, size: CoverSize): string[] {
  const sources: string[] = []
  if (album.art) sources.push(albumArtUrl(album))
  if (album.release_mbid) {
    const variant = size === 'full' ? 'front' : size === 'large' ? 'front-500' : 'front-250'
    sources.push(`https://coverartarchive.org/release/${album.release_mbid}/${variant}`)
  }
  return sources
}

export function AlbumArt(
  { album, size = 'thumb', class: className = 'library-art', onOpen }:
  //? `| undefined` is not redundant: exactOptionalPropertyTypes is on, and a caller that only
  //? sometimes has a cover to open passes undefined explicitly
  { album: LibraryAlbum | undefined; size?: CoverSize; class?: string; onOpen?: (() => void) | undefined },
) {
  const sources = album ? coverSources(album, size) : []
  const [attempt, setAttempt] = useState(0)

  //? a different album, or a replaced cover, starts again at the best source - otherwise one
  //? failure would carry over to every album this instance is later asked to draw
  useEffect(() => setAttempt(0), [album?.path, album?.art_mtime])

  const src = sources[attempt]

  // an empty square rather than nothing, so rows don't jump around as art loads or fails
  if (!src) return <div class={`${className} is-empty`} aria-hidden="true" />

  const image = (
    <img
      class={className}
      src={src}
      alt=""
      loading="lazy"
      decoding="async"
      onError={() => setAttempt((n) => n + 1)}
    />
  )

  if (!onOpen) return image

  return (
    <button type="button" class="library-art-open" title="View full size" onClick={onOpen}>
      {image}
    </button>
  )
}

//? Two chips and a count at most. An unidentified album trips five or six rules at once - all
//? downstream of the one fact that it was never matched to a release - and a row that turns into
//? a wall of amber for a single underlying problem reads as far worse than it is.
export function IssueChips(
  { issues, types, ignored, max = 2 }:
  { issues: readonly string[]; types: Record<string, MetadataIssueType>; ignored?: boolean; max?: number },
) {
  if (!issues.length) return null

  const shown = issues.slice(0, max)
  const rest = issues.length - shown.length

  return (
    <span
      class={`library-issues${ignored ? ' is-ignored' : ''}`}
      title={describeIssues(issues, types)}
    >
      {shown.map((code) => (
        <span class="library-issue-chip" key={code}>{issueLabel(code, types)}</span>
      ))}
      {rest > 0 && <span class="library-issue-more">+{rest}</span>}
    </span>
  )
}

/**
 * Fetch just the cover for one album.
 *
 * Rendered only for albums that have no art but DO name a release, which is exactly the set it
 * can help - there is nothing to look a cover up by otherwise, and an album that already has
 * one isn't asking.
 */
export function GetArtButton(
  { album, onDone, class: className = 'commandbar-button' }:
  { album: LibraryAlbum; onDone: () => void; class?: string },
) {
  const [state, setState] = useState<'idle' | 'working' | 'failed'>('idle')

  if (album.art || !album.release_mbid) return null

  const fetchArt = async (event: MouseEvent) => {
    event.stopPropagation()
    setState('working')

    try {
      await libraryApi.fetchCoverArt(album.path)
      onDone()
    } catch (caught) {
      setState('failed')
      console.error(caught)
    }
  }

  return (
    <button
      type="button"
      class={`${className}${state === 'failed' ? ' failed' : ''}`}
      /*
       * Disabled only while a request is actually in flight. A failure leaves it clickable on
       * purpose: the usual reason is that the Archive has no front cover for this release, but
       * the second usual reason is that the Archive was briefly unreachable - it goes away for
       * minutes at a time, exactly like MusicBrainz - and a button that latches off after one
       * bad answer turns a passing outage into a permanent dead end with no way to retry.
       */
      disabled={state === 'working'}
      title={
        state === 'failed'
          ? 'no front cover came back for this release - the Archive may not have one, or may '
            + 'have been briefly unreachable. Click to try again.'
          : 'download a cover for this album and change nothing else'
      }
      onClick={(event) => void fetchArt(event as unknown as MouseEvent)}
    >
      {state === 'working' ? <Loading /> : state === 'failed' ? 'Retry cover' : 'Get cover'}
    </button>
  )
}

/**
 * Fetch lyrics for every track of one album that doesn't have them yet.
 *
 * Rendered while any track lacks a `.lrc`, and - once it has run - for as long as you stay on
 * that album, reading "Lyrics · 9 of 10" with the whole outcome in its tooltip. Without that
 * the button would either vanish (every track found) or come back looking untouched (some not
 * on LRCLIB), and both read as the click having done nothing.
 */
export function GetLyricsButton(
  { album, onDone, class: className = 'commandbar-button' }:
  { album: LibraryAlbum; onDone: () => void; class?: string },
) {
  const [run, setRun] = useState<{
    path: string
    state: 'working' | 'done' | 'failed'
    summary?: LyricsSummary
  } | null>(null)

  //? a result belongs to the album it was fetched for, never to the next one selected
  const mine = run && run.path === album.path ? run : null

  if (!mine && album.lyrics_count >= album.track_count) return null

  const getLyrics = async (event: MouseEvent) => {
    event.stopPropagation()
    const path = album.path
    setRun({ path, state: 'working' })

    try {
      const summary = await libraryApi.fetchLyrics(path)
      setRun({ path, state: 'done', summary })
      if (summary.written || summary.replaced) onDone()
    } catch (caught) {
      setRun({ path, state: 'failed' })
      console.error(caught)
    }
  }

  const summary = mine?.state === 'done' ? mine.summary : undefined

  return (
    <button
      type="button"
      class={`${className}${mine?.state === 'failed' ? ' failed' : ''}`}
      //? like Get cover: disabled only while in flight, so a passing outage is never a dead end
      disabled={mine?.state === 'working'}
      title={
        summary
          ? `${describeLyrics(summary)}.`
            + (lyricsOnDisk(summary) < album.track_count ? ' Click to look again for the rest.' : '')
          : mine?.state === 'failed'
            ? 'the lyrics lookup failed - LRCLIB may be briefly unreachable. Click to try again.'
            : 'look up lyrics on LRCLIB for the tracks here without them, and save each as a .lrc '
              + 'beside the track. Nothing else about the album changes.'
      }
      onClick={(event) => void getLyrics(event as unknown as MouseEvent)}
    >
      {mine?.state === 'working'
        ? <Loading />
        : summary
          ? `Lyrics · ${lyricsOnDisk(summary)} of ${album.track_count}`
          : mine?.state === 'failed' ? 'Retry lyrics' : 'Get lyrics'}
    </button>
  )
}

/** A small person, for artist rows. Drawn in currentColor so it follows the row's state. */
export function ArtistIcon() {
  return (
    <svg class="tree-icon" viewBox="0 0 16 16" aria-hidden="true">
      <circle cx="8" cy="5" r="3" fill="currentColor" />
      <path d="M2.5 14.5c0-3.2 2.5-5.3 5.5-5.3s5.5 2.1 5.5 5.3z" fill="currentColor" />
    </svg>
  )
}


/**
 * An artist's or a group's albums as covers.
 *
 * Shared rather than duplicated: the details pane draws it for an artist node and the artist
 * page draws the same thing, and two copies would drift the moment one gained a tooltip.
 */
export function CoverGrid(
  { groups, showArtist, onSelect }:
  { groups: readonly AlbumGroup[]; showArtist: boolean; onSelect: (id: string) => void },
) {
  return (
    <div class="cover-grid">
      {groups.map((group) => (
        <button
          key={group.key}
          type="button"
          class="cover-tile"
          title={`${group.album} — ${group.artist}`}
          onClick={() => onSelect(groupNodeId(group))}
        >
          <AlbumArt album={group.artFrom} size="large" class="cover-tile-art" />
          <span class="cover-tile-title">{group.album}</span>
          <span class="cover-tile-sub">
            {showArtist ? group.artist : group.yearRange || group.year || ' '}
          </span>
        </button>
      ))}
    </div>
  )
}
