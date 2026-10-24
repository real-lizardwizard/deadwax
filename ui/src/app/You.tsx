import { useEffect, useMemo, useRef, useState } from 'preact/hooks'

import { pingMusicBrainz, pingSlskd, type PingAnswer } from '../api/connections'
import { me as fetchMe, type Me } from '../api/me'
import type { ManagingKind } from '../lib/appFrame'
import { isAbort, latestOnly } from '../lib/latest'
import { needsLookLabel } from '../lib/needsLook'
import { badgeText } from '../lib/requestsView'
import { navidromeStatus, type NavidromeStatus } from '../player/api'
import { readConfirmCancel, writeConfirmCancel } from '../state/persisted'
import { ChevronRightIcon } from '../player/icons'
import { usePlayerActions, usePlayerState } from './context'
import type { Look } from '../lib/turntable'
import { GaplessChoice } from './GaplessChoice'
import { ConfirmCancelChoice } from './ConfirmCancelChoice'
import { GettingChoices } from './GettingChoices'
import { LookChoice } from './LookChoice'
import { NormalizationChoice } from './NormalizationChoice'
import { QualityChoice } from './QualityChoice'
import { askGetSettings, chooseGetSettings, useGetSettings } from './useGetSettings'
import { WindDownChoice } from './WindDownChoice'
import { managing as managingOf, UNVERIFIED } from '../lib/permissions'
import { accessNow, noteAccess, seesDetail, useAccess } from './access'
import { errorNote } from './ErrorNote'
import { PING_UNANSWERED, pingWords, TELL, unansweredLine } from '../lib/errorWords'
import { SignOutRow } from './SignOutRow'
import { ChangePassword } from './ChangePassword'
import { changeOffered } from '../lib/ownPassword'
import { YourLibrary } from './YourLibrary'

/** (2.0.4) Getting albums' three, when deadwax's database can't keep them - "Tell whoever runs deadwax." after it for
 *  anyone else, who can't put the volume right. */
export const GETTING_UNSAVED = "deadwax can't keep these: its database isn't writable."

type CheckState = { state: 'pending' | 'ok' | 'failed'; text: string; detail?: string }

const SERVICES = [
  { id: 'musicbrainz', label: 'MusicBrainz' },
  { id: 'slskd', label: 'slskd' },
  { id: 'navidrome', label: 'Navidrome' },
] as const

type Service = (typeof SERVICES)[number]['id']

const PENDING: CheckState = { state: 'pending', text: 'Checking…' }


/** A ping's answer as a row says it: (2.0.4) a short word for its code, and the sentence under it - slskd's from the
 *  server (PING_WORDS), MusicBrainz's from lib/errorWords.ts - never the code itself, nor the log's own line. */
