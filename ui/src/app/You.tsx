import { useEffect, useMemo, useState } from 'preact/hooks'

import { pingMusicBrainz, pingSlskd, type PingAnswer } from '../api/connections'
import { me as fetchMe, type Me } from '../api/me'
import { isAbort, latestOnly } from '../lib/latest'
import { navidromeStatus, type NavidromeStatus } from '../player/api'
import { ChevronRightIcon } from '../player/icons'
import { usePlayerActions, usePlayerState } from './context'
import type { Look } from '../lib/turntable'
import { GaplessChoice } from './GaplessChoice'
import { LookChoice } from './LookChoice'
import { QualityChoice } from './QualityChoice'

type CheckState = { state: 'pending' | 'ok' | 'failed'; text: string; detail?: string }

const SERVICES = [
  { id: 'musicbrainz', label: 'MusicBrainz' },
  { id: 'slskd', label: 'slskd' },
  { id: 'navidrome', label: 'Navidrome' },
] as const

type Service = (typeof SERVICES)[number]['id']

const PENDING: CheckState = { state: 'pending', text: 'Checking…' }

const message = (error: unknown) => (error instanceof Error ? error.message : String(error))

/** A ping's answer as a row says it: the code is the short word, the error the sentence under it. */
function fromPing(answer: PingAnswer): CheckState {
  if (String(answer.status).toLowerCase() === 'ok') return { state: 'ok', text: 'Connected' }
  const code = answer.code === undefined || answer.code === null ? '' : String(answer.code)
  return { state: 'failed', text: code || 'Not connected', ...(answer.error ? { detail: answer.error } : {}) }
}

function fromNavidrome(status: NavidromeStatus): CheckState {
  if (status.ok) return { state: 'ok', text: status.server || 'Connected' }
  return {
    state: 'failed',
    text: status.configured ? "Can't reach it" : 'Not set up',
    ...(status.problem ? { detail: status.problem } : {}),
  }
}

/**
 * You: what this device plays like, whether deadwax can reach what it needs, and what version it
 * is. The rest of looking after deadwax - server settings, the albums that need a look, the log,
 * editing an album - is on the main page for now, and this says so and links there.
 *
 * - Playback: Gapless, a checkbox (GaplessChoice.tsx - moved here from the now-playing screen in
 *   2.0.0-player.10, where it was a switch), "Now Playing opens as" (LookChoice.tsx,
 *   2.0.0-player.11: the cover or the turntable - App keeps it, and hands it here), and Maximum
 *   quality, moved here from the player's settings sheet with its words unchanged. All three are
 *   kept per device. Gapless is handed the player itself, whose `setGapless` it calls in the tap:
 *   this page names no playback action of its own (ui/test/app-rules.sim.cjs).
 * - Connections: the main page's three pings, asked the first time You shows (not at start-up: the
 *   MusicBrainz ping is a real request to a rate-limited service), and again on "Check again". Each
 *   row is its own live region, read whole ("slskd, Connected"): the three answers land in any
 *   order, and a bare "Connected" says nothing about which service it is.
 * - About: from `GET /deadwax/me` - the version, and that logins are off. Asked with the pings, and
 *   again on "Check again": deadwax restarting under Komodo while You first opened must not leave
 *   "unknown" there until the app is killed.
 * - The link to the main page opens it BESIDE the app (a new tab in a browser), so the music playing
 *   here carries on: in the same page it would unload the player, its queue and all.
 *
 * It works with Navidrome unset or down: nothing here waits on it. A page, so it reads the player
 * from context; `shown` is App's word that the tab has been opened at least once.
 */
