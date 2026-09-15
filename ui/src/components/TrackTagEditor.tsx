import { useEffect, useMemo, useState } from 'preact/hooks'

import * as libraryApi from '../api/library'
import type { LibraryAlbum, TagEditPlan, TrackDetails } from '../api/types'
import type { TrackDetailsState } from '../hooks/useTrackDetails'
import {
  buildEdits, EDIT_FIELDS, sharedValue, tagProblem, type EditField, type SharedValue,
} from '../lib/tagEdit'
import { Loading, LoadingPanel } from './Loading'

//? A plan is a server round trip, and every keystroke would be one - the metadata editor's
//? figure, for the same reason: long enough to finish a word, short enough to feel attached.
const PREVIEW_DEBOUNCE_MS = 400

/** Tag names in the preview are the form's own labels, so the two read as one thing. */
const LABELS: Record<string, string> = Object.fromEntries(
  EDIT_FIELDS.map((field) => [field.key, field.label]),
)

interface Props {
  album: LibraryAlbum
  /** The files being edited, in running order. Fixed when the editor opened. */
  filenames: string[]
  /** Every file in the album as read just now - where each field's current value comes from. */
  details: TrackDetailsState
  onClose: () => void
  /** After a write, so the library can reload what changed. */
  onApplied: () => void
}

/**
 * Edit tags by hand: one track, or every ticked track at once.
 *
 * The metadata editor applies a release wholesale, which is right for a mistagged album and
 * wrong for nearly everything else - a genre MusicBrainz doesn't carry, the one track that
 * ended up on the wrong disc. This is the other half, asked for with a selection so that one
 * change can go to many tracks.
 *
 * Only what you edit is written. A field whose value differs across the tracks starts empty and
 * says so, and left alone it keeps each track's own - see buildEdits. Nothing is written until
 * Apply, and the preview beside the fields comes from the same planner the write recomputes.
 */
