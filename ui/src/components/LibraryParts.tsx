import { useState } from 'preact/hooks'

import { ApiError } from '../api/http'
import * as libraryApi from '../api/library'
import type { LibraryAlbum, LyricsSummary } from '../api/types'
import { albumArtUrl } from '../lib/format'
import { lyricsOnDisk } from '../lib/lyrics'
import { GETTING, getProblem, lyricsResult } from '../lib/getResults'
import { accessNow, seesDetail } from '../app/access'
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

/**
 * (2.0.8, UX batch 5) What a Get came to, as a line under its button (lib/getResults.ts) - it was only in the button's
 * tooltip, which a phone never shows. A live region, so VoiceOver hears it too.
 */
function ResultLine({ text, class: className }: { text: string | null; class: string }) {
  return text ? <p class={className} role="status">{text}</p> : null
}

/**
 * Fetch just the cover for one album.
 *
 * Rendered only for albums that have no art but DO name a release, which is exactly the set it
 * can help - there is nothing to look a cover up by otherwise, and an album that already has
 * one isn't asking.
 */
export function GetArtButton(
  { album, onDone, class: className = 'commandbar-button', note = 'app-edit-note' }:
  { album: LibraryAlbum; onDone: () => void; class?: string; note?: string },
) {
  //? keyed to the album it ran for, like Get lyrics and Get CD art below: this one instance
  //? serves every album you select, and "working" or a failure belonged to the last one
  const [run, setRun] = useState<{ path: string; state: 'working' | 'none' | 'failed'; said?: string } | null>(null)
  const mine = run && run.path === album.path ? run : null
  const state = mine ? mine.state : 'idle'

  if (album.art || !album.release_mbid) return null

  const fetchArt = async (event: MouseEvent) => {
    event.stopPropagation()
    const path = album.path
    setRun({ path, state: 'working' })

    try {
      await libraryApi.fetchCoverArt(path)
      setRun((now) => (now?.path === path ? null : now))
      onDone()
    } catch (caught) {
      //? (2.0.8) said under the button - it went only to the console; a 404 is the Archive having no front cover for the
      //? release, a fact rather than a failure, so the button is Look again, as Get CD art's is - not Try again
      const said = getProblem(caught, 'cover', seesDetail(accessNow()))
      const state = caught instanceof ApiError && caught.status === 404 ? 'none' : 'failed'
      setRun((now) => (now?.path === path ? { path, state, said } : now))
    }
  }

  return (
    <>
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
        title="Download a cover for this album and change nothing else."
        onClick={(event) => void fetchArt(event as unknown as MouseEvent)}
      >
        {state === 'working' ? <Loading label={GETTING.cover} /> : state === 'none' ? 'Look again' : state === 'failed' ? 'Try again' : 'Get cover'}
      </button>
      <ResultLine text={mine?.said ?? null} class={note} />
    </>
  )
}

/**
 * Fetch lyrics for every track of one album that doesn't have them yet.
 *
 * Rendered while any track lacks a `.lrc`, and - once it has run - for as long as you stay on
 * that album, reading "Lyrics · 9 of 10" with the whole outcome in the line under it (2.0.8 - it
 * was in its tooltip). Without that the button would either vanish (every track found) or come back
 * looking untouched (some not on LRCLIB), and both read as the click having done nothing.
 */
