import { useMemo } from 'preact/hooks'

import type { LibraryAlbum } from '../api/types'
import { folderChoices, folderChoicesWords } from '../lib/albumEdit'

/**
 * "Choose the folder" (2.0.0-player.42): the library's scan as a list of folders, narrowed by typing -
 * every word somewhere in a folder's path, artist or album (lib/albumEdit.ts folderChoices) - the first
 * FOLDER_CHOICES_SHOWN of them drawn, and how many match said over them. A folder clicked is the one the
 * panel edits from then on.
 */
export function FolderPicker({
  albums,
  typed,
  onType,
  onPick,
}: {
  albums: readonly LibraryAlbum[]
  typed: string
  onType: (typed: string) => void
  onPick: (path: string) => void
}) {
  const { shown, matching } = useMemo(() => folderChoices(albums, typed), [albums, typed])
  return (
    <div class="app-edit-state app-edit-pick">
      <label class="app-edit-pick-field">
        <span class="app-edit-label">Folder</span>
        <input
          class="app-edit-pick-input"
          type="search"
          value={typed}
          placeholder="Name, artist or path"
          spellcheck={false}
          autoComplete="off"
          aria-controls={shown.length ? 'app-edit-pick-list' : undefined}
          onInput={(event) => onType((event.currentTarget as HTMLInputElement).value)}
        />
      </label>
      <p class="app-edit-note" role="status">{folderChoicesWords(shown.length, matching, typed)}</p>
      {shown.length > 0 && (
        <ul id="app-edit-pick-list" class="app-edit-choices" aria-label="Folders in the library">
          {shown.map((album) => (
            <li key={album.path}>
              <button type="button" class="app-edit-choice app-edit-pick-choice" onClick={() => onPick(album.path)}>
                <span class="app-edit-pick-path">{album.path}</span>
                <span class="app-edit-pick-sub">
                  {[album.artist, album.album].filter(Boolean).join(' - ') || 'No artist or album tags'}
                  {album.release_mbid ? '' : ' · no release'}
                </span>
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}
