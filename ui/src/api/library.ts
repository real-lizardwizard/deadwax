import { fetchOk, get, post } from './http'
import type {
  ArtistImagesPreview, ArtistImagesResult, ArtistSearchResult, ArtistSummary, DeleteResult,
  DeletionSummary,
  LibraryAlbum, LibraryResponse, LyricsSummary, NewImportsResponse, OwnedResponse, QueueSummaryResponse, RetagPlan,
  RetagRelease, RetagResponse, TagEditPlan, TagEditResponse, TrackDetailsResponse, TrackLyrics,
  TrackTagEdit,
} from './types'

/** What a scan says about itself in its headers - see _SCAN_HEADERS in src/routes/library.py. */
export type ScanMeta = Pick<LibraryResponse, 'scanned_at' | 'scan_seconds' | 'cached' | 'stale' | 'etag'>

/** A scan whose body is the one already on screen: only what its headers say is new. */
export type UnchangedScan = ScanMeta & { unchanged: true }

/**
 * Everything currently in LIBRARY_PATH: the saved scan (`snapshot`, from the cache, touching no
 * disk - what makes the tab open at once), a scan, or a forced rescan.
 *
 * The server caches per folder on mtime, so a scan is cheap to repeat - but the first one of a
 * large library reads tags off every file and can take seconds. Treat it as a load, not a poll.
 *
 * `shownEtag` is the ETag of the albums already on screen. The ETag is a hash of the body, so an
 * answer carrying the same one IS what's on screen, and it isn't read at all (v0.9.25): opening
 * the tab fetches the snapshot and then the scan, and when nothing changed - nearly always - the
 * scan used to be parsed, rebuilt and re-rendered for nothing, 140ms of a thousand albums on a
 * fast machine.
 */
export async function loadScan(
  mode: 'snapshot' | 'scan' | 'rescan',
  shownEtag: string | null = null,
): Promise<LibraryResponse | UnchangedScan> {
  const response = mode === 'rescan'
    ? await fetchOk('/library/rescan', { method: 'POST' })
    : await fetchOk(mode === 'snapshot' ? '/library/albums?snapshot=true' : '/library/albums')

  const meta = scanMeta(response.headers)
  if (shownEtag && meta.etag === shownEtag) {
    void response.body?.cancel()
    return { ...meta, unchanged: true }
  }
  //? the tracks arrive compact; undone here, at the one place albums arrive
  return expandTracks({ ...((await response.json()) as LibraryResponse), ...meta })
}

/** A real scan, always read whole - for a caller with nothing on screen to compare it to. */
export async function listAlbums(): Promise<LibraryResponse> {
  //? with no ETag to match, loadScan always reads the body
  return (await loadScan('scan')) as LibraryResponse
}

function scanMeta(headers: Headers): ScanMeta {
  const number = (name: string) => {
    const value = headers.get(name)
    return value === null || value === '' ? null : Number(value)
  }
  return {
    scanned_at: number('X-Scanned-At'),
    scan_seconds: number('X-Scan-Seconds') ?? 0,
    cached: number('X-Scan-Cached') ?? 0,
    stale: headers.get('X-Scan-Stale') === '1',
    etag: headers.get('ETag'),
  }
}

/**
 * Put every track back together from the compact wire form (v0.9.20, src/library.py
 * compact_for_wire): an album sends the values its tracks share once, as `track_defaults`, and a
 * track carries only where it differs, plus `has_title_tag` only when false. Expanded here, at the
 * one place albums arrive, so nothing past the fetch knows the difference.
 */
export function expandTracks(response: LibraryResponse): LibraryResponse {
  for (const album of response.albums ?? []) {
    const wire = album as LibraryAlbum & { track_defaults?: Record<string, unknown> }
    const defaults = wire.track_defaults
    if (!defaults) continue
    const fields = Object.keys(defaults)
    //? filled in place, not rebuilt with spreads: the same tracks, and 3ms rather than 35 for a
    //? thousand albums (measured) - these objects are fresh from JSON.parse and nobody else's
    for (const track of album.tracks as unknown as Record<string, unknown>[]) {
      for (const field of fields) if (!(field in track)) track[field] = defaults[field]
      if (!('has_title_tag' in track)) track['has_title_tag'] = true
    }
    delete wire.track_defaults
  }
  return response
}

