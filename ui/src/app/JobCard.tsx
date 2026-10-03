import { useState } from 'preact/hooks'

import type { RequestRow } from '../lib/requestsView'
import { CloseIcon, PlayIcon } from '../player/icons'

/**
 * A download, drawn as the Requests board draws it (2.0.0-player.12): a card for one on its way or
 * needing attention, a plain row for one done, and Home's Arriving card. Every word comes from the
 * row (lib/requestsView.ts); these only lay it out, and hand a tap to the page.
 *
 * Leaves: they take props, and read no context (the fake-Preact sims have none).
 */

/**
 * The pressing's cover from the Cover Art Archive, or a plain tile - with no release id, while it
 * loads nothing, and when it fails: offline, or an album the Archive has no picture for. It
 * remembers WHICH address failed, as player/Cover.tsx does, so a row that moves on (next peer, a
 * poll) never keeps a blank from the one before.
 */
export function JobCover({ src, large = false }: { src: string | null; large?: boolean }) {
  const [failed, setFailed] = useState<string | null>(null)
  const shown = src && src !== failed ? src : null
  const cls = `app-job-cover${large ? ' is-large' : ''}`
  return shown ? (
    <img class={cls} src={shown} alt="" loading="lazy" decoding="async" onError={() => setFailed(shown)} />
  ) : (
    <span class={`${cls} is-empty`} aria-hidden="true" />
  )
}

/** The thin sunken bar with the purple fill. Its words are beside it, so it is only drawn. */
export function JobBar({ progress }: { progress: number }) {
  return (
    <span class="app-bar" aria-hidden="true">
      <span class="app-bar-fill" style={{ width: `${progress}%` }} />
    </span>
  )
}

/**
 * What a card with a ✕ takes. A tap on the ✕ is the page's to interpret (Requests.tsx): it cancels
 * at once, or - with "Confirm before cancelling" on - asks first, IN the card (`asking`): a line
 * saying what it costs, "Keep it" and "Cancel download". Never window.confirm(): a blocking dialog
 * holds the page's JavaScript, and this page plays the music - the next song, a stream's refill and
 * the lock screen's controls would all wait for it.
 */
export interface CancelProps {
  /** the ✕ tapped */
  onCancel: (row: RequestRow) => void
  /** this card is asking "cancel it?" */
  asking?: boolean
  /** "Keep it": stop asking */
  onKeep?: () => void
  /** "Cancel download": cancel it */
  onConfirm?: (row: RequestRow) => void
}

const confirmId = (row: RequestRow) => `app-confirm-${row.key}`

/**
 * ✕ - a tap target tall, the board's 32px box drawn inside it. It opens the card's question (and a
 * second tap closes it), so it says it is expanded while that shows. While its cancel is on its
 * way it waits, aria-disabled rather than disabled: a disabled button drops the focus a keyboard
 * or VoiceOver had on it, and the tap is refused here instead.
 */
function CancelButton({ row, onCancel, asking = false }: { row: RequestRow; onCancel: (row: RequestRow) => void; asking?: boolean }) {
  if (!row.cancel) return null
  const waiting = row.cancel === 'cancelling'
  return (
    <button
      type="button"
      class="app-job-cancel"
      aria-label={`Cancel ${row.title}`}
      aria-disabled={waiting}
      aria-expanded={asking}
      {...(asking ? { 'aria-controls': confirmId(row) } : {})}
      onClick={() => {
        if (!waiting) onCancel(row)
      }}
    >
      <span class="app-job-cancel-face">
        <CloseIcon class="app-job-cancel-icon" />
      </span>
    </button>
  )
}

/** The card's question, under its words: what a cancel costs, and the two answers. */
function CancelConfirm({
  row,
  onKeep,
  onConfirm,
}: {
  row: RequestRow
  onKeep: (() => void) | undefined
  onConfirm: ((row: RequestRow) => void) | undefined
}) {
  return (
    <div class="app-job-confirm" id={confirmId(row)} role="group" aria-label={`Cancel ${row.title}?`}>
      <span class="app-job-confirm-text">Cancel this download? You'll lose your place in this peer's queue.</span>
      <div class="app-job-actions">
        <button type="button" class="app-job-action is-secondary" onClick={() => onKeep?.()}>
          <span class="app-job-action-label">Keep it</span>
        </button>
        <button type="button" class="app-job-action is-secondary is-danger" onClick={() => onConfirm?.(row)}>
          <span class="app-job-action-label">Cancel download</span>
        </button>
      </div>
    </div>
  )
}

const toneClass = (row: RequestRow) => (row.lineTone === 'plain' ? '' : ` is-${row.lineTone}`)

const asked = (row: RequestRow, asking: boolean) => asking && row.cancel === 'ready'

/** Downloading: the bigger cover, who and from where, the bar, and "6 of 10 files · 1.8 MB/s". */
export function DownloadingCard({ row, onCancel, asking = false, onKeep, onConfirm }: { row: RequestRow } & CancelProps) {
  const question = asked(row, asking)
  return (
    <div class={`app-card app-job is-downloading${row.dimmed ? ' is-dimmed' : ''}${question ? ' is-asking' : ''}`}>
      <JobCover src={row.cover} large />
      <div class="app-job-body">
        <span class="app-job-title">{row.title}</span>
        <span class="app-job-line">{row.line}</span>
        <JobBar progress={row.progress} />
        <span class="app-job-data">{row.data}</span>
      </div>
      <CancelButton row={row} onCancel={onCancel} asking={question} />
      {question && <CancelConfirm row={row} onKeep={onKeep} onConfirm={onConfirm} />}
    </div>
  )
}

