import { useEffect, useMemo, useState } from 'preact/hooks'

import { logStreamUrl, recentLog, type LogLine } from '../api/logs'
import {
  EMPTY_WORDS,
  LOG_PHONE,
  STREAM_RETRY_MS,
  STREAM_WORDS,
  clearLog,
  emptyLog,
  joinHistory,
  joinLine,
  levelOf,
  lineTime,
  type LogState,
  type StreamState,
} from '../lib/eventLog'
import { isAbort, latestOnly } from '../lib/latest'
import { ChevronLeftIcon } from '../player/icons'

/** The page's lines, beyond its own life - one page's worth, shared by every copy mounted (an address
 *  can put it on another tab too; only the copy that shows ever listens). */
let kept: LogState = emptyLog()
const listeners = new Set<() => void>()

function keep(update: (state: LogState) => LogState): void {
  kept = update(kept)
  for (const listener of [...listeners]) listener()
}

/** For the sims: forget the lines, as a fresh page would. */
export function forgetEventLogPage(): void {
  kept = emptyLog()
}

/**
 * The event log in the app, on a desktop (2.0.0-player.33) - the main page's log (interface/scripts/
 * init.js, which is left as it is) as a page of the app, pushed on You (`#/you/log/all`). There is no
 * board for it; the desktop sidebar's Managing names it.
 *
 * THE LINES are TEXT, never markup: the log quotes MusicBrainz titles, Soulseek queries and folder
 * paths, all typed by strangers (the v0.9.21 rule). Newest first, as the main page's; each with its
 * time (the server's, as it logged it), its level - errors red, warnings amber - and its words. At most
 * LOG_KEPT (500) are kept, the oldest dropped. Clear empties the view, nothing on the server.
 *
 * THE HISTORY AND THE STREAM: deadwax keeps the last 500 lines meant for the page (src/logger.py). As
 * the page shows it reads them (GET /interface_logs/recent), then opens the stream from the last number
 * it has; the stream sends the kept lines after that first, and EventSource reconnecting by itself asks
 * from the same number. Each line is shown once, by its number (lib/eventLog.ts) - and a history that
 * couldn't be read is filled in by the next that can. Where the stream stands - connecting, live, lost
 * and trying again - is ONE line above the log, never a column of failures in it. "Trying again" is
 * kept true: EventSource tries again by itself only after a network error, and an answer that isn't
 * the stream (a reverse proxy's 502 while deadwax restarts) ends it for good - then the page asks
 * again itself, the history first, every STREAM_RETRY_MS.
 *
 * THE STREAM IS HELD ONLY WHILE THIS PAGE IS WHAT SHOWS (`live`: a desktop, an admin, the page in front,
 * the visualizer not over it - App's word) and closed otherwise: the player fetches its audio from the
 * same host over plain http/1.1, where a held connection is one of the six a browser allows. Coming back,
 * the history is read again and the stream rejoined by number. So there is no unread badge anywhere - it
 * would need the stream held open.
 *
 * THE LINES OUTLIVE THE PAGE (`kept`, below - review): App draws only the page on top of each tab, so
 * the page goes whenever another takes its place (the sidebar's Settings or Needs a look, Back). The
 * lines on screen, the number they reach, a gap still to fill and a Clear are kept in this module, so
 * coming back is coming back into view: the history joined by number, nothing twice, and nothing
 * cleared back again. Kept until a reload.
 *
 * On a PHONE it is a short note, asking nothing.
 */