/**
 * Every tag on every file in one album, read from disk now. For the track viewer.
 *
 * Deliberately not part of the scan: the scan is the whole library in one payload, and thirty
 * tags a track across thousands of tracks would tax every visit for detail shown one album at
 * a time.
 */
export function trackDetails(albumPath: string): Promise<TrackDetailsResponse> {
  return get<TrackDetailsResponse>(`/library/tracks?album=${encodeURIComponent(albumPath)}`)
}

/** Drop the server's per-folder cache and read everything again. */
/**
 * What applying this release to that album would change. Writes nothing.
 *
 * A separate endpoint from apply rather than a flag on it — this runs while you're still
 * choosing, so it must be impossible for it to modify anything by accident.
 */
export function previewRetag(
  albumPath: string,
  release: RetagRelease,
  fetchArt = false,
): Promise<RetagPlan> {
  return post<RetagPlan>('/library/retag/preview', {
    album_path: albumPath, release, fetch_art: fetchArt,
  })
}

/**
 * Write the tags and re-file the folder.
 *
 * The server recomputes the plan rather than taking the previewed one back, so this sends
 * the same two arguments the preview did — a plan is a list of file operations, and handing
 * one over the wire would let a caller name arbitrary paths to write to.
 */
export function applyRetag(
  albumPath: string,
  release: RetagRelease,
  fetchArt = false,
): Promise<RetagResponse> {
  return post<RetagResponse>('/library/retag/apply', {
    album_path: albumPath, release, fetch_art: fetchArt,
  })
}

/* ===== editing tags by hand ===== */

/**
 * What these hand edits would change, file by file. Writes nothing.
 *
 * Its own endpoint rather than a flag on apply, for the retag preview's reason: it runs while
 * you are still typing, so it must be impossible for it to write anything by accident.
 */
export function previewTagEdits(albumPath: string, edits: TrackTagEdit[]): Promise<TagEditPlan> {
  return post<TagEditPlan>('/library/tags/preview', { album_path: albumPath, edits })
}

/**
 * Write them. Tags only — no file is renamed and no folder moves.
 *
 * Sends the same edits the preview did; the server recomputes the plan rather than taking one
 * back, and refuses the whole batch if any of it is invalid.
 */
export function applyTagEdits(albumPath: string, edits: TrackTagEdit[]): Promise<TagEditResponse> {
  return post<TagEditResponse>('/library/tags/apply', { album_path: albumPath, edits })
}

/**
 * Every album in the library, reduced to which album and edition it is (2.0.0-player.13 gave the
 * app this call; the main page's search has always made it). The app's Search leaves the albums
 * the library holds out of "Not in your library yet" with it (lib/owned.ts).
 *
 * NOT cheap the first time after deadwax restarts: that answer is a real scan, which walks the whole
 * library (`library_is_behind`) - so never ask it as a page loads (app/useOwned.ts asks when Search
 * first shows). Answered with an ETag and `Cache-Control: no-cache`, so the browser asks again each
 * time and an unchanged library comes back as a 304 the browser fills in from its own copy - nothing
 * to do here.
 */
export function owned(signal?: AbortSignal): Promise<OwnedResponse> {
  return get<OwnedResponse>('/library/owned', signal)
}

/* ===== the metadata queue ===== */

/**
 * Albums deadwax has filed that you haven't looked at yet.
 *
 * Cheap on purpose — one indexed table read, no filesystem. Safe to call on page load, which
 * `listAlbums` deliberately is not.
 */
export function newImports(): Promise<NewImportsResponse> {
  return get<NewImportsResponse>('/library/queue/new_imports')
}

