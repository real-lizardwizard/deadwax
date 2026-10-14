import type { EmbeddedPicture, LibraryAlbum, LibraryTrack, TrackDetails, TrackLyrics } from '../api/types'
import { formatSize, trackTime } from './format'
import { discTitle } from './libraryTree'
import { FIELD_GROUPS, TRACK_FIELDS, type FieldGroup, type TrackRow } from './trackFields'

/**
 * Inside a track, in the app (2.0.0-player.44): what the Edit panel's track inspector says of one track -
 * pure, so the inspector (app/TrackInspector.tsx) draws it and inspector.sim.cjs holds it.
 *
 * It is the main page's track view (components/LibraryDetails.tsx, TrackDetailsView) read for a panel
 * 390 to 470px wide: the SAME registry of fields (lib/trackFields.ts) - every field the main page offers,
 * not only the ones its Fields menu shows, each under its group (Tags, Audio, MusicBrainz, File) in the
 * registry's order - the same values from the scan's copy and the file read just now (`/library/tracks`,
 * hooks/useTrackDetails.ts), the same dimmed disc 1 for a file with no disc tag, and the same words for
 * where the track sits, its pictures and its lyrics.
 */

/** One field as the inspector draws it. */
export interface InspectorField {
  id: string
  label: string
  /** what the file (or the scan) says - '' for a field the file lacks */
  value: string
  mono: boolean
  /** a default rather than a tag - the disc of a file with no disc tag: drawn dimmed, saying why */
  inferred: string | null
  /** a field only the file carries, while the file is still being read: '…', never a blank that reads
   *  as "this track has no genre" */
  waiting: boolean
}

export interface InspectorGroup {
  name: FieldGroup
  fields: InspectorField[]
}

/**
 * Every field the main page's track viewer offers, under its group, for one track: the scan's copy at
 * once, the file's own once read (the file wins where both say - lib/trackFields.ts). A field with no
 * value is '' (drawn as a dash), or `waiting` while the file is still being read and the scan can't say.
 */
export function inspectorGroups(track: LibraryTrack, details: TrackDetails | undefined, loading: boolean): InspectorGroup[] {
  const row: TrackRow = { track, details }
  return FIELD_GROUPS.map((name) => ({
    name,
    fields: TRACK_FIELDS.filter((field) => field.group === name).map((field) => {
      const value = field.value(row)
      return {
        id: field.id,
        label: field.label,
        value,
        mono: !!field.mono,
        inferred: value ? field.inferred?.(row) ?? null : null,
        waiting: !value && !field.fromScan && !details && loading,
      }
    }),
  }))
}

/** The track's title: the file's own tag once read, else the scan's (the file name's stem when untagged). */
export function trackTitle(track: LibraryTrack, details: TrackDetails | undefined): string {
  return details?.tags['title'] ?? track.title
}

/** Whether the title shown is the file's NAME - the file has no title tag (the main page's table marks it). */
export function untitled(track: LibraryTrack, details: TrackDetails | undefined): boolean {
  return details ? !details.tags['title'] : !track.has_title_tag
}

/**
 * Where the track sits, as the main page's track view says it: "Track 3, disc 2 of 2 · <disc title>",
 * then its length and its format - "Unnumbered" for a file with no track number.
 */
export function trackPlace(album: LibraryAlbum, track: LibraryTrack): string {
  const titled = track.disc ? discTitle(album, track.disc) : ''
  const where = [
    track.position !== null ? `Track ${track.position}` : 'Unnumbered',
    album.disc_count > 1 && track.disc ? `disc ${track.disc} of ${album.disc_count}${titled ? ` · ${titled}` : ''}` : '',
  ].filter(Boolean).join(', ')
  return [where, trackTime(track.length), track.format.toUpperCase()].filter(Boolean).join(' · ')
}

/**
 * The tracks either side of this one - `before` is Previous's, `after` Next's - in the album's order (the
 * scan's: disc, then number), and where it is. (Not named previous and next: those are the player's
 * actions' names, which app-rules.sim.cjs finds as members wherever they are written.)
 */