function fromPing(service: 'musicbrainz' | 'slskd', answer: PingAnswer): CheckState {
  if (String(answer.status).toLowerCase() === 'ok') return { state: 'ok', text: 'Connected' }
  const words = pingWords(service, answer.code, answer.error)
  return { state: 'failed', text: words.text, ...(words.line ? { detail: words.line } : {}) }
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
 * You: how Get works for you, what this device plays like, whether deadwax can reach what it needs,
 * and what version it is - and the way to the app's own Managing pages: the albums that need a look,
 * Library care, the server's settings and the log (below) - on a phone as on a desktop since
 * 2.0.0-player.47 (until then a phone's Managing said all of it was the main page's). The row and the
 * footnote pointing at the main page went when it retired (2.0.0-player.66): everything is here.
 *
 * - Getting albums (2.0.0-player.15, GettingChoices.tsx): "When I tap Get" (Show me the sources, the
 *   default, or Pick the best source for me), the quality floor and Format (2.0.0-player.41) - kept per USER on the server
 *   (useGetSettings.ts), asked each time You's tab is opened and on "Check again", so one changed on
 *   another device shows here without the app being killed. A choice not kept ("Not saved. …") is
 *   said in a live region that is always in the page, so VoiceOver hears why the choice went back.
 *   Under them (2.0.0-player.41, ConfirmCancelChoice.tsx) "Confirm before cancelling", which is this
 *   DEVICE's - Requests' ✕ reads it at the tap - with a note saying so: after the three's note and
 *   what went wrong keeping them, so neither reads as being about it.
 * - Playback: Gapless, a checkbox (GaplessChoice.tsx - moved here from the now-playing screen in
 *   2.0.0-player.10, where it was a switch), "Now Playing opens as" (LookChoice.tsx,
 *   2.0.0-player.11: the cover or the turntable - App keeps it, and hands it here), "Pause winds the
 *   record down" (WindDownChoice.tsx, 2.0.0-player.14: the turntable's pause - App keeps it too),
 *   and Maximum quality, moved here from the player's settings sheet - and
 *   (2.0.0-player.62) Normalization after it (NormalizationChoice.tsx: Automatic, By song, By album, Off -
 *   read at each play, never by the engine). All five are kept per device. Gapless is handed the player itself, whose `setGapless` it calls in the tap:
 *   this page names no playback action of its own (ui/test/app-rules.sim.cjs).
 * - Connections: the three pings the main page had, asked the first time You shows (not at start-up: the
 *   MusicBrainz ping is a real request to a rate-limited service), and again on "Check again". Each
 *   row is its own live region, read whole ("slskd, Connected"): the three answers land in any
 *   order, and a bare "Connected" says nothing about which service it is. (2.0.4) Whoever runs
 *   deadwax's alone - an admin, or someone with Settings and the log (access.ts seesDetail): nobody
 *   else is shown slskd's key refused or Navidrome's address, nor asked about them. A row says a word
 *   for its code ("Not on Soulseek", lib/errorWords.ts pingWords), never the code, with a sentence
 *   under it saying where to put it right - slskd's from the server (PING_WORDS), MusicBrainz's from
 *   pingWords - never the log's own line.
 * - About: from `GET /deadwax/me` - the version, and logins (on: who, Change password (2.0.2, ChangePassword.tsx - a
 *   Navidrome sign-in's, never break-glass's) and Sign out). Asked with the pings, and
 *   again on "Check again": deadwax restarting under Komodo while You first opened must not leave
 *   "unknown" there until the app is killed.
 * - "Albums that need a look" above it (2.0.0-player.25), with how many - the review queue's page,
 *   Needs a look (`onNeedsLook`: App opens it on this tab). Under it (2.0.0-player.33) "Server
 *   settings" and "Log", the app's own pages of them (`onManaging`: App opens them on this tab), and
 *   (2.0.0-player.42) "Library care" under the queue's row: Rescan and the bulk runs, the same way. A
 *   desktop's only until 2.0.0-player.47; a phone's too since.
 *
 * - Your library (2.0.0-player.51, YourLibrary.tsx): with logins on, at the top - how many albums your
 *   library (your starred albums in Navidrome) holds, what still waits to be starred and why ("sign in
 *   again" when Navidrome no longer takes your login), and what the admin deleted, to request again or
 *   put away. Nothing with logins off.
 *
 * THE WORDS (2.0.1, James: "I need the descriptions to be more user oriented and not testing oriented"):
 * every note under a choice says what it does for the person and when they'd pick it - never how it was
 * built or tried. tests/test_settings_words.py and you.sim scan for test-note words; you.sim and settings.sim
 * pin the words themselves.
 *
 * It works with Navidrome unset or down: nothing here waits on it. A page, so it reads the player
 * from context; `shown` is App's word that the tab has been opened at least once, `current` that it
 * is the tab showing now.
 */
export function You({
  shown,
  current,
  opensAs,
  onOpensAs,
  windDown,
  onWindDown,
  needsLook = null,
  onNeedsLook,
  onManaging,
  onRequestAgain,
}: {
  shown: boolean
  /** the tab showing now: Getting albums are asked again each time it becomes so */
  current: boolean
  /** "Now Playing opens as", and the way to change it - App's */
  opensAs: Look
  onOpensAs: (look: Look) => void
  /** "Pause winds the record down", and the way to change it - App's */
  windDown: boolean
  onWindDown: (on: boolean) => void
  /** how many albums need a look (null: not known yet) */
  needsLook?: number | null
  onNeedsLook?: () => void
  /** Library care, People, the server's settings, or the log: its page (2.0.0-player.33, .42, .61) */
  onManaging?: (kind: ManagingKind) => void
  /** (2.0.0-player.51) an album the admin deleted, requested again: its album page, where Get is */
  onRequestAgain?: (group: { id: string; title: string }) => void
}) {
  const player = usePlayerState()
  const actions = usePlayerActions()
  const [who, setWho] = useState<Me | null>(null)
  //? (2.0.4) the error itself, said by errorNote (app/ErrorNote.tsx): a listener's words, and its own for whoever runs deadwax
  const [whoFailed, setWhoFailed] = useState<unknown>(null)
  const [checks, setChecks] = useState<Record<Service, CheckState> | null>(null)
  const meRequests = useMemo(latestOnly, [])
  const pingRequests = useMemo(latestOnly, [])
  //? whether this showing of You has asked the pings yet
  const pinged = useRef(false)
  //? Getting albums: the server's answer, asked each time the tab is opened (the first time too)
  const getting = useGetSettings(current)
  //? "Confirm before cancelling": this device's (2.0.0-player.41) - Requests reads it at the tap
  const [confirmCancel, setConfirmCancel] = useState(readConfirmCancel)

  function askWho() {
    const request = meRequests.begin()
    setWhoFailed(null)
    fetchMe(request.signal).then(
      (answer) => {
        if (!request.current()) return
        setWho(answer)
        //? (2.0.0-player.61) what deadwax says this person may do - every reader of it redraws
        noteAccess(answer)
      },
      (reason: unknown) => {
        //? what deadwax said before stays (the version didn't change); the failure is said under it
        if (request.current() && !isAbort(reason)) setWhoFailed(reason)
      },
    )
  }

  function checkAll() {
    askWho()
    //? Getting albums too: changed on another device, they show here (what's in hand stands meanwhile)
    void askGetSettings()
    pingRequests.supersede()
    pinged.current = false
    //? (2.0.4) the rows are for whoever runs deadwax alone - nobody else is asked about, nor shown, slskd's key
    if (!seesDetail(accessNow())) {
      setChecks(null)
      return
    }
    pingAll()
  }

  function pingAll() {
    const request = pingRequests.begin()
    pinged.current = true
    setChecks({ musicbrainz: PENDING, slskd: PENDING, navidrome: PENDING })
    const settle = (service: Service, state: CheckState) => {
      if (request.current()) setChecks((now) => ({ ...(now ?? { musicbrainz: PENDING, slskd: PENDING, navidrome: PENDING }), [service]: state }))
    }
    //? the ask itself failing: its sentence, and the route's own words after it - the rows are only ever drawn for
    //? whoever runs deadwax, who needs them (review: "Something went wrong" alone told them nothing)
    const failed = (service: Service) => (reason: unknown) => {
      if (!isAbort(reason)) settle(service, { state: 'failed', text: PING_UNANSWERED, detail: unansweredLine(reason) })
    }
    pingMusicBrainz(request.signal).then((answer) => settle('musicbrainz', fromPing('musicbrainz', answer)), failed('musicbrainz'))
    pingSlskd(request.signal).then((answer) => settle('slskd', fromPing('slskd', answer)), failed('slskd'))
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

  //? (2.0.0-player.61) each Managing row by its permission - with logins off everyone has them all; on, the
  //? session's word until /me answers (access.ts). People only with logins on
  const access = useAccess()
  const runsDeadwax = seesDetail(access)
  //? (review) deadwax saying, while You is shown, that this person runs deadwax after all (an admin gave them Settings
  //? and the log since the session began): Connections is drawn now, so its rows are asked now - never left on
  //? "Checking…" with Check again disabled until You is opened again
  useEffect(() => {
    if (shown && runsDeadwax && !pinged.current) pingAll()
  }, [shown, runsDeadwax])
  const managing = managingOf(access.permissions, access.on)
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

      {/* (2.0.0-player.51) with logins on: your library - your starred albums - and how far its starring has got */}
      <YourLibrary current={current} onRequestAgain={onRequestAgain} />

      <section class="app-section" aria-labelledby="app-getting-title">
        <h2 id="app-getting-title" class="app-section-title">
          Getting albums
        </h2>
        <GettingChoices settings={getting.settings} onChoose={(values) => void chooseGetSettings(values)} />
        <p id="app-get-note" class="app-footnote">
          “Show me the sources” lets you choose each download yourself. “Pick the best source for me”
          downloads the best match that meets your quality floor, and shows you the sources instead when
          nothing matches well, or when you already have the album or are getting it. The quality floor is also what the sources start filtered to. Format:
          Prefer lossless ranks lossless downloads higher, and Lossless only leaves out anything without
          a lossless file. All three are kept for you on deadwax, so they follow you to every device.
        </p>
        {/* what went wrong keeping those three, right under them and their note - never under this
            device's own setting below, which deadwax's database has no part in */}
        {!getting.canSave && (
          <p class="app-footnote app-error">{GETTING_UNSAVED}{runsDeadwax ? '' : ` ${TELL}`}</p>
        )}
        {/* always in the page, so VoiceOver hears a choice that wasn't kept (it reads a region only
            once it is already there) - and, empty or not, the gap before the next choice */}
        <div class="app-choice-gap" aria-live="polite" aria-atomic="true">
          {getting.problem && <p class="app-footnote app-error">{getting.problem}</p>}
        </div>
        <ConfirmCancelChoice
          on={confirmCancel}
          onChange={(on) => {
            writeConfirmCancel(on)
            setConfirmCancel(on)
          }}
        />
        <p id="app-confirm-cancel-note" class="app-footnote">
          The ✕ on a download in Requests asks first. Kept on this device.
        </p>
      </section>

      <section class="app-section" aria-labelledby="app-playback-title">
        <h2 id="app-playback-title" class="app-section-title">
          Playback
        </h2>
        <GaplessChoice player={player} />
        <p id="app-gapless-note" class="app-footnote app-choice-gap">
          Plays one song straight into the next. In Safari and Chrome, FLAC albums play through with no
          pause at all, as they were recorded; other songs change with a much shorter pause. It
          downloads the next song ahead, which uses more data, and on a slow connection that can stop
          helping: turn it off if song changes are no quicker.
        </p>
        <LookChoice look={opensAs} onChange={onOpensAs} />
        <p id="app-look-note" class="app-footnote app-choice-gap">
          What you see first when you open Now Playing. The button at its top right switches between
          the two while it's open. For phones: a big screen has no Now Playing view.
        </p>
        <WindDownChoice on={windDown} onChange={onWindDown} />
        <p id="app-wind-down-note" class="app-footnote app-choice-gap">
          On the turntable, pausing slows the music to a stop over about a second, as a real record
          deck does. Turn it off to stop at once. Pausing from the cover always stops at once. For
          phones: a big screen has no turntable.
        </p>
        <QualityChoice player={{ maxRate: player.maxRate, setMaxRate: actions.setMaxRate }} />
        <NormalizationChoice />
        <p id="app-normalization-note" class="app-footnote app-choice-gap">
          Evens out FLAC songs only - other files play as they are. The first time an album is levelled,
          deadwax measures it, so its first song can take a few seconds to start.
        </p>
        <p class="app-footnote">
          These are kept on this device. Maximum quality changes from the next song, and Normalization from
          the next thing you play.
        </p>
      </section>

      {/* (2.0.4) whoever runs deadwax's alone - an admin, or someone with Settings and the log (access.ts seesDetail):
          what slskd's key or Navidrome's address is doing is nothing anyone else can act on */}
      {runsDeadwax && (
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
      )}

      {access.unverified && <p class="app-footnote app-you-unverified">{UNVERIFIED}</p>}

      {managing.any && (
        <section class="app-section" aria-labelledby="app-managing-title">
          <h2 id="app-managing-title" class="app-section-title">
            Managing deadwax
          </h2>
          <div class="app-group">
            {managing.queue && (
              <button
                type="button"
                class="app-row app-link-row app-queue-link-row"
                {...(needsLook ? { 'aria-label': needsLookLabel('Albums that need a look', needsLook) } : {})}
                onClick={() => onNeedsLook?.()}
              >
                <span class="app-row-label">Albums that need a look</span>
                {badgeText(needsLook ?? 0) && (
                  <span class="app-queue-badge app-mono" aria-hidden="true">
                    {badgeText(needsLook ?? 0)}
                  </span>
                )}
                <ChevronRightIcon class="app-chevron" />
              </button>
            )}
            {managing.care && (
              <button type="button" class="app-row app-link-row app-queue-link-row" onClick={() => onManaging?.('care')}>
                <span class="app-row-label">Library care</span>
                <ChevronRightIcon class="app-chevron" />
              </button>
            )}
            {managing.people && (
              <button type="button" class="app-row app-link-row app-queue-link-row" onClick={() => onManaging?.('people')}>
                <span class="app-row-label">People</span>
                <ChevronRightIcon class="app-chevron" />
              </button>
            )}
            {managing.settings && (
              <button type="button" class="app-row app-link-row app-queue-link-row" onClick={() => onManaging?.('settings')}>
                <span class="app-row-label">Server settings</span>
                <ChevronRightIcon class="app-chevron" />
              </button>
            )}
            {managing.log && (
              <button type="button" class="app-row app-link-row app-queue-link-row" onClick={() => onManaging?.('log')}>
                <span class="app-row-label">Log</span>
                <ChevronRightIcon class="app-chevron" />
              </button>
            )}
          </div>
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
        {whoFailed ? errorNote(whoFailed, { class: 'app-footnote app-error' }) : null}
        {/* (2.0.2) your own Navidrome password - logins on and a Navidrome sign-in only (never break-glass) */}
        {who && changeOffered(who) && <ChangePassword user={who.user} />}
        {/* (2.0.0-player.48) only with logins on - off, there is nobody to sign out */}
        {who?.auth === 'on' && <SignOutRow user={who.user} />}
      </section>
    </section>
  )
}
