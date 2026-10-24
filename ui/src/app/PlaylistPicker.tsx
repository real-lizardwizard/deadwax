import { useEffect, useLayoutEffect, useRef, useState } from 'preact/hooks'

import { addToPlaylist, createPlaylist, type Duplicates, type Playlist } from '../api/playlists'
import { ApiError } from '../api/http'
import { addedWords, duplicateQuestion, listFailed, madeWords, pickLine, pickerPlaylists, songCount, type PlaylistPick } from '../lib/playlists'
import { Cover } from '../player/Cover'
import { PlaylistAddIcon, PlaylistIcon } from '../player/icons'
import { NewPlaylistForm } from './NewPlaylistForm'
import { askPlaylists, announcePlaylistChanged, usePlaylists } from './usePlaylists'
import { sayPins } from './usePins'
import { useSheet } from './useSheet'
import { sayError } from './sayError'

/** Some of the songs are in the playlist already: the question, in place of the list. */
interface Question {
  playlist: Playlist
  already: number
  asked: number
}

/**
 * Add to a playlist (2.0.0-player.58): one sheet on both frames, over everything - opened from a song's or an
 * album's ••• menu (app/QueueMenu.tsx), Now Playing's ••• menu, the desktop's player bar - with the songs in hand.
 * New playlist… first, then the playlists you can add to (lib/playlists.ts pickerPlaylists: yours and editable, the
 * one changed last on top); the list is asked afresh as the sheet opens, what is held drawing meanwhile.
 *
 * A playlist's tap adds (`ask`): one write at a time - its row (or the question's button pressed) says "Adding…"
 * and every row is aria-disabled until the answer, so a double tap never adds twice; the answer frees them however
 * it went, the sheet closed and opened again meanwhile or not (review). Done: the sheet closes - focus back to what opened it - and the
 * app's one notice (PinNotice, sayPins) says what happened. Some there already, nothing written: the list gives
 * way to the question - add them again, or skip those (or Cancel, back to the list). Refused: the words under the
 * list, the sheet open - focus to the list's first row when it was the question that sent it; a playlist gone
 * ("isn't on Navidrome any more") asks the list again. The heading, what it adds and the words are on a card of
 * their own, never on the scrim over the page. Closing the sheet while
 * an add is out doesn't call it off (a write) - the notice still says how it went. New playlist… opens the form in
 * place of its row and makes the playlist WITH the songs.
 *
 * A sheet like the others (useSheet.ts): its own scroll lock, focus in to its first row and back to its opener,
 * Escape, the backdrop; inert while closed. It names no playback action.
 */