export function GetLyricsButton(
  { album, onDone, class: className = 'commandbar-button', note = 'app-edit-note' }:
  { album: LibraryAlbum; onDone: () => void; class?: string; note?: string },
) {
  const [run, setRun] = useState<{
    path: string
    state: 'working' | 'done' | 'failed'
    summary?: LyricsSummary
    said?: string
  } | null>(null)

  //? a result belongs to the album it was fetched for, never to the next one selected
  const mine = run && run.path === album.path ? run : null

  if (!mine && album.lyrics_count >= album.track_count) return null

  const getLyrics = async (event: MouseEvent) => {
    event.stopPropagation()
    const path = album.path
    setRun({ path, state: 'working' })

    //? only over this album's own run - an answer for the album you left must not end the
    //? "working" of one you started since
    try {
      const summary = await libraryApi.fetchLyrics(path)
      setRun((now) => (now?.path === path ? { path, state: 'done', summary } : now))
      if (summary.written || summary.replaced) onDone()
    } catch (caught) {
      const said = getProblem(caught, 'lyrics', seesDetail(accessNow()))
      setRun((now) => (now?.path === path ? { path, state: 'failed', said } : now))
    }
  }

  const summary = mine?.state === 'done' ? mine.summary : undefined

  return (
    <>
      <button
        type="button"
        class={`${className}${mine?.state === 'failed' ? ' failed' : ''}`}
        //? like Get cover: disabled only while in flight, so a passing outage is never a dead end
        disabled={mine?.state === 'working'}
        title="Look up lyrics on LRCLIB for the tracks here without them, and save each as a .lrc beside the track. Nothing else about the album changes."
        onClick={(event) => void getLyrics(event as unknown as MouseEvent)}
      >
        {mine?.state === 'working'
          ? <Loading label={GETTING.lyrics} />
          : summary
            ? `Lyrics · ${lyricsOnDisk(summary)} of ${album.track_count}`
            : mine?.state === 'failed' ? 'Try again' : 'Get lyrics'}
      </button>
      <ResultLine text={summary ? lyricsResult(summary) : mine?.said ?? null} class={note} />
    </>
  )
}

/**
 * Fetch a picture of the disc for one album, saved as disc.<ext> beside the tracks.
 *
 * Rendered for albums that name a release and have none of deadwax's own `disc*` images. A
 * `cd.jpg` scan a download brought with it doesn't hide it: a fetched `disc.*` sits ahead of
 * that in every reader's order, so fetching is how a stray scan stops being what players show.
 *
 * "None found" and "couldn't reach" are told apart, and both stay clickable - an archive that
 * was briefly away is worth asking again, and nothing here should latch into a dead end. (2.0.8)
 * Which it was is said under the button, where it was in the tooltip.
 */
export function GetDiscArtButton(
  { album, onDone, class: className = 'commandbar-button', note = 'app-edit-note' }:
  { album: LibraryAlbum; onDone: () => void; class?: string; note?: string },
) {
  const [run, setRun] = useState<{ path: string; state: 'working' | 'none' | 'failed'; said?: string } | null>(null)
  const mine = run && run.path === album.path ? run : null

  const hasOwn = (album.disc_art ?? []).some((name) => name.toLowerCase().startsWith('disc'))
  if (!album.release_mbid || hasOwn) return null

  const getDiscArt = async (event: MouseEvent) => {
    event.stopPropagation()
    const path = album.path
    setRun({ path, state: 'working' })

    try {
      await libraryApi.fetchDiscArt(path)
      setRun((now) => (now?.path === path ? null : now))
      onDone()
    } catch (caught) {
      const said = getProblem(caught, 'disc', seesDetail(accessNow()))
      const state = caught instanceof ApiError && caught.status === 404 ? 'none' : 'failed'
      setRun((now) => (now?.path === path ? { path, state, said } : now))
    }
  }

  return (
    <>
      <button
        type="button"
        class={`${className}${mine?.state === 'failed' ? ' failed' : ''}`}
        disabled={mine?.state === 'working'}
        title="Download a picture of the disc for this release and save it beside the tracks - what players show for a song with a disc number. Nothing else changes."
        onClick={(event) => void getDiscArt(event as unknown as MouseEvent)}
      >
        {mine?.state === 'working'
          ? <Loading label={GETTING.disc} />
          : mine?.state === 'none' ? 'Look again' : mine?.state === 'failed' ? 'Try again' : 'Get CD art'}
      </button>
      <ResultLine text={mine?.said ?? null} class={note} />
    </>
  )
}