/**
 * Waiting: who and from where, and its place - "#4 in their queue", "starting", "asking slskd…" -
 * in amber when the peer has already refused some of its files.
 */
export function WaitingCard({ row, onCancel, asking = false, onKeep, onConfirm }: { row: RequestRow } & CancelProps) {
  const question = asked(row, asking)
  return (
    <div class={`app-card app-job${row.dimmed ? ' is-dimmed' : ''}${question ? ' is-asking' : ''}`}>
      <JobCover src={row.cover} />
      <div class="app-job-body">
        <span class="app-job-title">{row.title}</span>
        <span class={`app-job-line${toneClass(row)}`}>{row.line}</span>
      </div>
      <CancelButton row={row} onCancel={onCancel} asking={question} />
      {question && <CancelConfirm row={row} onKeep={onKeep} onConfirm={onConfirm} />}
    </div>
  )
}

/**
 * Needs attention: why it stopped, in red, and the two ways on - "Next peer · N left" (primary
 * only on the first such card) and "Ask again". While one runs both wait, the one tapped saying
 * what it's doing - aria-disabled, the tap refused here, so the focus on the one tapped stays put;
 * a refusal is the red line under the reason. Each label is a span inside its button, which is
 * where the ellipsis goes: clipping the button would clip its reach to 44px away too.
 */
export function AttentionCard({
  row,
  onRetry,
}: {
  row: RequestRow
  onRetry: (row: RequestRow, samePeer: boolean) => void
}) {
  const nextPeer = row.nextPeer
  const askAgain = row.askAgain
  return (
    <div class="app-card app-job is-attention">
      <div class="app-job-top">
        <JobCover src={row.cover} />
        <div class="app-job-body">
          <span class="app-job-title">{row.title}</span>
          {row.line && <span class="app-job-line">{row.line}</span>}
          {row.reason && <span class="app-job-reason">{row.reason}</span>}
          {row.problem && <span class="app-job-reason">{row.problem}</span>}
        </div>
      </div>
      {(nextPeer || askAgain) && (
        <div class={`app-job-actions${nextPeer && askAgain ? '' : ' is-single'}`}>
          {nextPeer && (
            <button
              type="button"
              class={`app-job-action ${nextPeer.primary ? 'is-primary' : 'is-tinted'}${row.busy ? ' is-busy' : ''}`}
              aria-disabled={row.busy}
              onClick={() => {
                if (!row.busy) onRetry(row, false)
              }}
            >
              <span class="app-job-action-label">{nextPeer.label}</span>
            </button>
          )}
          {askAgain && (
            <button
              type="button"
              class={`app-job-action is-secondary${row.busy ? ' is-busy' : ''}`}
              aria-disabled={row.busy}
              onClick={() => {
                if (!row.busy) onRetry(row, true)
              }}
            >
              <span class="app-job-action-label">{askAgain.label}</span>
            </button>
          )}
        </div>
      )}
    </div>
  )
}

/**
 * Done: how it ended and how long ago. Since 2.0.0-player.17, a download whose album is in the library
 * (`row.release`: filed, partly filed, or already there) OPENS it - the row is a button - and one this
 * download filed (`row.plays`) has the board's round ▶, which plays it: the page decides, in the tap,
 * whether the album's songs are in hand to play, and opens the album otherwise. `note` is the page's
 * own word for a row it couldn't open ("Navidrome hasn't found it yet"); `opening` while it looks,
 * faded so the tap shows it was taken.
 */
export function DoneRow({
  row,
  onOpen,
  onPlay,
  opening = false,
  note = null,
}: {
  row: RequestRow
  onOpen?: (row: RequestRow) => void
  onPlay?: (row: RequestRow) => void
  opening?: boolean
  note?: string | null
}) {
  const body = (
    <>
      <JobCover src={row.cover} />
      <span class="app-job-body">
        <span class="app-job-title">{row.title}</span>
        <span class={`app-job-line${toneClass(row)}`}>{row.line}</span>
        {note && <span class="app-job-line is-warning">{note}</span>}
      </span>
    </>
  )
  return (
    <div class="app-done-row">
      {row.release && onOpen ? (
        <button type="button" class={`app-done-open${opening ? ' is-busy' : ''}`} aria-busy={opening} onClick={() => onOpen(row)}>
          {body}
        </button>
      ) : (
        <div class="app-done-open">{body}</div>
      )}
      {row.release && row.plays && onPlay && (
        <button type="button" class="app-done-play" aria-label={`Play ${row.title}`} onClick={() => onPlay(row)}>
          <span class="app-done-play-face">
            <PlayIcon class="app-done-play-icon" />
          </span>
        </button>
      )}
    </div>
  )
}

/** Home's Arriving card: cover, title, artist and the bar, and its state at the end. Goes to Requests. */
export function ArrivingCard({ row, onOpen }: { row: RequestRow; onOpen: () => void }) {
  return (
    <button type="button" class="app-card app-job app-arriving-card" onClick={onOpen}>
      <JobCover src={row.cover} />
      <span class="app-job-body">
        <span class="app-job-title">{row.title}</span>
        {row.artist && <span class="app-job-line">{row.artist}</span>}
        <JobBar progress={row.progress} />
      </span>
      <span class="app-job-brief">{row.brief}</span>
    </button>
  )
}