export function TrackTagEditor({ album, filenames, details, onClose, onApplied }: Props) {
  //? only the fields you have touched, and what you typed into them
  const [draft, setDraft] = useState<Record<string, string>>({})
  const [plan, setPlan] = useState<TagEditPlan | null>(null)
  const [planning, setPlanning] = useState(false)
  const [applying, setApplying] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [applied, setApplied] = useState<string | null>(null)

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') onClose()
    }
    document.addEventListener('keydown', onKeyDown)
    return () => document.removeEventListener('keydown', onKeyDown)
  }, [onClose])

  const files = useMemo(
    () => filenames
      .map((name) => details.files?.get(name))
      .filter((file): file is TrackDetails => Boolean(file)),
    [filenames, details.files],
  )

  //? the fields show what the files say, so there is nothing to show until they have been read
  const ready = files.length === filenames.length

  const shared = useMemo(
    () => Object.fromEntries(EDIT_FIELDS.map((field) => [field.key, sharedValue(files, field.key)])),
    [files],
  ) as Record<string, SharedValue>

  const problems: Record<string, string> = {}
  for (const [key, value] of Object.entries(draft)) {
    const problem = tagProblem(key, value)
    if (problem) problems[key] = problem
  }
  const problemCount = Object.keys(problems).length

  const edits = useMemo(() => buildEdits(filenames, draft), [filenames, draft])

  /*
   * The preview: debounced, and cancelled when superseded, so an answer to what you typed three
   * keys ago can't land on top of the answer to what is in the box now. Nothing is asked while a
   * field is plainly wrong - the server would only refuse it, and the field already says why.
   */
  useEffect(() => {
    if (!edits.length || problemCount) {
      setPlan(null)
      setPlanning(false)
      return
    }

    let cancelled = false
    setPlanning(true)

    const timer = setTimeout(async () => {
      try {
        const next = await libraryApi.previewTagEdits(album.path, edits)
        if (!cancelled) {
          setPlan(next)
          setError(null)
        }
      } catch (caught) {
        if (!cancelled) {
          setPlan(null)
          setError(caught instanceof Error ? caught.message : 'could not work out the changes')
        }
      } finally {
        if (!cancelled) setPlanning(false)
      }
    }, PREVIEW_DEBOUNCE_MS)

    return () => {
      cancelled = true
      clearTimeout(timer)
    }
  }, [album.path, edits, problemCount])

  const edit = (key: string, value: string) => {
    //? the message describes a write that has happened; the moment anything changes it stops
    //? describing what Apply would now do
    setApplied(null)
    setDraft((current) => ({ ...current, [key]: value }))
  }

  const revert = (key: string) => {
    setApplied(null)
    setDraft((current) => {
      const next = { ...current }
      delete next[key]
      return next
    })
  }

  const apply = async () => {
    setApplying(true)
    setError(null)

    try {
      const { results } = await libraryApi.applyTagEdits(album.path, edits)
      const said = [
        `Saved ${results.written} file${results.written === 1 ? '' : 's'}.`,
        ...results.problems,
      ].join(' ')

      if (results.failed) setError(said)
      else setApplied(said)

      //? the preview described a write that has now happened, so it is no longer a preview -
      //? and Apply stays off until there is something new to write
      setPlan(null)
      onApplied()
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'could not save the tags')
    } finally {
      setApplying(false)
    }
  }

  const single = filenames.length === 1
  const heading = single
    ? (files[0]?.tags['title'] ?? filenames[0] ?? 'one track')
    : `${filenames.length} tracks`
  const changed = plan?.files.filter((file) => Object.keys(file.changes).length) ?? []

  return (
    <div id="tags-window" role="dialog" aria-label="Edit tags" onClick={(event) => event.stopPropagation()}>
      <div class="window-titlebar">
        <span class="window-title">Edit tags · {heading}</span>
        <button type="button" class="window-close" title="Close (Esc)" onClick={onClose}>✕</button>
      </div>

      <div class="tags-subject">
        <span class="text white">{album.album}</span>
        <span class="text default-secondary">{album.artist}</span>
        <span class="tags-path text white-tertiary">{album.path}</span>
      </div>

      {!ready ? (
        details.error
          ? <p class="text yellow tags-status">{details.error}</p>
          : <LoadingPanel label="Reading the files…" />
      ) : (
        <div class="tags-body">
          <div class="tags-form scrollable">
            {!single && (
              <details class="tags-tracks">
                <summary>Editing these {filenames.length} tracks</summary>
                <ol class="tags-track-list">
                  {files.map((file) => (
                    <li key={file.filename}>
                      <span class="is-mono">{file.position ?? '·'}</span>
                      <span>{file.tags['title'] ?? file.filename}</span>
                    </li>
                  ))}
                </ol>
              </details>
            )}

            <div class="tags-fields">
              {EDIT_FIELDS.map((field) => (
                <TagField
                  key={field.key}
                  field={field}
                  shared={shared[field.key] ?? { value: '', mixed: false }}
                  draft={draft[field.key]}
                  problem={problems[field.key] ?? null}
                  onEdit={edit}
                  onRevert={revert}
                />
              ))}
            </div>

            <p class="text white-tertiary tags-hint">
              Only the fields you change are written{single ? '' : ', to every track above'}.
              {single ? '' : ' A field showing several values keeps each track’s own unless you type over it.'}
              {' '}Empty a field to remove that tag. No file is renamed and the folder stays where
              it is - the metadata editor re-files an album once its tags say where it belongs.
            </p>
          </div>

          <div class="tags-preview scrollable">
            <h4 class="tags-preview-title">What would change</h4>

            {applied && !plan && <p class="text green tags-status">{applied}</p>}

            {!edits.length && !applied && (
              <p class="text default-muted tags-status">Change a field to see what would be written.</p>
            )}

            {problemCount > 0 && (
              <p class="text yellow tags-status">
                Fix the field{problemCount === 1 ? '' : 's'} marked in yellow first.
              </p>
            )}

            {planning && (
              <p class="tags-status"><Loading label="working out the changes" /></p>
            )}

            {!planning && plan && (
              <>
                {plan.problems.map((problem) => (
                  <p class="text yellow metadata-problem" key={problem}>{problem}</p>
                ))}

                {plan.empty && !plan.problems.length && (
                  <p class="text default-muted tags-status">
                    Nothing to change - {single ? 'the track already says' : 'every track already says'} that.
                  </p>
                )}

                {changed.map((file) => (
                  <div class="metadata-file" key={file.filename}>
                    <div class="metadata-file-name text white">{file.filename}</div>
                    {Object.entries(file.changes).map(([key, change]) => (
                      <div class="metadata-change" key={key}>
                        <span class="metadata-tag text default-secondary">{LABELS[key] ?? key}</span>
                        <span class="metadata-from text white-tertiary">{change.from || '—'}</span>
                        <span class={`metadata-to text ${change.to ? 'default' : 'white-tertiary'}`}>
                          {change.to || 'removed'}
                        </span>
                      </div>
                    ))}
                  </div>
                ))}
              </>
            )}
          </div>
        </div>
      )}

      <div class="tags-footer">
        {error && <span class="text red tags-result">{error}</span>}
        {!error && applied && <span class="text green tags-result">{applied}</span>}
        {!error && !applied && plan && !plan.empty && (
          <span class="text default-muted tags-result">
            {plan.changed_file_count} of {plan.file_count} file{plan.file_count === 1 ? '' : 's'} would change
          </span>
        )}

        <span class="tags-spacer" />

        <button type="button" class="columns-toggle-button" onClick={onClose}>
          {applied ? 'Close' : 'Cancel'}
        </button>

        {/*
          Writes tags to disk with no undo, like the metadata editor's Apply - so it gets the same
          solid accent, and must not look like the Cancel beside it.
        */}
        <button
          type="button"
          id="tags-apply-button"
          disabled={
            !plan || plan.empty || plan.problems.length > 0 || planning || applying || problemCount > 0
          }
          onClick={() => void apply()}
        >
          {applying ? <Loading label="Saving" /> : 'Apply'}
        </button>
      </div>
    </div>
  )
}