/**
 * How many albums need a look (2.0.0-player.25) - the app's count beside "Needs a look". Answered
 * from the saved scan and the review rows, never a walk of the disk, so it is safe to ask whenever
 * the count could have moved (app/useQueueSummary.ts).
 */
export function queueSummary(signal?: AbortSignal): Promise<QueueSummaryResponse> {
  return get<QueueSummaryResponse>('/library/queue/summary', signal)
}

/**
 * Accept an album as it is, so it drops out of the queue.
 *
 * The issue codes are sent rather than left to the server to work out, so this can only ever
 * mute the problems that were actually on screen. An album that develops a *different* problem
 * later comes back into the queue on its own.
 */
export function ignoreIssues(albumPath: string, issues: string[]): Promise<{ ignored: boolean }> {
  return post('/library/queue/ignore', { album_path: albumPath, issues })
}

/** Put an ignored album back into the queue. */
export function unignoreAlbum(albumPath: string): Promise<{ ignored: boolean }> {
  return post('/library/queue/unignore', { album_path: albumPath })
}

/**
 * Note that you've looked at an album.
 *
 * Clears it from the new-import prompt and nothing else — its issues stand, because a queue
 * that empties when you glance at things is a queue that lies.
 */
export function markReviewed(albumPath: string): Promise<{ reviewed: boolean }> {
  return post('/library/queue/reviewed', { album_path: albumPath })
}

/**
 * Put a cover in an album's folder, changing nothing else about it.
 *
 * The narrow counterpart to `applyRetag`. That one rewrites every file's tags and can rename
 * the folder — a lot to agree to when the only thing missing is the picture. This asks the
 * Cover Art Archive for art belonging to the release the album's own tags already name, so
 * there is nothing to choose and nothing to preview. It is saved at COVER_ART_SIZE, which the
 * settings tab sets.
 *
 * `replace` is off by default: a sleeve you picked yourself is not ours to overwrite because
 * the Archive happens to have one too.
 */
export function fetchCoverArt(
  albumPath: string,
  options: { replace?: boolean; releaseMbid?: string | null } = {},
): Promise<{ written: string | null; replaced: string | null }> {
  return post('/library/art/fetch', {
    album_path: albumPath,
    replace: options.replace ?? false,
    //? omitted for the plain path, where the release comes from the album's own tags. The
    //? editor sends one because it is showing you that release's cover as you decide.
    release_mbid: options.releaseMbid ?? null,
  })
}

/**
 * Look up every track's lyrics on LRCLIB and save each as a `.lrc` beside it.
 *
 * Like fetchCoverArt it chooses nothing, so there is nothing to preview: each file is asked
 * about by the tags it already carries, and a `.lrc` already there is kept unless `replace`.
 * A track LRCLIB has nothing for is in the summary, not an error.
 */
export function fetchLyrics(
  albumPath: string,
  options: { replace?: boolean; retime?: boolean } = {},
): Promise<LyricsSummary> {
  return post<LyricsSummary>('/library/lyrics/fetch', {
    album_path: albumPath,
    replace: options.replace ?? false,
    //? re-time the .lrc files already there to LYRICS_LEAD_MS, leaving any that aren't
    //? LRCLIB's timings untouched - see lyrics.timing_delta() on the server
    retime: options.retime ?? false,
  })
}

/** One track's lyrics as they are on disk now, for the track viewer. */
export function trackLyrics(albumPath: string, filename: string): Promise<TrackLyrics> {
  return get<TrackLyrics>(
    `/library/lyrics?album=${encodeURIComponent(albumPath)}&file=${encodeURIComponent(filename)}`,
  )
}

/**
 * Save a picture of the disc beside an album's tracks, as disc.<ext> or disc<N>.<ext>.
 *
 * Chooses nothing, like fetchCoverArt: the release comes from the album's own tags. A 404 means
 * neither the Cover Art Archive nor fanart.tv has one; a 502, that one couldn't be reached.
 */
