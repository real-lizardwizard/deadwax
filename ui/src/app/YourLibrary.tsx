import { useEffect, useLayoutEffect, useRef, useState } from 'preact/hooks'

import { dismissRemoved } from '../api/me'
import type { MyLibrary } from '../api/types'
import { REMOVED_WORDS, entryName, libraryLine, loginWords, nextFocus, waitingGroups, waitingText } from '../lib/myLibrary'
import { askMyLibrary, hasLibrary, useMyLibrary } from './useMyLibrary'
import { TELL } from '../lib/errorWords'
import { gets } from '../lib/permissions'
import { accessNow, seesDetail, useAccess } from './access'
import { sayError } from './sayError'

/** Focus fell to the page (or was never taken) - the only time a row leaving moves it. */
const focusLost = (): boolean => {
  if (typeof document === 'undefined') return false
  const active = document.activeElement
  return !active || active === document.body
}

/** (2.0.4) Your library when deadwax can't read its database - "Tell whoever runs deadwax." after it for anyone who
 *  doesn't run it. */
export const LIBRARY_UNREAD = "deadwax can't read its database, so it can't say what your library holds."

/**
 * You > Your library (2.0.0-player.51, personal libraries): with logins on, how many albums your library
 * holds - your starred albums in Navidrome - and how far deadwax has got starring them: what still waits
 * and why (a few named a reason, then "and N more"), above all that Navidrome no longer takes the login
 * you signed in with ("sign in again"); and the albums an admin deleted ("Removed by an admin."), each with
 * Get it again (its album page, where Get is - only for someone who may Get) and Dismiss (2.0.5's words: Request it
 * again, Put away). Asked each time You's
 * tab comes into view (`current`). Nothing at all with logins off, or for the break-glass admin (no
 * Navidrome account, no library).
 *
 * A row dismissed leaves the page once deadwax answers; its focus goes to the row now in its place (else
 * the one before it, else the section's heading), and "<album> dismissed" is said - never dropped to the
 * page (review; the app's rule, as Pinned's unpin).
 */
export function YourLibrary({
  current,
  onRequestAgain,
}: {
  current: boolean
  /** the album's page, where Get is - by its release group */
  onRequestAgain?: ((group: { id: string; title: string }) => void) | undefined
}) {
  const library = useMyLibrary()
  //? (2.0.5 review) Get it again only for someone who may Get - for anyone else its page says "Getting albums is off
  //? for you", so the button promised what they can't do; Dismiss stays for everyone (as Search, ReleaseGroupPage and
  //? JobCard gate Get)
  const getsAlbums = gets(useAccess().permissions)
  const [putting, setPutting] = useState<number | null>(null)
  const [problem, setProblem] = useState<string | null>(null)
  const [said, setSaid] = useState('')
  //? the album being put away, at once - a second tap before the page draws again asks nothing more
  const acting = useRef<number | null>(null)
  const list = useRef<HTMLUListElement | null>(null)
  const heading = useRef<HTMLHeadingElement | null>(null)
  //? where focus goes once a put-away row has left: `to` (an album id), or the heading for null - asked
  //? of the answer after `answer`, the one the row was put away in
  const refocus = useRef<{ gone: number; to: number | null; answer: MyLibrary | null } | null>(null)

  useEffect(() => {
    if (current) askMyLibrary()
  }, [current])

  useLayoutEffect(() => {
    const wanted = refocus.current
    if (!wanted || library === wanted.answer) return
    refocus.current = null
    //? still there (asking again failed, or it came back): nothing moves
    if ((library?.removed ?? []).some((entry) => entry.album_id === wanted.gone) || !focusLost()) return
    const row = wanted.to === null || !list.current
      ? null
      : [...list.current.querySelectorAll<HTMLElement>('[data-album]')].find((each) => each.dataset.album === String(wanted.to))
    ;(row?.querySelector<HTMLButtonElement>('button') ?? heading.current)?.focus()
  })

  if (!hasLibrary() || !library?.on || !library.library) return null
  if (!library.kept) {
    return (
      <section class="app-section" aria-labelledby="app-mylibrary-title">
        <h2 id="app-mylibrary-title" class="app-section-title">Your library</h2>
        <p class="app-footnote app-error">{LIBRARY_UNREAD}{seesDetail(accessNow()) ? '' : ` ${TELL}`}</p>
      </section>
    )
  }

  const login = loginWords(library)
  const groups = waitingGroups(library)
  const removed = library.removed ?? []

  const putAway = (albumId: number) => {
    if (acting.current !== null) return
    acting.current = albumId
    setPutting(albumId)
    setProblem(null)
    const entry = removed.find((each) => each.album_id === albumId)
    const asked = library
    dismissRemoved(albumId).then(
      () => {
        acting.current = null
        setPutting(null)
        refocus.current = { gone: albumId, to: nextFocus(removed.map((each) => each.album_id), albumId), answer: asked }
        setSaid(`${entry ? entryName(entry) : 'The album'} dismissed`)
        askMyLibrary()
      },
      (caught: unknown) => {
        acting.current = null
        setPutting(null)
        //? (2.0.4) in a listener's words (sayError)
        setProblem(sayError(caught))
      },
    )
  }

  return (
    <section class="app-section" aria-labelledby="app-mylibrary-title">
      <h2 ref={heading} id="app-mylibrary-title" class="app-section-title" tabIndex={-1}>Your library</h2>
      <div class="app-group">
        <div class="app-row">
          <span class="app-row-label">Albums</span>
          <span class="app-row-value">{libraryLine(library)}</span>
          {(library.incomplete ?? 0) > 0 && (
            <span class="app-row-detail">
              {library.incomplete} of them {library.incomplete === 1 ? 'is' : 'are'} missing some songs.
            </span>
          )}
        </div>
      </div>
      {login && <p class="app-footnote app-error">{login}</p>}
      {groups.map((group) => (
        <p key={group.words} class="app-footnote app-mylib-waiting">
          {waitingText(group)}
        </p>
      ))}
      {removed.length > 0 && (
        <ul ref={list} class="app-group app-mylib-removed" aria-label="Removed by an admin">
          {removed.map((entry) => (
            <li key={entry.album_id} class="app-row" data-album={String(entry.album_id)}>
              <span class="app-row-label">{entryName(entry)}</span>
              <span class="app-row-detail">{REMOVED_WORDS}</span>
              <span class="app-mylib-actions">
                {entry.release_group_mbid && onRequestAgain && getsAlbums && (
                  <button
                    type="button"
                    class="app-text-button"
                    onClick={() => onRequestAgain({ id: entry.release_group_mbid!, title: entry.album })}
                  >
                    Get it again
                  </button>
                )}
                <button type="button" class="app-text-button" aria-disabled={putting === entry.album_id} onClick={() => putAway(entry.album_id)}>
                  {putting === entry.album_id ? 'Dismissing…' : 'Dismiss'}
                </button>
              </span>
            </li>
          ))}
        </ul>
      )}
      <div aria-live="polite">
        {problem ? <p class="app-footnote app-error">{problem}</p> : said && <p class="app-visually-hidden">{said}</p>}
      </div>
      <p class="app-footnote">
        Your library is also in your other music apps, such as Amperfy, as your favourite albums.
        Making an album a favourite there, or taking it out, adds it here or takes it out within a few minutes.
      </p>
    </section>
  )
}