export function You({
  shown,
  opensAs,
  onOpensAs,
}: {
  shown: boolean
  /** "Now Playing opens as", and the way to change it - App's */
  opensAs: Look
  onOpensAs: (look: Look) => void
}) {
  const player = usePlayerState()
  const actions = usePlayerActions()
  const [who, setWho] = useState<Me | null>(null)
  const [whoFailed, setWhoFailed] = useState<string | null>(null)
  const [checks, setChecks] = useState<Record<Service, CheckState> | null>(null)
  const meRequests = useMemo(latestOnly, [])
  const pingRequests = useMemo(latestOnly, [])

  function askWho() {
    const request = meRequests.begin()
    setWhoFailed(null)
    fetchMe(request.signal).then(
      (answer) => {
        if (request.current()) setWho(answer)
      },
      (reason: unknown) => {
        //? what deadwax said before stays (the version didn't change); the failure is said under it
        if (request.current() && !isAbort(reason)) setWhoFailed(message(reason))
      },
    )
  }

  function checkAll() {
    askWho()
    const request = pingRequests.begin()
    setChecks({ musicbrainz: PENDING, slskd: PENDING, navidrome: PENDING })
    const settle = (service: Service, state: CheckState) => {
      if (request.current()) setChecks((now) => ({ ...(now ?? { musicbrainz: PENDING, slskd: PENDING, navidrome: PENDING }), [service]: state }))
    }
    const failed = (service: Service) => (reason: unknown) => {
      if (!isAbort(reason)) settle(service, { state: 'failed', text: 'No answer', detail: message(reason) })
    }
    pingMusicBrainz(request.signal).then((answer) => settle('musicbrainz', fromPing(answer)), failed('musicbrainz'))
    pingSlskd(request.signal).then((answer) => settle('slskd', fromPing(answer)), failed('slskd'))
    navidromeStatus(request.signal).then((status) => settle('navidrome', fromNavidrome(status)), failed('navidrome'))
  }

  useEffect(() => {
    if (!shown) return
    checkAll()
    return () => {
      meRequests.supersede()
      pingRequests.supersede()
    }
  }, [shown])

  //? admin-only rows show unless deadwax has said this user isn't one - with logins off, everyone is
  const admin = who ? who.admin : true
  //? only what deadwax has said: nothing while it hasn't answered, "…" while it is being asked
  const identity = who ? (who.auth === 'off' ? 'Logins are off' : who.user) : whoFailed ? null : '…'

  return (
    <section class="app-you">
      <header class="app-identity">
        <span class="app-avatar" aria-hidden="true">
          d
        </span>
        <div class="app-identity-text">
          <h1 class="app-identity-name">deadwax</h1>
          {identity && <p class="app-identity-sub">{identity}</p>}
        </div>
      </header>

      <section class="app-section" aria-labelledby="app-playback-title">
        <h2 id="app-playback-title" class="app-section-title">
          Playback
        </h2>
        <GaplessChoice player={player} />
        <p id="app-gapless-note" class="app-footnote app-choice-gap">
          An experiment: it shortens the pause between songs, and FLAC songs played one after
          another can join in one stream, with none at all.
        </p>
        <LookChoice look={opensAs} onChange={onOpensAs} />
        <p id="app-look-note" class="app-footnote app-choice-gap">
          The button at the top right of Now Playing switches between them until it closes.
        </p>
        <QualityChoice player={{ maxRate: player.maxRate, setMaxRate: actions.setMaxRate }} />
        <p class="app-footnote">
          All three are kept on this device. Maximum quality is used from the next song.
        </p>
      </section>

      <section class="app-section" aria-labelledby="app-connections-title">
        <div class="app-section-head">
          <h2 id="app-connections-title" class="app-section-title">
            Connections
          </h2>
          <button type="button" class="app-text-button" onClick={checkAll} disabled={!checks}>
            Check again
          </button>
        </div>
        <ul class="app-group">
          {SERVICES.map((service) => {
            const check = checks?.[service.id] ?? PENDING
            return (
              <li key={service.id} class="app-row app-status-row" aria-live="polite" aria-atomic="true">
                <span class="app-row-label">{service.label}</span>
                <span class="app-row-value">
                  <span class={`app-dot is-${check.state}`} aria-hidden="true" />
                  <span class="app-status-text">{check.text}</span>
                </span>
                {check.detail && <span class="app-row-detail">{check.detail}</span>}
              </li>
            )
          })}
        </ul>
      </section>

      {admin && (
        <section class="app-section" aria-labelledby="app-managing-title">
          <h2 id="app-managing-title" class="app-section-title">
            Managing deadwax
          </h2>
          <div class="app-group">
            <a class="app-row app-link-row" href="/" target="_blank" rel="noopener">
              <span class="app-row-label">Open the main page</span>
              <ChevronRightIcon class="app-chevron" />
            </a>
          </div>
          <p class="app-footnote">
            Server settings, albums that need a look, the log and editing an album are on the main
            page for now.
          </p>
        </section>
      )}

      <section class="app-section" aria-labelledby="app-about-title">
        <h2 id="app-about-title" class="app-section-title">
          About
        </h2>
        <dl class="app-group">
          <div class="app-row">
            <dt class="app-row-label">Version</dt>
            <dd class="app-row-value app-mono">{who?.version ?? (whoFailed ? 'unknown' : '…')}</dd>
          </div>
          <div class="app-row">
            <dt class="app-row-label">Logins</dt>
            <dd class="app-row-value">{who ? (who.auth === 'off' ? 'Off' : 'On') : whoFailed ? 'unknown' : '…'}</dd>
          </div>
        </dl>
        {whoFailed && <p class="app-footnote app-error">deadwax didn't answer: {whoFailed}</p>}
      </section>
    </section>
  )
}
