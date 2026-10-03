import type { Candidate } from '../api/types'
import { formatSize } from '../lib/format'
import { missingLine, qualityText, scoreClass, speedFact, startsFact, tracksText } from '../lib/candidates'

/**
 * One place an album can come from, in the Sources sheet (2.0.0-player.15) - James chose cards over
 * a comparison table, and Sources.dc.html draws them.
 *
 *  - The top line: the match score (green from AUTO_GRAB_MIN_SCORE's 75 up - the score colours'
 *    "good" band, the one a pick needs - amber under it), the folder, "from <peer>" (and how many
 *    disc folders a set shared one per disc was joined from), and Get. The best match's Get is the
 *    screen's ONE solid purple button, wherever the sort puts its card; the rest are tinted. Each
 *    Get is named for its folder and its peer, since one peer often shares a FLAC folder and an MP3
 *    one of the same album, and two buttons both called "Get from bob" can't be told apart in
 *    VoiceOver's rotor or by Voice Control (review).
 *  - SPEED LEADS, large, with a bar (the speed against 3 MB/s, capped), and says where its number
 *    comes from: green "what you got from them" where deadwax measured this peer before, "their own
 *    average" for the peer's advertised rate - never presented as the download speed - and "no speed
 *    reported yet" with neither.
 *  - Then Tracks ("11 of 11", against the release's audio tracks - a CD+DVD's films aren't counted;
 *    amber when tracks are missing), Quality ("FLAC 16/44.1"), Size, and Starts ("now", "3 ahead").
 *  - What it is missing, on its own amber line: "Missing “Threads”".
 *
 * Every word is lib/candidates.ts's, pinned by candidates.sim.cjs. A leaf: props only. `onGet` is
 * the tap - it asks for the download in the same turn, and the sheet hands over to Requests.
 */
export function SourceCard({
  candidate,
  best,
  onGet,
}: {
  candidate: Candidate
  /** the best match through the chips (wherever the sort puts it): a purple edge and the solid Get */
  best: boolean
  onGet: (candidate: Candidate) => void
}) {
  const percent = Math.round(candidate.score * 100)
  const good = scoreClass(percent) === 'good'
  const speed = speedFact(candidate)
  const starts = startsFact(candidate)
  const missing = missingLine(candidate)
  const discs = candidate.disc_folders?.length ?? 0

  return (
    <li class={`app-card app-source${best ? ' is-best' : ''}`}>
      <div class="app-source-top">
        <span class={`app-source-score app-mono ${good ? 'is-good' : 'is-low'}`} aria-label={`Match score ${percent}`}>
          {percent}
        </span>
        <span class="app-source-name">
          <span class="app-source-folder" title={candidate.directory}>{candidate.directory_name}</span>
          <span class="app-source-peer">
            from {candidate.username}
            {discs > 1 ? ` · ${discs} disc folders` : ''}
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
          <dd class={`app-source-value app-mono${missing ? ' is-warning' : ''}`}>{tracksText(candidate)}</dd>
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
          <dd class={`app-source-value app-mono ${starts.waits ? 'is-warning' : 'is-now'}`}>{starts.text}</dd>
        </div>
      </dl>

      {missing && <p class="app-source-missing">{missing}</p>}
    </li>
  )
}
