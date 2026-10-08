import { useEffect, useMemo, useState } from 'preact/hooks'

import { isAbort, latestOnly } from '../lib/latest'
import { clock } from '../lib/scrub'
import { SEARCH_MAX_CHARS } from '../lib/searchQuery'
import { navidromeStatus, searchLibrary, type Song } from '../player/api'
import { formatLine, librarySearch, libraryTrack, type SearchAnswer } from './library'

const message = (error: unknown) => (error instanceof Error ? error.message : String(error))

/** What the bench says when Navidrome can't be asked - the bench's own signals work all the same. */
export const STILL_WORKS = "The bench's own signals still work."

/** What Navidrome's status says, in one line - or null when it answers. */
export function navidromeLine(status: { configured: boolean; ok: boolean; problem: string | null }): string | null {
  if (status.ok) return null
  if (!status.configured) return `${status.problem ?? "Navidrome isn't set up"}. ${STILL_WORKS}`
  return `Navidrome isn't answering just now - ${status.problem ?? 'it gave no reason'}. ${STILL_WORKS}`
}

/** A song's second and third lines: who and from what; how long and what it is (Info's Format). */
function songLines(song: Song): [string, string] {
  const who = [song.artist, song.album].filter(Boolean).join(' · ')
  return [who || 'Navidrome named no artist or album', `${clock(song.duration ?? 0)} · ${formatLine(libraryTrack(song))}`]
}

/**
 * A SONG FROM YOUR LIBRARY on the test bench (2.0.0-player.37): a search box, Navidrome's songs as rows,
 * one tapped to make it the bench's song. The search is lab/library.ts librarySearch: paced as the app's
 * Search paces its library half, only its newest answer drawn. Navidrome not set up or not answering is
 * said in one line, asked once as the picker shows (its status, through latestOnly too).
 */
export function LibraryPicker({ disabled, chosen, onPick }: {
  /** while anything records, or a motion or the check runs: the song is held still */
  disabled: boolean
  /** the library song the bench has now (Navidrome's id), or null */
  chosen: string | null
  onPick: (song: Song) => void
}) {
  const [text, setText] = useState('')
  const [answer, setAnswer] = useState<SearchAnswer>({ state: 'idle', query: '' })
  const [navidrome, setNavidrome] = useState<string | null>(null)
  const search = useMemo(() => librarySearch({ search: (query, signal) => searchLibrary(query, signal), onAnswer: setAnswer }), [])
  useEffect(() => () => search.stop(), [])

  //? whether there is a Navidrome to search - one line if not, the rest of the bench as ever
  const statuses = useMemo(latestOnly, [])
  useEffect(() => {
    const ticket = statuses.begin()
    navidromeStatus(ticket.signal).then(
      (status) => {
        if (ticket.current()) setNavidrome(navidromeLine(status))
      },
      (error: unknown) => {
        if (ticket.current() && !isAbort(error)) setNavidrome(`deadwax couldn't say whether Navidrome is there - ${message(error)}. ${STILL_WORKS}`)
      },
    )
    return () => statuses.supersede()
  }, [])

  const said = answer.state === 'asking' ? 'Asking Navidrome…'
    : answer.state === 'failed' ? `Navidrome couldn't be searched - ${answer.problem}. ${STILL_WORKS}`
      : answer.state === 'found' && !answer.songs.length ? `No song in your library matches “${answer.query}”.`
        : answer.state === 'found' ? `${answer.songs.length === 1 ? 'One song' : `${answer.songs.length} songs`} - tap one to make it the song.`
          : ''

  return (
    <div class="lab-library">
      {navidrome && <p class="lab-note lab-warning">{navidrome}</p>}
      <label class="lab-field lab-search">
        <span>Search your library</span>
        <input
          type="search"
          value={text}
          maxLength={SEARCH_MAX_CHARS}
          enterKeyHint="search"
          autoComplete="off"
          spellcheck={false}
          placeholder="A song, an artist, an album"
          disabled={disabled}
          onInput={(event) => {
            const value = (event.currentTarget as HTMLInputElement).value
            setText(value)
            search.type(value)
          }}
          onKeyDown={(event) => {
            if (event.key !== 'Enter') return
            event.preventDefault()
            search.now(text)
          }}
        />
      </label>
      <p class="lab-status" role="status" aria-live="polite">{said}</p>
      {answer.state === 'found' && answer.songs.length > 0 && (
        <ul class="lab-results">
          {answer.songs.map((song) => {
            const [who, what] = songLines(song)
            return (
              <li key={song.id}>
                <button type="button" class="lab-result" aria-pressed={chosen === song.id} aria-disabled={disabled} onClick={() => !disabled && onPick(song)}>
                  <span class="lab-result-title">{song.title}</span>
                  <span class="lab-result-line">{who}</span>
                  <span class="lab-result-line">{what}</span>
                </button>
              </li>
            )
          })}
        </ul>
      )}
    </div>
  )
}