/** One field: what the files say, what you typed over it, and anything wrong with that. */
function TagField(
  { field, shared, draft, problem, onEdit, onRevert }:
  {
    field: EditField
    shared: SharedValue
    draft: string | undefined
    problem: string | null
    onEdit: (key: string, value: string) => void
    onRevert: (key: string) => void
  },
) {
  const edited = draft !== undefined
  const id = `tag-field-${field.key}`

  //? emptying a field removes the tag - but only from tracks that have one to remove
  const removing = edited && !draft.trim() && (shared.mixed || shared.value !== '')

  const placeholder = shared.mixed && !edited
    ? 'Several values'
    //? a disc number defaults to 1, so an untagged one says so rather than looking blank
    : field.key === 'discnumber' ? '1' : 'Not set'

  const note = problem
    ?? (removing ? 'Will be removed' : null)
    ?? (shared.mixed && !edited ? 'Differs between tracks - left alone, each keeps its own' : null)
    ?? (field.key === 'discnumber' && !edited && !shared.value ? 'Not tagged - reads as disc 1' : null)

  return (
    <div
      class={[
        'tags-field',
        field.short ? 'is-short' : '',
        edited ? 'is-edited' : '',
        problem ? 'has-problem' : '',
      ].filter(Boolean).join(' ')}
    >
      <div class="tags-field-head">
        <label class="tags-field-label" for={id}>{field.label}</label>
        {edited && (
          <button
            type="button"
            class="tags-revert"
            title="Put back what the files say"
            onClick={() => onRevert(field.key)}
          >
            undo
          </button>
        )}
      </div>

      <input
        id={id}
        class="releases-filter-input"
        value={edited ? draft : shared.value}
        placeholder={placeholder}
        inputMode={field.numeric ? 'numeric' : 'text'}
        spellcheck={false}
        autocomplete="off"
        onInput={(event) => onEdit(field.key, (event.currentTarget as HTMLInputElement).value)}
      />

      {note && <span class={`tags-field-note text ${problem ? 'yellow' : 'white-tertiary'}`}>{note}</span>}
    </div>
  )
}