export function PlaylistPicker({
  open,
  pick,
  opener,
  onClose,
}: {
  open: boolean
  /** what it was opened with - kept as it slides away; a new key each time it opens */
  pick: PlaylistPick | null
  opener?: { current: HTMLElement | null } | undefined
  onClose: () => void
}) {
  const { list, problem: listProblem } = usePlaylists()
  const first = useRef<HTMLButtonElement>(null)
  const [making, setMaking] = useState(false)
  const [question, setQuestion] = useState<Question | null>(null)
  //? the write out: to which playlist, and how - so the button pressed is the one that says "Adding…"
  const [adding, setAdding] = useState<{ id: string; mode: Duplicates } | null>(null)
  const [problem, setProblem] = useState<string | null>(null)
  //? one write at a time, held at once - a state update would let a second tap through before it drew
  const writing = useRef(false)
  //? the pick the sheet shows now: an answer for an earlier one still says how it went, but changes nothing here
  const showing = useRef<number | null>(null)
  showing.current = open && pick ? pick.key : null
  const questionFirst = useRef<HTMLButtonElement>(null)

  //? (the form's Escape calls preventDefault, so the sheet stays open around it - useSheet passes it over)
  useSheet({ open, onClose, lockClass: 'app-picker-open', first, opener })
  //? back to the list from the question or the form: focus to its first row, never dropped to the page
  const backToList = useRef(false)
  useLayoutEffect(() => {
    if (!backToList.current) return
    backToList.current = false
    first.current?.focus({ preventScroll: true })
  })

  //? afresh each time it opens: the list asked again, the form, the question and the words put away
  useEffect(() => {
    if (!open) return
    setMaking(false)
    setQuestion(null)
    setProblem(null)
    askPlaylists({ fresh: true })
  }, [open, pick?.key])

  useEffect(() => {
    if (question) questionFirst.current?.focus({ preventScroll: true })
  }, [question])

  const rows = list ? pickerPlaylists(list) : []
  const ids = pick ? pick.songs.map((song) => song.id) : []

  const add = (playlist: Playlist, mode: Duplicates) => {
    if (!pick || writing.current || !ids.length) return
    writing.current = true
    const key = pick.key
    const asked = { label: pick.label, songs: pick.songs }
    //? sent from the question: refused, the list comes back - focus to its first row, never dropped to the page
    const fromQuestion = question !== null
    setAdding({ id: playlist.id, mode })
    setProblem(null)
    addToPlaylist(playlist.id, ids, mode).then(
      (answer) => {
        writing.current = false
        //? (review) freed whether or not this is still the pick showing - else, closed and opened again while it was
        //? out, the rows stayed "Adding…" and New playlist… did nothing
        setAdding(null)
        const here = showing.current === key
        if (!answer.done) {
          if (here) setQuestion({ playlist, already: answer.already, asked: answer.asked ?? ids.length })
          else sayPins(`Nothing added - some are in ${playlist.name} already`)
          return
        }
        announcePlaylistChanged(playlist.id)
        sayPins(addedWords({ added: answer.added ?? 0, already: answer.already }, mode, asked, playlist.name))
        if (here) {
          setQuestion(null)
          onClose()
        }
      },
      (caught: unknown) => {
        writing.current = false
        setAdding(null)
        //? (2.0.4) in a listener's words (sayError)
        const why = sayError(caught)
        if (caught instanceof ApiError && caught.status === 404) askPlaylists({ fresh: true })
        if (showing.current !== key) {
          sayPins(`Couldn't add to ${playlist.name}. ${why}`)
          return
        }
        if (fromQuestion) backToList.current = true
        setQuestion(null)
        setProblem(why)
      },
    )
  }

  const make = (name: string) => {
    if (!pick) return Promise.resolve()
    const asked = { label: pick.label, songs: pick.songs }
    return createPlaylist(name, ids).then((made) => {
      announcePlaylistChanged(made.playlist.id, made)
      sayPins(madeWords(made.playlist.name, asked))
      if (showing.current === pick.key) onClose()
    })
  }

  const asked = question && pick ? duplicateQuestion(question.already, question.asked, pick, question.playlist.name) : null

  return (
    <div class={`app-layer app-menu-layer app-playlist-layer${open ? ' is-open' : ''}`} aria-hidden={!open} inert={!open}>
      <div class="app-backdrop" onClick={onClose} />
      <div class="app-menu app-playlist-picker" role="dialog" aria-modal="true" aria-labelledby="app-playlist-picker-title">
        {/* (review) on a card of their own - over the scrim the page showed through them */}
        <div class="app-group app-playlist-picker-head">
          <h2 id="app-playlist-picker-title" class="app-playlist-picker-title">Add to a playlist</h2>
          <p class="app-playlist-picker-what">{pick ? pickLine(pick) : ''}</p>
          {problem && (
            <p class="app-store-line is-refused app-playlist-picker-problem" role="alert">
              {problem}
            </p>
          )}
        </div>

        {asked && question ? (
          <div class="app-group app-playlist-question" role="group" aria-label={asked.text}>
            <p class="app-playlist-question-words">{asked.text}</p>
            <div class="app-confirm-buttons">
              <button ref={questionFirst} type="button" class="app-button is-primary" aria-disabled={adding !== null} onClick={() => add(question.playlist, asked.yes.mode)}>
                {adding?.mode === asked.yes.mode ? 'Adding…' : asked.yes.label}
              </button>
              <button
                type="button"
                class="app-button"
                aria-disabled={adding !== null}
                onClick={() => {
                  if (adding) return
                  if (asked.no.mode) add(question.playlist, asked.no.mode)
                  else {
                    backToList.current = true
                    setQuestion(null)
                  }
                }}
              >
                {adding && adding.mode === asked.no.mode ? 'Adding…' : asked.no.label}
              </button>
            </div>
          </div>
        ) : (
          <div class="app-group app-playlist-picker-list">
            {list !== null && !rows.length && !listProblem && <p class="app-playlist-picker-note">No playlists yet - make one:</p>}
            {making ? (
              <NewPlaylistForm onCreate={make} onCancel={() => {
                backToList.current = true
                setMaking(false)
              }} />
            ) : null}
            <button
              ref={first}
              type="button"
              class="app-menu-item app-playlist-pick app-playlist-new"
              hidden={making}
              aria-disabled={adding !== null}
              onClick={() => {
                if (!adding) setMaking(true)
              }}
            >
              <span class="app-playlist-pick-art is-new" aria-hidden="true">
                <PlaylistAddIcon class="app-playlist-art-icon" />
              </span>
              <span class="app-playlist-pick-name">New playlist…</span>
            </button>
            {rows.map((playlist) => (
              <button
                key={playlist.id}
                type="button"
                class="app-menu-item app-playlist-pick"
                aria-disabled={adding !== null}
                onClick={() => add(playlist, 'ask')}
              >
                <span class="app-playlist-pick-art">
                  {playlist.coverArt ? <Cover id={playlist.coverArt} size={80} class="app-playlist-pick-cover" /> : <PlaylistIcon class="app-playlist-art-icon" />}
                </span>
                <span class="app-playlist-pick-text">
                  <span class="app-playlist-pick-name">{playlist.name}</span>
                  <span class="app-playlist-pick-line">{adding?.id === playlist.id ? 'Adding…' : songCount(playlist.songCount)}</span>
                </span>
              </button>
            ))}
            {listProblem && list === null && (
              <div class="app-playlist-picker-note">
                <p class="app-store-line is-refused">{listFailed(listProblem)}</p>
                <button type="button" class="app-text-button" onClick={() => askPlaylists({ fresh: true })}>
                  Try again
                </button>
              </div>
            )}
          </div>
        )}
        <button type="button" class="app-button app-menu-cancel" onClick={onClose}>
          Cancel
        </button>
      </div>
    </div>
  )
}
