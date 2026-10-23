import { useEffect, useState } from 'preact/hooks'

import { clearSavedAnswers, getSavedAnswers, type SavedAnswersStats } from '../api/musicbrainzCache'
import { isAbort, latestOnly } from '../lib/latest'
import { describeSavedAnswers } from '../lib/musicbrainzAnswers'

const message = (reason: unknown) => (reason instanceof Error ? reason.message : String(reason))

/**
 * "Clear MusicBrainz's saved answers" (2.0.0-player.54), under MUSICBRAINZ_CACHE_PATH and
 * MUSICBRAINZ_CACHE_MB - on Server settings' Connections (and on the main page's settings tab too, until it
 * retired in 2.0.0-player.66) - with the file's size and how many answers it holds beside it.
 *
 * Read as it is drawn, through latestOnly(); again each time its page comes back into view (`live`
 * turning true - the app keeps a tab's page drawn but hidden while another tab shows, and the file goes
 * on filling meanwhile; the main page's tab was drawn afresh each time it opened, so it left `live`
 * out); and again whenever the two settings' saved values change (its parent keys it on them -
 * lib/musicbrainzAnswers.ts savedAnswersKey). Coming back while a Clear is on its way reads nothing: the
 * Clear answers with the file as it is - and going out of view never calls it off, only being let go.
 *
 * Clear empties the file and the hour in memory: only speed is lost, so it asks no confirmation - the
 * next answers are asked of MusicBrainz again. Refused while MUSICBRAINZ_CACHE_PATH has an unsaved edit
 * (it clears the file that is SAVED), while there is nothing to clear, and while it goes - with
 * aria-disabled and the press refused here, never `disabled`: Clear refuses itself on its own press,
 * and a focused button made disabled drops the focus to the page, where a keyboard or VoiceOver starts
 * again from the top.
 */
export function MusicBrainzAnswers({ unsaved, live = true }: { unsaved: boolean; live?: boolean }) {
  const [stats, setStats] = useState<SavedAnswersStats | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [clearing, setClearing] = useState(false)
  const [cleared, setCleared] = useState(false)
  //? one ask drawn at a time - the read, or the clear that answers after it
  const [asks] = useState(() => latestOnly())

  //? let go: whatever is still out lands nowhere. Only then - out of view, it is still drawn
  useEffect(() => () => asks.supersede(), [])

  useEffect(() => {
    //? `clearing` as it stands in the drawing that changed `live` - the one this runs for
    if (!live || clearing) return
    const ticket = asks.begin()
    getSavedAnswers(ticket.signal).then(
      (answer) => {
        if (!ticket.current()) return
        setStats(answer)
        setError(null)
        //? what the file holds now - a Clear's "Cleared." is the line only until the next read
        setCleared(false)
      },
      (reason: unknown) => {
        if (ticket.current() && !isAbort(reason)) setError(`couldn't read them - ${message(reason)}`)
      },
    )
  }, [live])

  //? nothing to clear: no answers held (an empty file is a few KB of its own table, and stays)
  const empty = !stats || stats.answers === 0
  const refused = clearing || unsaved || empty

  const clear = () => {
    if (refused) return
    const ticket = asks.begin()
    setClearing(true)
    clearSavedAnswers().then(
      (answer) => {
        if (!ticket.current()) return
        setStats(answer)
        setError(null)
        setCleared(true)
        setClearing(false)
      },
      (reason: unknown) => {
        if (!ticket.current()) return
        setError(`couldn't clear them - ${message(reason)}`)
        setClearing(false)
      },
    )
  }

  return (
    <div class="settings-answers">
      <button
        type="button"
        class="win-button"
        aria-disabled={refused}
        title={unsaved
          ? 'Save the new path first - this clears the file that is saved'
          : clearing
            ? 'Clearing them…'
            : empty
              ? 'Nothing saved to clear'
              : "Every saved answer gone, on disk and in memory. Only speed is lost: the next answers are asked of MusicBrainz again."}
        onClick={clear}
      >
        {clearing ? 'Clearing…' : "Clear MusicBrainz's saved answers"}
      </button>

      <span class="settings-answers-note" role="status">
        {unsaved
          ? 'Save the new path first.'
          : error
            ? `MusicBrainz's saved answers: ${error}`
            : stats
              ? describeSavedAnswers(stats, cleared)
              : 'Reading the saved answers…'}
      </span>
    </div>
  )
}