export function EventLog({
  desktop,
  live,
  onBack,
  backLabel,
}: {
  desktop: boolean
  /** this page is what shows - its tab current, the app in front, nothing over it */
  live: boolean
  onBack: () => void
  backLabel: string
}) {
  //? the lines are the module's (`kept`): this copy draws them, and is drawn again as they change - the
  //? stream's listeners, which outlive the render that made them, read and join them there too
  const [, redraw] = useState(0)
  useEffect(() => {
    const listener = () => redraw((n) => n + 1)
    listeners.add(listener)
    return () => {
      listeners.delete(listener)
    }
  }, [])
  const log = kept
  const [stream, setStream] = useState<StreamState>('connecting')
  const [historyFailed, setHistoryFailed] = useState<string | null>(null)
  const reads = useMemo(latestOnly, [])

  const join = keep

  useEffect(() => {
    if (!desktop || !live) return
    let source: EventSource | null = null
    let closed = false
    let retry: ReturnType<typeof setTimeout> | null = null
    setStream('connecting')

    const open = () => {
      if (closed) return
      const { last, boot } = kept
      const made = new EventSource(logStreamUrl(boot ? last : null, boot))
      source = made
      made.onopen = () => {
        if (!closed) setStream('live')
      }
      made.onerror = () => {
        //? one line says so, never a column
        if (closed) return
        setStream('lost')
        //? after a network error EventSource tries again by itself, from the same number. An answer
        //? that isn't the stream ends it for good (CLOSED): then it is asked again here, after a pause
        if (made.readyState !== EventSource.CLOSED || retry) return
        made.close()
        if (source === made) source = null
        retry = setTimeout(() => {
          retry = null
          connect()
        }, STREAM_RETRY_MS)
      }
      made.onmessage = (event: MessageEvent) => {
        if (closed) return
        let line: LogLine
        try {
          line = JSON.parse(String(event.data)) as LogLine
        } catch {
          return
        }
        join((state) => joinLine(state, line))
      }
    }

    //? the history, then the stream from where it ends
    const connect = () => {
      const ticket = reads.begin()
      recentLog(ticket.signal).then(
        (recent) => {
          if (!ticket.current() || closed) return
          setHistoryFailed(null)
          join((state) => joinHistory(state, recent))
          open()
        },
        (reason: unknown) => {
          if (!ticket.current() || closed || isAbort(reason)) return
          //? the history couldn't be had: the stream still says what happens from now (and the next
          //? history read fills in what it would have)
          setHistoryFailed(reason instanceof Error ? reason.message : String(reason))
          open()
        },
      )
    }
    connect()

    return () => {
      closed = true
      reads.supersede()
      source?.close()
      source = null
      if (retry) clearTimeout(retry)
    }
  }, [desktop, live])

  const header = (
    <>
      <header class="pl-nav-bar">
        <button type="button" class="pl-back" onClick={onBack}>
          <ChevronLeftIcon class="pl-back-icon" />
          <span class="pl-back-label">{backLabel}</span>
        </button>
      </header>
      <header class="pl-large-header">
        <h1 class="pl-large-title">Log</h1>
      </header>
    </>
  )

  if (!desktop) {
    return (
      <section class="app-log is-phone app-needs">
        {header}
        <div class="app-card app-placeholder-body">
          <p class="app-placeholder-text app-log-phone">
            {LOG_PHONE}{' '}
            <a class="app-queue-link" href="/" target="_blank" rel="noopener">
              the main page
            </a>
            .
          </p>
        </div>
      </section>
    )
  }

  return (
    <section class="app-log">
      {header}
      <div class="app-log-body">
        <div class="app-log-bar">
          <p class={`app-log-stream is-${stream}`} role="status">
            <span class="app-log-dot" aria-hidden="true" />
            {STREAM_WORDS[stream]}
          </p>
          <button
            type="button"
            class="app-text-button app-log-clear"
            aria-disabled={log.lines.length ? undefined : 'true'}
            onClick={() => {
              if (log.lines.length) join(clearLog)
            }}
          >
            Clear
          </button>
        </div>
        <p class="app-log-line">
          What deadwax has said since it started - the last 500 lines - newest first. Clear empties this view only.
        </p>
        {historyFailed && <p class="app-log-problem">deadwax couldn't send the lines it kept: {historyFailed}</p>}
        {!log.lines.length ? (
          <p class="app-log-empty">{log.cleared ? EMPTY_WORDS.cleared : EMPTY_WORDS.never}</p>
        ) : (
          <ol class="app-log-list" aria-label="Log, newest first">
            {log.lines.map((line, index) => {
              const level = levelOf(line.event_type)
              return (
                <li key={line.seq !== undefined ? `${line.boot ?? ''}:${line.seq}` : `n${index}`} class={`app-log-row is-${level}`}>
                  <span class="app-log-time app-mono">{lineTime(line)}</span>
                  <span class="app-log-level">{line.event_type}</span>
                  {/* always drawn, so a line with no source keeps its words in the column of those with one */}
                  <span class="app-log-src" {...(line.src ? { title: line.src } : {})}>{line.src ?? ''}</span>
                  <span class="app-log-words">{line.event_content}</span>
                </li>
              )
            })}
          </ol>
        )}
      </div>
    </section>
  )
}
