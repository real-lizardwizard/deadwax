import { useMemo, useState } from 'preact/hooks'

import type { Candidate } from '../api/types'
import { formatSize } from '../lib/format'
import { editionTags, missingLine, qualityText, scoreClass, signalChips, speedFact, startsFact, tracksText } from '../lib/candidates'
import { ChevronDownIcon } from '../player/icons'

//? each card's reasons its own id, for the score's aria-controls
let reasonLists = 0

/**
 * One place an album can come from, in the Sources sheet (2.0.0-player.15) - James chose cards over
 * a comparison table, and Sources.dc.html draws them.
 *
 *  - The top line: the match score as a percentage, "70%" (green from AUTO_GRAB_MIN_SCORE's 75 up - the
 *    score colours' "good" band, the one a pick needs - amber under it; "70% match" to VoiceOver), the folder,
 *    "from <peer>" (and, for a set shared one folder per disc, "in 2 parts, one per disc"), and Get. The best match's Get is the
 *    screen's ONE solid purple button, wherever the sort puts its card; the rest are tinted. Each
 *    Get is named for its folder and its peer, since one peer often shares a FLAC folder and an MP3
 *    one of the same album, and two buttons both called "Get from bob" can't be told apart in
 *    VoiceOver's rotor or by Voice Control (review).
 *  - SPEED LEADS, large, with a bar (the speed against 3 MB/s, capped), and says where its number
 *    comes from: green "what you got from them" where deadwax measured this peer before, "their usual
 *    speed" for the peer's advertised rate - never presented as the download speed - and "no speed
 *    reported yet" with neither.
 *  - Then Tracks ("11 of 11", against the release's audio tracks - a CD+DVD's films aren't counted;
 *    amber when tracks are missing), Quality ("FLAC 16/44.1"), Size, and Starts ("now", "after 3 others").
 *  - What it is missing, on its own amber line: "Missing “Threads”".
 *  - WHY IT SCORED WHAT IT DID (2.0.0-player.41) - the README's promise, "ranked candidates with
 *    visible reasoning": the edition words found in the folder's name (REMASTER, DELUXE...) in their
 *    colours, and the score's signals - Track names, Track count, Track lengths, Edition, Format,
 *    Availability - each a chip with its value and its band's colour, as the main page's candidates panel
 *    showed them, and (2.0.6, UX batch 3) what it measures written beside it, under "Why it's a 70% match"
 *    (they were "Titles 48 · Count 52 · … · Peer 100", unexplained, and the score a bare "70"). Last on
 *    the card, so opening them moves nothing above. On a desktop's panel they are always shown
 *    (`reasons` 'shown'); on a phone, where 390px can't hold six of them beside the facts, they are
 *    behind a tap on the score ('tap'): the score is then a button - aria-expanded, a chevron that
 *    turns - and the reasons open under the facts, the card growing downward, nothing moving under
 *    the finger.
 *
 * Every word is lib/candidates.ts's, pinned by candidates.sim.cjs. A leaf but for whether its reasons
 * are open. `onGet` is the tap - it asks for the download in the same turn, and the sheet hands over
 * to Requests.
 */
