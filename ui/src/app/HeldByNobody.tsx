import { useEffect, useLayoutEffect, useMemo, useRef, useState } from 'preact/hooks'

import { addFlagged, dismissFlag, heldByNobody } from '../api/library'
import type { HeldByNobody as HeldAnswer } from '../api/types'
import { isAbort, latestOnly } from '../lib/latest'
import { flagWords, heldByNobodyLine, nextFocus } from '../lib/myLibrary'

/** How many of the albums nobody holds are listed before "Show all". */
export const HELD_SHOWN = 20

/** Focus fell to the page (or was never taken) - the only time a row leaving moves it. */
const focusLost = (): boolean => {
  if (typeof document === 'undefined') return false
  const active = document.activeElement
  return !active || active === document.body
}

/** A flag as its row names it. */
const flagName = (flag: HeldAnswer['flags'][number]): string => [flag.album || 'Unknown album', flag.artist].filter(Boolean).join(' · ')

/**
 * Library care > Held by nobody (2.0.0-player.51, personal libraries - an admin's, with logins on): every
 * album in the store nobody has in their library - copied in by hand or by another tool, it belongs to
 * nobody and stays for anyone to add - and the downloads flagged for a look: every file was already in a
 * folder holding another pressing or an untagged copy, so nobody was given it. A flag is given to those
 * who asked ("Add for them") or put away. Asked as the page shows (`live`), through latestOnly().
 *
 * Focus is never dropped to the page (review; the app's rule): a flag dealt with leaves once the list is
 * read again, and its focus goes to the flag now in its place (else the one before, else the heading),
 * with what happened said; "Show all" and "Show fewer" are one button, so the focus stays on it.
 */
export function HeldByNobody({ live }: { live: boolean }) {
  const [answer, setAnswer] = useState<HeldAnswer | null>(null)
  //? why the list couldn't be read - and, apart, why the last Add or Put away was refused (kept as the
  //? list is read again after it)
  const [problem, setProblem] = useState<string | null>(null)
  const [refused, setRefused] = useState<string | null>(null)
  const [said, setSaid] = useState('')
  const [all, setAll] = useState(false)
  const [busy, setBusy] = useState<number | null>(null)
  //? the flag being dealt with, at once - a second tap before the page draws again asks nothing more
  const acting = useRef<number | null>(null)
  const requests = useMemo(latestOnly, [])
  const flagList = useRef<HTMLUListElement | null>(null)
  const heading = useRef<HTMLHeadingElement | null>(null)
  //? where focus goes once a flag dealt with has left: `to` (a flag id), or the heading for null - asked
  //? of the list read after `answer`, the one it was dealt with in
  const refocus = useRef<{ gone: number; to: number | null; answer: HeldAnswer | null } | null>(null)

  function load() {
    const request = requests.begin()
    heldByNobody(request.signal).then(
      (found) => {
        if (!request.current()) return
        setAnswer(found)
        setProblem(null)
      },
      (caught: unknown) => {
        if (request.current() && !isAbort(caught)) setProblem(caught instanceof Error ? caught.message : String(caught))
      },
    )
  }

  useEffect(() => {
    if (!live) return
    load()
    return () => requests.supersede()
  }, [live])

  useLayoutEffect(() => {
    const wanted = refocus.current
    if (!wanted || answer === wanted.answer) return
    refocus.current = null
    if ((answer?.flags ?? []).some((flag) => flag.id === wanted.gone) || !focusLost()) return
    const row = wanted.to === null || !flagList.current
      ? null
      : [...flagList.current.querySelectorAll<HTMLElement>('[data-flag]')].find((each) => each.dataset.flag === String(wanted.to))
    ;(row?.querySelector<HTMLButtonElement>('button') ?? heading.current)?.focus()
  })

  const act = (flagId: number, how: 'add' | 'dismiss') => {
    if (acting.current !== null) return
    acting.current = flagId
    setBusy(flagId)
    setRefused(null)
    const flags = answer?.flags ?? []
    const flag = flags.find((each) => each.id === flagId)
    const name = flag ? flagName(flag) : 'The flag'
    const asked = answer
    const done = () => {
      acting.current = null
      setBusy(null)
      //? whatever came of it, the row may go as the list is read again: its focus is handed on then
      refocus.current = { gone: flagId, to: nextFocus(flags.map((each) => each.id), flagId), answer: asked }
      load()
    }
    ;(how === 'add' ? addFlagged(flagId) : dismissFlag(flagId)).then(
      (result) => {
        const users = 'users' in result ? result.users : []
        setSaid(how === 'add' ? (users.length ? `${name}: given to ${users.join(', ')}` : `${name}: nobody to give it to`) : `${name}: put away`)
        done()
      },
      (caught: unknown) => {
        setSaid('')
        setRefused(caught instanceof Error ? caught.message : String(caught))
        done()
      },
    )
  }

  const albums = answer?.albums ?? []
  const shown = all ? albums : albums.slice(0, HELD_SHOWN)
  return (
    <section class="app-care-section" aria-labelledby="app-care-held">
      <h2 ref={heading} id="app-care-held" class="app-care-title" tabIndex={-1}>Held by nobody</h2>
      {!answer ? (
        problem ? <p class="app-care-problem">{problem}</p> : <p class="app-care-note">Asking deadwax…</p>
      ) : (
        <>
          <p class="app-care-note">{heldByNobodyLine(answer.count)}</p>
          {shown.length > 0 && (
            <ul class="app-care-held">
              {shown.map((album) => (
                <li key={album.id} class="app-care-held-row">
                  <span class="app-care-held-name">{[album.album || 'Unknown album', album.artist].filter(Boolean).join(' · ')}</span>
                  <span class="app-care-held-path">{album.path}</span>
                </li>
              ))}
            </ul>
          )}
          {albums.length > HELD_SHOWN && (
            //? one button for both ways, so the focus on it stays as the list grows or shrinks under it
            <button type="button" class="app-text-button" aria-expanded={all} onClick={() => setAll((open) => !open)}>
              {all ? 'Show fewer' : `Show all ${albums.length}`}
            </button>
          )}
          {answer.flags.length > 0 && (
            <>
              <h3 class="app-care-heading">Flagged downloads</h3>
              <ul ref={flagList} class="app-care-held">
                {answer.flags.map((flag) => (
                  <li key={flag.id} class="app-care-held-row" data-flag={String(flag.id)}>
                    <span class="app-care-held-name">{flagName(flag)}</span>
                    <span class="app-care-held-path">{flagWords(flag)}</span>
                    <span class="app-care-held-actions">
                      <button type="button" class="app-button app-care-button" aria-disabled={busy === flag.id} onClick={() => act(flag.id, 'add')}>
                        Add for them
                      </button>
                      <button type="button" class="app-text-button" aria-disabled={busy === flag.id} onClick={() => act(flag.id, 'dismiss')}>
                        Put away
                      </button>
                    </span>
                  </li>
                ))}
              </ul>
            </>
          )}
          <div aria-live="polite">
            {refused || problem ? <p class="app-care-problem">{refused || problem}</p> : said && <p class="app-visually-hidden">{said}</p>}
          </div>
        </>
      )}
    </section>
  )
}