export function trackSteps(album: LibraryAlbum, filename: string): { before: string | null; after: string | null; at: number; count: number } {
  const at = album.tracks.findIndex((track) => track.filename === filename)
  return {
    before: at > 0 ? album.tracks[at - 1]!.filename : null,
    after: at >= 0 && at < album.tracks.length - 1 ? album.tracks[at + 1]!.filename : null,
    at,
    count: album.tracks.length,
  }
}

/** "3 of 11" - where the track is among the album's. */
export function stepWords(steps: { at: number; count: number }): string {
  return steps.at < 0 ? '' : `${steps.at + 1} of ${steps.count}`
}

/** A picture's size - embedded art is usually tens of KB, which formatSize would call 0 MB (the main page's). */
export function pictureBytes(bytes: number): string {
  return bytes < 1024 * 1024 ? `${Math.max(1, Math.round(bytes / 1024))} KB` : formatSize(bytes)
}

/** A picture's facts: its pixel size once it has loaded, its bytes, its format - "500 × 500 · 61 KB · JPEG". */
export function pictureFacts(picture: Pick<EmbeddedPicture, 'size' | 'mime'>, pixels: string | undefined): string {
  return [pixels, pictureBytes(picture.size), picture.mime.replace('image/', '').toUpperCase()].filter(Boolean).join(' · ')
}

/** What "Pictures in this file" says of a file that holds none (the main page's words). */
export const NO_PICTURES = "None - a player shows the album's cover for this song, or its CD art if the song has a disc number."

/**
 * What the lyrics say when the track has none on disk - and, while some of the album's tracks have none,
 * where Get lyrics is: in the panel it is the Lyrics tab (the main page's "above" is its command bar).
 */
export function noLyricsWords(album: Pick<LibraryAlbum, 'lyrics_count' | 'track_count'>): string {
  return `No lyrics for this track on disk.${album.lyrics_count < album.track_count ? ' Get lyrics, in the Lyrics tab, looks for them on LRCLIB.' : ''}`
}

/** Where the lyrics shown came from: the .lrc beside the track, or the file's own tags. */
export function lyricsSource(lyrics: Pick<TrackLyrics, 'source' | 'lyrics_file'>): string {
  return lyrics.source === 'file' ? `From ${lyrics.lyrics_file}` : 'Embedded in the file'
}

/**
 * What one track's lyrics are read again on: the album's folder and the track, the folder's mtime (a
 * fetch writing a .lrc moves it) and how many .lrc files the scan counted - so lyrics just fetched show
 * without leaving the track, as on the main page.
 */
export function lyricsKey(album: Pick<LibraryAlbum, 'path' | 'modified_at' | 'lyrics_count'>, filename: string): string {
  return `${album.path}\n${filename}\n${album.modified_at}\n${album.lyrics_count}`
}

/** "All tags in this file (24)" - the count once the file has been read. */
export function rawTagsTitle(details: TrackDetails | undefined): string {
  return `All tags in this file${details ? ` (${details.raw.length})` : ''}`
}

/**
 * (review) What a screen reader is told of the track shown - "Sour Times, 2 of 11": the name the list
 * showed it by and where it is. The inspector keeps it in a polite live region that is always there, so
 * a step with Previous or Next (focus staying on the button) is spoken, and Back describes itself with
 * it as the inspector opens.
 */
export function trackNow(track: Pick<LibraryTrack, 'title' | 'filename'>, steps: { at: number; count: number }): string {
  return [track.title || track.filename, stepWords(steps)].filter(Boolean).join(', ')
}

/**
 * (review) How far to scroll a box so a row in it shows - the least that does: up to its top, down to its
 * bottom (its top, for a row taller than the box), nothing for a row already in view. Both as the
 * window has them (top and bottom, the box's its visible area). The Edit panel's way back from a track:
 * the list is put back where it was, but Previous and Next may have moved on past the rows that were in
 * view, and focus goes to the track's own name - which must not be out of sight.
 */
export function revealBy(box: { top: number; bottom: number }, row: { top: number; bottom: number }): number {
  if (row.top < box.top) return row.top - box.top
  if (row.bottom > box.bottom) return Math.min(row.bottom - box.bottom, row.top - box.top)
  return 0
}
