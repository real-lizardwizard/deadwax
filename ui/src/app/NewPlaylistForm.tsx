import { useLayoutEffect, useRef, useState } from 'preact/hooks'

import { PLAYLIST_NAME_MAX } from '../lib/playlists'
import { sayError } from './sayError'

/**
 * New playlist's form (2.0.0-player.58) - the Playlists page's and the picker's: a Name field, Create and Cancel.
 * Enter creates; Escape cancels the form and nothing else (its handler calls preventDefault, so a sheet around it -
 * the picker - stays open). Create is aria-disabled while the name is blank and while it is out ("Creating…");
 * refused, the form stays with the reason under it. The field takes focus as the form opens, its text at least
 * 16px (app.css) so iOS doesn't zoom.
 *
 * A leaf: `onCreate` makes the playlist and resolves once it is made (the parent takes it from there) or rejects
 * with why, which the form says.
 */
export function NewPlaylistForm({ onCreate, onCancel }: { onCreate: (name: string) => Promise<unknown>; onCancel: () => void }) {
  const [name, setName] = useState('')
  const [busy, setBusy] = useState(false)
  const [problem, setProblem] = useState<string | null>(null)
  const field = useRef<HTMLInputElement>(null)
  const sending = useRef(false)

  useLayoutEffect(() => {
    field.current?.focus({ preventScroll: true })
  }, [])

  const blank = !name.trim()
  const create = () => {
    if (blank || sending.current) return
    sending.current = true
    setBusy(true)
    setProblem(null)
    onCreate(name.trim()).then(
      () => {
        sending.current = false
        setBusy(false)
      },
      (caught: unknown) => {
        sending.current = false
        setBusy(false)
        setProblem(sayError(caught))
      },
    )
  }

  return (
    <form
      class="app-new-playlist"
      onSubmit={(event) => {
        event.preventDefault()
        create()
      }}
    >
      <label class="app-new-playlist-field">
        <span class="app-new-playlist-label">Name</span>
        <input
          ref={field}
          class="app-new-playlist-input"
          type="text"
          value={name}
          maxLength={PLAYLIST_NAME_MAX}
          enterKeyHint="done"
          autoCapitalize="sentences"
          autoComplete="off"
          onInput={(event) => setName((event.currentTarget as HTMLInputElement).value)}
          onKeyDown={(event) => {
            if (event.key !== 'Escape') return
            event.preventDefault()
            onCancel()
          }}
        />
      </label>
      <div class="app-new-playlist-buttons">
        <button type="submit" class="app-button is-primary app-new-playlist-create" aria-disabled={blank || busy}>
          {busy ? 'Creating…' : 'Create'}
        </button>
        <button type="button" class="app-button app-new-playlist-cancel" onClick={onCancel}>
          Cancel
        </button>
      </div>
      {problem && (
        <p class="app-store-line is-refused" role="alert">
          {problem}
        </p>
      )}
    </form>
  )
}
