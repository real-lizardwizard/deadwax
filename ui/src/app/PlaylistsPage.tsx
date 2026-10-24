import { useEffect, useRef, useState } from 'preact/hooks'

import { createPlaylist, type Playlist } from '../api/playlists'
import { PLAYLISTS_EMPTY, PLAYLISTS_EMPTY_HOW, groupPlaylists, listFailed, rowLine } from '../lib/playlists'
import { Cover } from '../player/Cover'
import { ChevronLeftIcon, ChevronRightIcon, PlaylistIcon } from '../player/icons'
import { NewPlaylistForm } from './NewPlaylistForm'
import { sayPins } from './usePins'
import { announcePlaylistChanged, askPlaylists, usePlaylists } from './usePlaylists'

/**
 * The Playlists page (2.0.0-player.58, `#/<tab>/playlists/all`): pushed on the Library tab - from the phone
 * Library's Playlists row, or the desktop sidebar's All playlists - inside the Navidrome gate. Yours, then Shared
 * with you, then From files folded behind one row ("From files (N)", opened in place for the page's life), each
 * in Navidrome's order (by name) and drawn only when it has something (lib/playlists.ts groupPlaylists). A row
 * OPENS its playlist and plays nothing.
 *
 * New playlist, at the bar's right, opens the form at the top of the list (NewPlaylistForm); made, the new
 * playlist's page opens over this one, its answer kept so it draws at once - while this page is still what shows
 * (review: made after a tap elsewhere, it would have been pushed on whatever tab showed then; the notice says it
 * instead). The list is asked afresh as the page
 * first draws and each time it becomes what shows (`shown`: its tab current, the app in front); what the store
 * holds draws meanwhile, and a failure with something held leaves the list and says so under the title.
 */
export function PlaylistsPage({
  onBack,
  backLabel,
  shown,
  onOpenPlaylist,
}: {
  onBack: () => void
  backLabel: string
  shown: boolean
  onOpenPlaylist: (playlist: Playlist) => void
}) {
  const { list, problem } = usePlaylists()
  const [making, setMaking] = useState(false)
  const [filesOpen, setFilesOpen] = useState(false)
  const newButton = useRef<HTMLButtonElement>(null)
  //? whether this page is still what shows - mounted, and `shown` - when a Create answers
  const here = useRef(shown)
  here.current = shown
  useEffect(() => () => {
    here.current = false
  }, [])

  useEffect(() => {
    if (shown) askPlaylists({ fresh: true })
  }, [shown])

  const make = (name: string) =>
    createPlaylist(name, []).then((made) => {
      announcePlaylistChanged(made.playlist.id, made)
      setMaking(false)
      if (here.current) onOpenPlaylist(made.playlist)
      else sayPins(`Made ${made.playlist.name}`)
    })
  const cancel = () => {
    setMaking(false)
    newButton.current?.focus({ preventScroll: true })
  }

  const groups = list ? groupPlaylists(list) : null
  const row = (playlist: Playlist) => (
    <li key={playlist.id}>
      <button type="button" class="app-result app-playlist-row" onClick={() => onOpenPlaylist(playlist)}>
        <span class="app-playlist-art">
          {playlist.coverArt ? <Cover id={playlist.coverArt} size={112} class="app-playlist-art-img" /> : <PlaylistIcon class="app-playlist-art-icon" />}
        </span>
        <span class="app-result-text">
          <span class="app-result-title" dir="auto">{playlist.name}</span>
          <span class="app-result-line">{rowLine(playlist)}</span>
        </span>
        <ChevronRightIcon class="app-chevron" />
      </button>
    </li>
  )

  return (
    <section class="app-playlists-page">
      <header class="pl-nav-bar app-album-bar">
        <button type="button" class="pl-back" onClick={onBack}>
          <ChevronLeftIcon class="pl-back-icon" />
          <span class="pl-back-label">{backLabel}</span>
        </button>
        <button ref={newButton} type="button" class="app-text-button app-playlists-new" aria-expanded={making} onClick={() => setMaking(true)}>
          New playlist
        </button>
      </header>
      <header class="pl-large-header">
        <h1 class="pl-large-title">Playlists</h1>
      </header>
      {problem && list !== null && <p class="app-store-line is-refused app-playlists-problem">{listFailed(problem)}</p>}

      {making && (
        <div class="app-playlists-form">
          <NewPlaylistForm onCreate={make} onCancel={cancel} />
        </div>
      )}

      {list === null ? (
        problem ? (
          <div class="pl-notice">
            <p>{listFailed(problem)}</p>
            <button type="button" class="pl-text-button" onClick={() => askPlaylists({ fresh: true })}>
              Try again
            </button>
          </div>
        ) : (
          <div class="pl-spinner" aria-label="Loading" />
        )
      ) : !list.length ? (
        !making && (
          <div class="pl-notice app-playlists-empty">
            <p class="app-playlists-empty-lead">{PLAYLISTS_EMPTY}</p>
            <p>{PLAYLISTS_EMPTY_HOW}</p>
            <button type="button" class="app-button app-playlists-empty-new" onClick={() => setMaking(true)}>
              New playlist
            </button>
          </div>
        )
      ) : (
        groups && (
          <>
            {groups.yours.length > 0 && (
              <section class="app-playlists-group" aria-labelledby="app-playlists-yours">
                <h2 id="app-playlists-yours" class="app-section-title app-playlists-heading">Yours</h2>
                <ul class="app-results app-playlists-list">{groups.yours.map(row)}</ul>
              </section>
            )}
            {groups.shared.length > 0 && (
              <section class="app-playlists-group" aria-labelledby="app-playlists-shared">
                <h2 id="app-playlists-shared" class="app-section-title app-playlists-heading">Shared with you</h2>
                <ul class="app-results app-playlists-list">{groups.shared.map(row)}</ul>
              </section>
            )}
            {groups.files.length > 0 && (
              <section class="app-playlists-group">
                <h2 class="app-section-title app-playlists-heading">
                  <button type="button" class="app-playlists-fold" aria-expanded={filesOpen} onClick={() => setFilesOpen(!filesOpen)}>
                    <span>From files ({groups.files.length})</span>
                    <ChevronRightIcon class={`app-chevron app-playlists-fold-icon${filesOpen ? ' is-open' : ''}`} />
                  </button>
                </h2>
                {filesOpen && <ul class="app-results app-playlists-list">{groups.files.map(row)}</ul>}
              </section>
            )}
          </>
        )
      )}
    </section>
  )
}
