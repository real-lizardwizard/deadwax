import { useEffect, useLayoutEffect, useRef, useState } from 'preact/hooks'

import { AlbumPage } from './AlbumPage'
import { Library } from './Library'
import { MiniPlayer } from './MiniPlayer'
import { NowPlaying } from './NowPlaying'
import { navidromeStatus, type Album, type NavidromeStatus } from './api'
import { usePlayer } from './usePlayer'

/** The album in the address, `#/album/<id>`, or null for the library. */
function albumInHash(): string | null {
  const match = /^#\/album\/(.+)$/.exec(location.hash)
  return match?.[1] ? decodeURIComponent(match[1]) : null
}

/** Before there is anything to play: why not, and what to do about it. */
function Unavailable({ status, onRetry }: { status: NavidromeStatus | null; onRetry: () => void }) {
  if (!status) return <div class="pl-spinner is-page" aria-label="Connecting" />

  return (
    <section class="pl-setup">
      <h1 class="pl-large-title">{status.configured ? "Can't reach Navidrome" : 'Connect Navidrome'}</h1>
      <p>{status.problem}</p>
      {status.configured ? (
        <button type="button" class="pl-pill" onClick={onRetry}>
          Try again
        </button>
      ) : (
        <p class="pl-setup-hint">
          The player plays your library from Navidrome, through deadwax - so the phone never needs
          Navidrome's password. Set it up in the <a href="/">settings tab</a>, then come back.
        </p>
      )}
    </section>
  )
}

/**
 * The player: the library, one album, and what's playing.
 *
 * The album is in the address so that iOS's swipe back and the back button both work. The
 * library stays mounted while an album is open - hidden, not thrown away - so coming back finds
 * the grid as it was, pages loaded and scrolled to where you left it.
 */
export function PlayerApp() {
  const player = usePlayer()
  const [status, setStatus] = useState<NavidromeStatus | null>(null)
  const [albumId, setAlbumId] = useState(albumInHash)
  const [preview, setPreview] = useState<Album | null>(null)
  const [sheetOpen, setSheetOpen] = useState(false)
  const libraryScroll = useRef(0)
  //? whether the open album was reached from the library, so "back" can be history's own back
  const cameFromLibrary = useRef(false)

  function check() {
    setStatus(null)
    navidromeStatus()
      .then(setStatus)
      .catch((reason: unknown) =>
        setStatus({ configured: true, ok: false, server: null, problem: String(reason) }),
      )
  }

  useEffect(check, [])

  useEffect(() => {
    history.scrollRestoration = 'manual'
    const onHash = () => setAlbumId(albumInHash())
    window.addEventListener('hashchange', onHash)
    return () => window.removeEventListener('hashchange', onHash)
  }, [])

  useLayoutEffect(() => {
    window.scrollTo(0, albumId ? 0 : libraryScroll.current)
  }, [albumId])

  function openAlbum(album: Album) {
    libraryScroll.current = window.scrollY
    cameFromLibrary.current = true
    setPreview(album)
    location.hash = `#/album/${encodeURIComponent(album.id)}`
  }

  function back() {
    if (cameFromLibrary.current) {
      cameFromLibrary.current = false
      history.back()
    } else {
      history.replaceState(null, '', location.pathname)
      setAlbumId(null)
    }
  }

  if (!status?.ok) return <Unavailable status={status} onRetry={check} />

  return (
    <div class={`pl-app${player.track ? ' has-mini' : ''}`}>
      <div hidden={albumId !== null}>
        <Library onOpen={openAlbum} />
      </div>
      {albumId !== null && <AlbumPage id={albumId} preview={preview} player={player} onBack={back} />}

      <MiniPlayer player={player} onOpen={() => setSheetOpen(true)} />
      <NowPlaying player={player} open={sheetOpen} onClose={() => setSheetOpen(false)} />
    </div>
  )
}