export function SourceCard({
  candidate,
  best,
  onGet,
  reasons = 'shown',
}: {
  candidate: Candidate
  /** the best match through the chips (wherever the sort puts it): a purple edge and the solid Get */
  best: boolean
  onGet: (candidate: Candidate) => void
  /** why it scored as it did: always shown (a desktop's panel), or behind a tap on the score (a phone) */
  reasons?: 'shown' | 'tap'
}) {
  const percent = Math.round(candidate.score * 100)
  const good = scoreClass(percent) === 'good'
  const speed = speedFact(candidate)
  const starts = startsFact(candidate)
  const missing = missingLine(candidate)
  const discs = candidate.disc_folders?.length ?? 0
  const signals = signalChips(candidate)
  const tags = editionTags(candidate)
  const reasonsId = useMemo(() => `app-source-reasons-${++reasonLists}`, [])
  const [open, setOpen] = useState(false)
  const tap = reasons === 'tap'
  const scoreClasses = `app-source-score app-mono ${good ? 'is-good' : 'is-low'}`

  return (
    <li class={`app-card app-source${best ? ' is-best' : ''}`}>
      <div class="app-source-top">
        {tap ? (
          //? a phone's: the score opens why it is what it is, under the facts
          <button
            type="button"
            class={`${scoreClasses} is-toggle`}
            aria-label={`${percent}% match`}
            aria-expanded={open}
            aria-controls={reasonsId}
            onClick={() => setOpen((was) => !was)}
          >
            {percent}%
            <ChevronDownIcon class="app-source-score-icon" />
          </button>
        ) : (
          <span class={scoreClasses} aria-label={`${percent}% match`}>
            {percent}%
          </span>
        )}
        <span class="app-source-name">
          <span class="app-source-folder" title={candidate.directory}>{candidate.directory_name}</span>
          <span class="app-source-peer">
            from {candidate.username}
            {discs > 1 ? ` · in ${discs} parts, one per disc` : ''}
          </span>
        </span>
        <button
          type="button"
          class={`app-source-get ${best ? 'is-primary' : 'is-tinted'}`}
          aria-label={`Get ${candidate.directory_name} from ${candidate.username}`}
          onClick={() => onGet(candidate)}
        >
          Get
        </button>
      </div>

      <div class="app-source-speed">
        <div class="app-source-speed-line">
          <span class="app-source-speed-value">
            <span class="app-source-label">Speed</span>
            <span class={`app-source-speed-text app-mono is-${speed.kind}`}>{speed.text}</span>
          </span>
          <span class="app-source-speed-note">{speed.note}</span>
        </div>
        <span class="app-source-bar" aria-hidden="true">
          <span class={`app-source-bar-fill is-${speed.kind}`} style={{ width: `${speed.percent}%` }} />
        </span>
      </div>

      <dl class="app-source-facts">
        <div class="app-source-fact">
          <dt class="app-source-label">Tracks</dt>
          <dd class={`app-source-value${missing ? ' is-warning' : ''}`}>{tracksText(candidate)}</dd>
        </div>
        <div class="app-source-fact">
          <dt class="app-source-label">Quality</dt>
          <dd class="app-source-value app-mono">{qualityText(candidate)}</dd>
        </div>
        <div class="app-source-fact">
          <dt class="app-source-label">Size</dt>
          <dd class="app-source-value app-mono">{formatSize(candidate.total_size) || '–'}</dd>
        </div>
        <div class="app-source-fact">
          <dt class="app-source-label">Starts</dt>
          <dd class={`app-source-value ${starts.waits ? 'is-warning' : 'is-now'}`}>{starts.text}</dd>
        </div>
      </dl>

      {missing && <p class="app-source-missing">{missing}</p>}

      {/* why it scored what it did: last, so opening it moves nothing above - hidden on a phone until
          the score is tapped, always there on a desktop */}
      <div
        id={reasonsId}
        class="app-source-reasons"
        role="group"
        aria-labelledby={`${reasonsId}-title`}
        hidden={tap && !open}
      >
        <p id={`${reasonsId}-title`} class="app-source-reasons-title">Why it's a {percent}% match</p>
        {tags.length > 0 && (
          <p class="app-source-tags">
            <span class="app-visually-hidden">In its name: </span>
            {tags.map(({ tag, tone }) => (
              <span key={tag} class={`app-source-tag is-${tone}`}>{tag}</span>
            ))}
          </p>
        )}
        <ul class="app-source-signals">
          {signals.map((chip) => (
            <li key={chip.signal} class="app-source-signal-row">
              <span class={`app-source-signal is-${chip.band}`}>
                {chip.label} <span class="app-mono">{chip.value}%</span>
              </span>
              {chip.meaning && <span class="app-source-signal-meaning">{chip.meaning}</span>}
            </li>
          ))}
        </ul>
      </div>
    </li>
  )
}
