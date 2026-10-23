import { Fragment } from 'preact'
import { useEffect, useMemo, useRef, useState } from 'preact/hooks'

import { trackLyrics } from '../api/library'
import type { LibraryAlbum, TrackDetails, TrackLyrics } from '../api/types'
import type { ViewerImage } from '../components/ArtViewer'
import { Loading } from '../components/Loading'
import type { TrackDetailsState } from '../hooks/useTrackDetails'
import { trackPictureUrl } from '../lib/format'
import { isAbort, latestOnly } from '../lib/latest'
import { lyricTime } from '../lib/lyrics'
import {
  NO_PICTURES, inspectorGroups, lyricsKey, lyricsSource, noLyricsWords, pictureFacts, rawTagsTitle, stepWords, trackNow,
  trackPlace, trackSteps, trackTitle, untitled,
} from '../lib/trackInspector'
import { ChevronLeftIcon, ChevronRightIcon } from '../player/icons'
import { CoverViewer } from './CoverViewer'
import { takeOpener } from './useSheet'

/** The inspector's line for a screen reader (one inspector at a time, the panel's). */
const NOW_ID = 'app-inspect-now'

/**
 * Inside a track, in the app (2.0.0-player.44): the Edit panel's Tags tab, a track's name tapped - its
 * inspector, a view pushed over the track list, with Back to it. The main page's track view as it
 * was (its LibraryDetails.tsx's TrackDetailsView, retired with it in 2.0.0-player.66), read for a panel
 * 390 to 470px wide:
 *
 *  - EVERY field the main page offered (lib/trackFields.ts's registry, not only the ones its Fields menu
 *    showed), grouped as it grouped them - Tags, Audio, MusicBrainz, File - each its value, or a dash for a
 *    field the file lacks, '…' while the file is still being read and the scan can't say, and the dimmed
 *    disc 1 of a file with no disc tag, saying why (lib/trackInspector.ts inspectorGroups). From the
 *    panel's useTrackDetails (`/library/tracks`, the files as they are now), as the main page read them;
 *  - "Pictures in this file": each embedded picture, its type, its pixel size once it has loaded, its
 *    bytes and format - a tap opens it in the cover viewer (CoverViewer: the main page's ArtViewer);
 *  - the track's lyrics: the .lrc beside it, else the file's own, synced lines with their times and
 *    the gaps between verses, where they came from - asked when the track shows, and again when the
 *    folder changes (a fetch writing a .lrc), through a latestOnly(): stepping on from a track never
 *    draws its lyrics over the next one's;
 *  - "All tags in this file": every tag under its container's own name, and the file's name;
 *  - Previous and Next (aria-disabled at the ends, so focus stays on them), and "Edit this track…",
 *    the main page's tag editor on this one file alone;
 *  - (review) for a screen reader, the track shown and where it is ("Sour Times, 2 of 11") in a polite
 *    live region that is always there - spoken on every step - and Back described by it as it opens.
 *
 * Read only - it writes nothing, and nothing about the tag editor or its rules changes. What it is
 * handed to do (back, a step, the tag editor) is the panel's: the panel keeps focus inside it and
 * gives Escape to this layer first (app/EditPanel.tsx). It plays nothing.
 */