export function fetchDiscArt(albumPath: string): Promise<{ written: string[]; source: string }> {
  return post('/library/disc_art/fetch', { album_path: albumPath })
}

/** What deleting this album would remove. Touches nothing. */
export function deletionSummary(albumPath: string): Promise<DeletionSummary> {
  return get<DeletionSummary>(`/library/deletion_summary?album=${encodeURIComponent(albumPath)}`)
}

/**
 * Delete an album folder and everything in it. Permanent, and the only call in here with no
 * undo — the guards that make it safe live in src/library.py::delete_album.
 */
export function deleteAlbum(albumPath: string): Promise<DeleteResult> {
  return post<DeleteResult>('/library/delete', { album_path: albumPath })
}


/**
 * One artist as the library knows them. Touches no network on the server.
 *
 * Drawn immediately, the way the library tab draws its snapshot; what needs MusicBrainz and the
 * image hosts arrives separately, because those can take seconds or be down altogether.
 */
export function fetchArtist(name: string): Promise<ArtistSummary> {
  return get<ArtistSummary>(`/library/artist?name=${encodeURIComponent(name)}`)
}

/**
 * Who this artist is in MusicBrainz, every picture the sources have of them, and what writing
 * those would do. Fetches no image bytes — only the small payloads that say what exists.
 */
export function previewArtistImages(
  artist: string,
  options: { artistMbid?: string | null; replace?: boolean } = {},
): Promise<ArtistImagesPreview> {
  return post<ArtistImagesPreview>('/library/artist/images/preview', {
    artist,
    artist_mbid: options.artistMbid ?? null,
    replace: options.replace ?? false,
  })
}

/**
 * Write the chosen pictures into the artist's folder.
 *
 * `choices` is kind -> the URL picked for it, and the server only honours a URL that this
 * artist's own sources offered — it recomputes the list rather than trusting this one.
 */
export function applyArtistImages(
  artist: string,
  choices: Record<string, string>,
  options: { artistMbid?: string | null; replace?: boolean } = {},
): Promise<ArtistImagesResult> {
  return post<ArtistImagesResult>('/library/artist/images/apply', {
    artist,
    artist_mbid: options.artistMbid ?? null,
    choices,
    replace: options.replace ?? false,
  })
}


/**
 * Artists in MusicBrainz going by this name. Writes nothing.
 *
 * The way past the two things the automatic match refuses to guess at: files carrying no
 * MusicBrainz ids, and the several bands that share a name.
 */
export function searchArtists(query: string): Promise<ArtistSearchResult> {
  return post<ArtistSearchResult>('/library/artist/search', { query })
}

/** One album the re-filing would move (v0.9.14). */
export interface ArtistRefileMove {
  album: string
  path: string
  target_path: string
  files: number
  retag: { filename: string; changes: Record<string, { from: string; to: string }> }[]
}

export interface ArtistRefilePlan {
  current_name: string
  to_folder: string
  artist_mbid: string | null
  moves: ArtistRefileMove[]
  refused: { album: string; path: string; reason: string }[]
  problems: string[]
  empty: boolean
}

export interface ArtistRefileResults {
  moved: { from: string; to: string }[]
  failed: { album: string; reason: string }[]
  pictures_moved: string[]
  removed_folders: string[]
}

/** Which of an artist's albums would move under the name MusicBrainz uses now. Writes nothing. */
export function previewArtistRefile(artist: string, artistMbid: string | null): Promise<ArtistRefilePlan> {
  return post<ArtistRefilePlan>('/library/artist/refile/preview', { artist, artist_mbid: artistMbid })
}

/** Move them. The server recomputes the plan rather than taking this one back. */
export function applyArtistRefile(
  artist: string, artistMbid: string | null,
): Promise<{ plan: ArtistRefilePlan; results: ArtistRefileResults }> {
  return post('/library/artist/refile/apply', { artist, artist_mbid: artistMbid })
}
