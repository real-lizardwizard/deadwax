import { useEffect, useState } from 'preact/hooks'

import * as libraryApi from '../api/library'
import type { DeletionSummary, LibraryAlbum } from '../api/types'
//? (2.1.30) its words, pure - moved there unchanged
import {
  DELETE_CHECKING, DELETE_CONFIRM, DELETE_FAILED, DELETE_READ_FAILED, DELETE_TITLE, DELETE_WARNING, DELETING, deleteCounts, deleteOthers,
} from '../lib/albumEdit'
import { holdersText } from '../lib/myLibrary'
import { Loading, LoadingPanel } from './Loading'
import { sayError } from '../app/sayError'

interface Props {
  album: LibraryAlbum
  onCancel: () => void
  /** Called once the folder is gone, so the library can drop it from the list. */
  onDeleted: () => void
}

/**
 * Confirm deleting an album.
 *
 * The summary is fetched live rather than taken from the album the library already has,
 * because the point of a confirmation is to describe what is about to happen to the disk
 * right now - and because the scan ignores files this doesn't. A rip log or a cue sheet in
 * that folder might be the only copy, so they're named individually before they go.
 *
 * Deliberately not a browser confirm(): it can't show any of that, and this is the one
 * action in deadwax with no undo.
 *
 * With logins on (2.0.0-player.51) it names who has the album in their library (the summary's
 * `holders`, and `yours` for the admin deleting it): deleting it turns each of theirs into "removed by
 * the admin, request it again" - and says so when deadwax couldn't read who has it, never "nobody".
 */
export function DeleteAlbumDialog({ album, onCancel, onDeleted }: Props) {
  const [summary, setSummary] = useState<DeletionSummary | null>(null)
  const [loading, setLoading] = useState(true)
  const [deleting, setDeleting] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      //? Escape cancels; Enter deliberately does NOT confirm. The destructive button should
      //? take a deliberate click rather than a keypress you might already be making.
      if (event.key === 'Escape') onCancel()
    }
    document.addEventListener('keydown', onKeyDown)
    return () => document.removeEventListener('keydown', onKeyDown)
  }, [onCancel])

  useEffect(() => {
    let cancelled = false

    void (async () => {
      try {
        const result = await libraryApi.deletionSummary(album.path)
        if (!cancelled) setSummary(result)
      } catch (caught) {
        if (!cancelled) setError(sayError(caught, '', { failed: DELETE_READ_FAILED }))
      } finally {
        if (!cancelled) setLoading(false)
      }
    })()

    return () => { cancelled = true }
  }, [album.path])

  const confirm = async () => {
    setDeleting(true)
    setError(null)

    try {
      await libraryApi.deleteAlbum(album.path)
      onDeleted()
    } catch (caught) {
      setError(sayError(caught, '', { failed: DELETE_FAILED }))
      setDeleting(false)
    }
  }

  //? the other files, named - null with none (lib/albumEdit.ts)
  const others = summary ? deleteOthers(summary) : null

  return (
    <div id="delete-window" onClick={(event) => event.stopPropagation()}>
      <div id="delete-panel">
        <h4 class="text red">{DELETE_TITLE}</h4>

        <div class="delete-subject">
          <span class="text white">{album.album}</span>
          <span class="text default-secondary">{album.artist}</span>
          {album.edition && <span class="library-edition">{album.edition}</span>}
        </div>

        <div class="text white-tertiary delete-path">{album.path}</div>

        {loading && <LoadingPanel label={DELETE_CHECKING} />}

        {error && <h5 class="text red delete-problem">{error}</h5>}

        {summary && (
          <>
            <div class="text default-muted delete-counts">{deleteCounts(summary)}</div>

            {/* named individually, because these are the ones that might not exist elsewhere */}
            {others && (
              <div class="delete-others">
                <span class="text yellow">{others.lead}</span>
                <span class="text white-tertiary">{others.names}</span>
              </div>
            )}
          </>
        )}

        {/* (2.0.0-player.51, logins on) whose libraries it is in - deleting it takes it out of them */}
        {summary && holdersText(summary) && (
          <p class="text yellow delete-warning delete-holders">{holdersText(summary)}</p>
        )}

        <p class="text red delete-warning">{DELETE_WARNING}</p>

        <div id="delete-actions">
          <button type="button" class="columns-toggle-button" disabled={deleting} onClick={onCancel}>
            Cancel
          </button>
          <button
            type="button"
            id="delete-confirm-button"
            disabled={loading || deleting || !summary}
            onClick={() => void confirm()}
          >
            {deleting ? <Loading label={DELETING} /> : DELETE_CONFIRM}
          </button>
        </div>
      </div>
    </div>
  )
}