export function TrackInspector({
  album,
  filename,
  details,
  onBack,
  onStep,
  onEdit,
}: {
  album: LibraryAlbum
  filename: string
  details: TrackDetailsState
  onBack: () => void
  onStep: (filename: string) => void
  onEdit: (filename: string) => void
}) {
  const track = album.tracks.find((each) => each.filename === filename)
  const [viewing, setViewing] = useState<ViewerImage[] | null>(null)
  const opener = useRef<HTMLElement | null>(null)
  if (!track) return null

  const file = details.files?.get(filename)
  const groups = inspectorGroups(track, file, details.loading)
  const steps = trackSteps(album, filename)
  const view = (event: MouseEvent, images: ViewerImage[]) => {
    opener.current = takeOpener(event)
    setViewing(images)
  }

  return (
    <div class="app-inspect">
      {/* (review) for a screen reader: the track shown, spoken as Previous or Next steps (focus staying on
          the button) - a polite region that is always there, which iOS needs to read one - and Back's
          description as the inspector opens, focus going to it */}
      <p id={NOW_ID} class="app-visually-hidden" role="status" aria-live="polite" aria-atomic="true">{trackNow(track, steps)}</p>
      <div class="app-inspect-bar">
        <button type="button" class="app-edit-button app-inspect-button app-inspect-back" aria-describedby={NOW_ID} onClick={onBack}>
          <ChevronLeftIcon class="app-inspect-icon" />
          Tracks
        </button>
        <span class="app-inspect-count">{stepWords(steps)}</span>
      </div>

      <header class="app-inspect-head">
        <h3 class="app-inspect-title">{trackTitle(track, file)}</h3>
        {untitled(track, file) && <p class="app-inspect-note">No title tag - this is the file's name.</p>}
        <p class="app-inspect-place">{trackPlace(album, track)}</p>
        <div class="app-inspect-actions">
          <button
            type="button"
            class="app-edit-button app-inspect-button app-inspect-prev"
            aria-disabled={steps.before ? undefined : 'true'}
            onClick={() => {
              if (steps.before) onStep(steps.before)
            }}
          >
            <ChevronLeftIcon class="app-inspect-icon" />
            Previous
          </button>
          <button
            type="button"
            class="app-edit-button app-inspect-button app-inspect-next"
            aria-disabled={steps.after ? undefined : 'true'}
            onClick={() => {
              if (steps.after) onStep(steps.after)
            }}
          >
            Next
            <ChevronRightIcon class="app-inspect-icon" />
          </button>
          <button type="button" class="app-edit-button app-inspect-button app-inspect-edit" onClick={() => onEdit(filename)}>
            Edit this track…
          </button>
        </div>
      </header>

      {details.error && <p class="app-inspect-warn">{details.error}</p>}

      {groups.map((group) => (
        <section key={group.name} class="app-inspect-group">
          <h4 class="app-inspect-heading">{group.name}</h4>
          <dl class="app-inspect-fields">
            {group.fields.map((field) => (
              <Fragment key={field.id}>
                <dt class="app-inspect-label">{field.label}</dt>
                <dd
                  class={`app-inspect-value${field.mono && field.value ? ' is-mono' : ''}${field.inferred ? ' is-inferred' : ''}${field.value ? '' : ' is-empty'}`}
                  title={field.inferred ?? undefined}
                >
                  {field.value || (field.waiting ? '…' : '—')}
                </dd>
              </Fragment>
            ))}
          </dl>
        </section>
      ))}

      <InspectorPictures album={album} file={file} loading={details.loading} onView={view} />

      <InspectorLyrics album={album} filename={filename} />

      {/* every tag the file carries, under its container's own name - the ones no field knows included */}
      <details class="app-inspect-raw">
        <summary class="app-inspect-summary">{rawTagsTitle(file)}</summary>
        {!file && details.loading && <Loading label="reading the file" />}
        {file && (
          <>
            <dl class="app-inspect-fields is-raw">
              {file.raw.map(([key, value], index) => (
                <Fragment key={`${key} ${index}`}>
                  <dt class="app-inspect-label is-mono" title={key}>{key}</dt>
                  <dd class="app-inspect-value">{value}</dd>
                </Fragment>
              ))}
            </dl>
            <p class="app-inspect-file">{filename}</p>
          </>
        )}
      </details>

      <CoverViewer images={viewing} onClose={() => setViewing(null)} opener={opener} />
    </div>
  )
}

/**
 * The pictures stored inside the file - a player shows a song's OWN picture in place of its album's
 * cover, which is how a song comes to show a sleeve that doesn't match. Each labelled with its declared
 * type, its real pixel size once it loads (measured by the browser, as the main page measured it), its bytes and
 * format; a tap opens it full size.
 */
function InspectorPictures({
  album,
  file,
  loading,
  onView,
}: {
  album: LibraryAlbum
  file: TrackDetails | undefined
  loading: boolean
  onView: (event: MouseEvent, images: ViewerImage[]) => void
}) {
  const [pixels, setPixels] = useState<Record<string, string>>({})
  const pictures = file?.pictures ?? []
  const url = (index: number) => trackPictureUrl(album.path, file?.filename ?? '', index, album.modified_at)

  return (
    <section class="app-inspect-group">
      <h4 class="app-inspect-heading">Pictures in this file</h4>
      {!file ? (
        loading ? <Loading label="reading the file" /> : null
      ) : !pictures.length ? (
        <p class="app-inspect-note">{NO_PICTURES}</p>
      ) : (
        <div class="app-inspect-pictures">
          {pictures.map((picture) => {
            const key = `${file.filename}:${picture.index}`
            return (
              <button
                key={key}
                type="button"
                class="app-inspect-picture"
                aria-label={`${picture.label} - see it full size`}
                onClick={(event) => onView(event as unknown as MouseEvent, [{ label: `${picture.label} · ${file.filename}`, sources: [url(picture.index)] }])}
              >
                <img
                  class="app-inspect-picture-img"
                  src={url(picture.index)}
                  alt=""
                  onLoad={(event) => {
                    const img = event.currentTarget as HTMLImageElement
                    setPixels((known) => ({ ...known, [key]: `${img.naturalWidth} × ${img.naturalHeight}` }))
                  }}
                />
                <span class="app-inspect-picture-words">
                  <span class="app-inspect-picture-label">{picture.label}</span>
                  <span class="app-inspect-picture-facts">{pictureFacts(picture, pixels[key])}</span>
                </span>
              </button>
            )
          })}
        </div>
      )}
    </section>
  )
}

/**
 * One track's lyrics, read from disk as the track shows - never carried in the scan - and again when the
 * album's folder changes (lib/trackInspector.ts lyricsKey). Through a latestOnly(): only the newest
 * answer is drawn, so a step to the next track never shows the last one's words under its name.
 */
function InspectorLyrics({ album, filename }: { album: LibraryAlbum; filename: string }) {
  const requests = useMemo(latestOnly, [])
  const key = lyricsKey(album, filename)
  const [state, setState] = useState<{ key: string; lyrics?: TrackLyrics; error?: string } | null>(null)

  useEffect(() => {
    const ticket = requests.begin()
    setState({ key })
    trackLyrics(album.path, filename, ticket.signal).then(
      (lyrics) => {
        if (ticket.current()) setState({ key, lyrics })
      },
      (reason: unknown) => {
        if (ticket.current() && !isAbort(reason)) setState({ key, error: reason instanceof Error ? reason.message : String(reason) })
      },
    )
    return () => requests.supersede()
  }, [key])

  const current = state?.key === key ? state : null
  const lyrics = current?.lyrics

  return (
    <section class="app-inspect-group">
      <h4 class="app-inspect-heading">
        Lyrics
        {lyrics?.synced && <span class="app-inspect-mark">synced</span>}
      </h4>
      {!current || (!current.lyrics && !current.error) ? (
        <Loading label="reading lyrics" />
      ) : current.error ? (
        <p class="app-inspect-warn">{current.error}</p>
      ) : !lyrics?.lines.length ? (
        <p class="app-inspect-note">{noLyricsWords(album)}</p>
      ) : (
        <>
          <div class={`app-inspect-lyrics${lyrics.synced ? ' is-synced' : ''}`}>
            {lyrics.lines.map((line, index) =>
              //? an empty synced line is a break in the singing: the space, never a time beside nothing
              line.text ? (
                <p key={index} class="app-inspect-line">
                  {lyrics.synced && <span class="app-inspect-time">{line.time === null ? '' : lyricTime(line.time)}</span>}
                  <span class="app-inspect-words">{line.text}</span>
                </p>
              ) : (
                <p key={index} class="app-inspect-line is-gap" aria-hidden="true" />
              ),
            )}
          </div>
          <p class="app-inspect-note">{lyricsSource(lyrics)}</p>
        </>
      )}
    </section>
  )
}
