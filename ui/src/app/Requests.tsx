import type { JSX } from 'preact'
import { useEffect, useLayoutEffect, useMemo, useRef, useState } from 'preact/hooks'

import { storeAlbum } from '../api/store'
import type { StoreAlbumResponse } from '../api/types'
import { isAbort, latestOnly } from '../lib/latest'
import {
  SECTIONS, SECTION_TITLES, changes, doneLooks, type RequestRow, type RequestsView, type Section,
} from '../lib/requestsView'
import { prefetchAlbum, rememberPlayed, toQueueTrack, type Album, type AlbumWithSongs } from '../player/api'
import { readPreferences } from '../state/persisted'
import { usePlayerActions } from './context'
import { AttentionCard, DoneRow, DownloadingCard, WaitingCard } from './JobCard'

/** How many Done rows have their album asked for ahead of a tap, so their ▶ plays at once - the
 *  newest first, as they are listed. A tap on any other opens the album, where Play is. */
export const DONE_PREFETCHED = 5

/** What a Done row says when Navidrome has no album for it (yet). */
export const NOT_IN_NAVIDROME = "Navidrome hasn't found it yet - it may still be scanning"

/** ...when no folder of the library is tagged with its release - an untagged copy it matched, or a
 *  folder since gone - so nothing can say which album in Navidrome it is. */
export const NOT_IN_STORE = "deadwax can't tell which album in your library this is - its folder has no MusicBrainz release id"

/** ...when deadwax itself didn't answer the look. */
export const NOT_LOOKED_UP = "Couldn't look it up just now - tap to try again"

const without = <V,>(map: ReadonlyMap<string, V>, key: string): Map<string, V> => {
  const next = new Map(map)
  next.delete(key)
  return next
}

/**
 * The Requests tab (2.0.0-player.12): the downloads, as the Requests board draws them - Downloading,
 * Waiting, Needs attention and Done, each only when it has something in it - and "Clear done".
 *
 * Everything comes from App, which calls useDownloadJobs ONCE for the whole app (it polls fast only
 * while this tab shows) and works the rows out with lib/requestsView.ts: the headings, the words,
 * which button is the primary one. This lays them out and hands taps back - cancel, next peer, ask
 * again, clear - to the hook's own actions, which put their overlay up in the tap ("cancelling…",
 * "trying next peer…") before anything goes to the server.
 *
 * Until the first answer comes (`answered`), a spinner - never "Nothing requested yet", which would
 * be a claim made before anything was known: a cold open on #requests (iOS reloads a tab it put
 * aside) waits a round trip, and longer while slskd is slow to answer deadwax.
 *
 * Cancelling asks first, IN the card - "Keep it" or "Cancel download" - unless "Confirm before
 * cancelling" is turned off on this device (the main page's preference, read at the tap): a cancel
 * gives up the place in the peer's queue, and with SLSKD_INCOMPLETE_PATH set deletes the
 * part-downloaded file. Never window.confirm(), which would hold the page that plays the music
 * (JobCard.tsx says why). One card asks at a time.
 *
 * For a screen reader, one polite live region says what changed (lib/requestsView.ts's `changes`):
 * a card under another heading, a retry's refusal, a tap's answer starting. A card that moved is
 * drawn afresh in another list, so the control a keyboard had on it is gone; focus goes to the card
 * in its new place instead of falling to the page.
 *
 * Done rows (2.0.0-player.17's id bridge): one whose album is in the library opens it - Navidrome's
 * album for the release, which the server looks up (GET /store/album) - and one this download filed
 * plays it from its ▶. The gesture rule: the ▶ calls playTracks straight from the tap, and only with
 * the album's songs already in hand, opening the album otherwise, as a Search song does. The first
 * DONE_PREFETCHED such rows have theirs asked for (KEPT) while the tab is what shows (`active` -
 * never as the app starts: the root is mounted hidden from the start), and looked for again
 * (lib/requestsView.ts's doneLooks) until found: Navidrome scans what a download filed only a few
 * seconds after it lands, so the first look at an album filed while you watch finds nothing - and
 * asked again when a later download of the same release may have added to it, or the tab comes
 * back after a while (review). A tap that finds the album asks for its songs too, so the next ▶
 * plays. A row it can't open says why: Navidrome not set up or not answering (`navidromeProblem`),
 * no folder tagged with the release, Navidrome not having found it yet - and the note goes once a
 * later look finds it. Each look goes through a latestOnly() of its own, and a tap's look still out
 * when the tab stops being what shows opens nothing (review: it pushed the album onto whichever tab
 * you had gone to). A page: it reads the player's actions from context.
 */
export function Requests({
  view,
  answered = true,
  trackingEnabled,
  error,
  active = false,
  navidromeProblem = null,
  onCancel,
  onRetry,
  onClear,
  onOpenAlbum,
}: {
  view: RequestsView
  /** deadwax has answered once (or failed to): until then nothing is known, empty or not */
  answered?: boolean
  /** false when deadwax can't write its database: downloads still work, but none is kept track of */
  trackingEnabled: boolean
  /** why the last look at the downloads failed; the rows stay as they were meanwhile */
  error: string | null
  /** the tab's root is what shows (App's watching, and no sheet over it): the Done rows' albums are
   *  asked for, and looked for again, only then */
  active?: boolean
  /** why Navidrome can't be asked for an album now (not set up, not answering); null when it can, or
   *  nobody knows yet */
  navidromeProblem?: string | null
  onCancel: (jobId: number) => Promise<void>
  onRetry: (jobId: number, samePeer?: boolean) => Promise<void>
  onClear: () => Promise<void>
  /** a Done row's album, opened on this tab */
  onOpenAlbum?: (album: Album) => void
}) {
  const actions = usePlayerActions()
  //? the card asking "cancel it?", by its row's key - one at a time
  const [asking, setAsking] = useState<string | null>(null)
  //? the tab shows, read when an answer lands
  const showing = useRef(active)
  showing.current = active

  //? the Done rows' albums, by release: Navidrome's id once found, the songs of the first few (and
  //? when they were asked), the looks that found nothing, and why a tapped row couldn't open
  const [albumIds, setAlbumIds] = useState<ReadonlyMap<string, string>>(new Map())
  const [ready, setReady] = useState<ReadonlyMap<string, { answer: AlbumWithSongs; at: number }>>(new Map())
  const [misses, setMisses] = useState<ReadonlyMap<string, { count: number; at: number }>>(new Map())
  const [notes, setNotes] = useState<ReadonlyMap<string, string>>(new Map())
  const [opening, setOpening] = useState<string | null>(null)
  //? a look falling due: the looks are worked out again
  const [due, setDue] = useState(0)
  const aheadRequests = useMemo(latestOnly, [])
  const openRequests = useMemo(latestOnly, [])
  const inFlight = useRef(new Set<string>())
  const period = useRef<ReturnType<typeof aheadRequests.begin> | null>(null)
  const activeSince = useRef(0)
  const mounted = useRef(true)

  //? when each Done row first showed as done, by this device's clock - 0 for one already done in
  //? deadwax's first answer: nothing it filed is still being scanned
  const doneSince = useRef(new Map<string, number>())
  const baseline = useRef(false)
  for (const row of view.sections.done) {
    if (!doneSince.current.has(row.key)) doneSince.current.set(row.key, answered && baseline.current ? Date.now() : 0)
  }
  if (answered) baseline.current = true

  const ahead = view.sections.done
    .filter((row) => row.plays && row.release)
    .slice(0, DONE_PREFETCHED)
    .map((row) => ({ release: row.release!, since: doneSince.current.get(row.key) ?? 0 }))
  const aheadKey = ahead.map((row) => `${row.release} ${row.since}`).join('\n')

  //? an album found: its id kept, and nothing left saying it couldn't be
  const found = (release: string, album: string) => {
    setAlbumIds((before) => new Map(before).set(release, album))
    setMisses((before) => without(before, release))
    setNotes((before) => without(before, release))
  }
  const missed = (release: string) =>
    setMisses((before) => new Map(before).set(release, { count: (before.get(release)?.count ?? 0) + 1, at: Date.now() }))

  /** An album's songs, asked for KEPT - asked anew when an earlier answer may be out of date - and
   *  a failure forgets its id (the album gone, or re-filed under another), so the next look asks
   *  the bridge again. */
  const askSongs = (release: string, album: string, fresh: boolean, live: () => boolean) => {
    inFlight.current.add(release)
    const at = Date.now()
    prefetchAlbum(album, true, fresh).then(
      (answer) => {
        inFlight.current.delete(release)
        if (live()) setReady((before) => new Map(before).set(release, { answer, at }))
      },
      () => {
        inFlight.current.delete(release)
        if (!live()) return
        setAlbumIds((before) => without(before, release))
        setReady((before) => without(before, release))
        missed(release)
      },
    )
  }

  //? the tab coming into view starts a period of looking; leaving it calls everything still out off
  useEffect(() => {
    inFlight.current.clear()
    if (active) {
      period.current = aheadRequests.begin()
      activeSince.current = Date.now()
    } else {
      aheadRequests.supersede()
      period.current = null
      openRequests.supersede()
      setOpening(null)
    }
  }, [active])

  //? the first few Done rows' albums: looked for, and their songs asked for, as doneLooks says - and
  //? looked at again when the soonest falls due
  useEffect(() => {
    const request = period.current
    if (!active || !request || !ahead.length) return
    const { look, songs, nextIn } = doneLooks(ahead, {
      ids: albumIds, asked: new Map([...ready].map(([release, entry]) => [release, entry.at])), misses,
      inFlight: inFlight.current, activeSince: activeSince.current,
    }, Date.now())
    const live = () => request.current()
    for (const release of look) {
      inFlight.current.add(release)
      storeAlbum({ release_mbid: release }, request.signal).then(
        (answer) => {
          inFlight.current.delete(release)
          if (!live()) return
          if (!answer.navidrome_id) {
            missed(release)
            return
          }
          found(release, answer.navidrome_id)
          askSongs(release, answer.navidrome_id, false, live)
        },
        (reason: unknown) => {
          inFlight.current.delete(release)
          if (live() && !isAbort(reason)) missed(release)
        },
      )
    }
    for (const release of songs) askSongs(release, albumIds.get(release)!, ready.has(release), live)
    if (nextIn === null) return
    const timer = setTimeout(() => setDue((count) => count + 1), nextIn)
    return () => clearTimeout(timer)
  }, [active, aheadKey, due, albumIds, ready, misses])

  useEffect(() => () => {
    mounted.current = false
    aheadRequests.supersede()
    openRequests.supersede()
  }, [])

  /** Why a row's album can't be opened, from the bridge's answer: Navidrome itself, no folder tagged
   *  with the release, or Navidrome not having found it yet. */
  const noteFor = (answer: StoreAlbumResponse) =>
    navidromeProblem ?? (answer.present.length ? NOT_IN_NAVIDROME : NOT_IN_STORE)

  /** A Done row's tap: the album it brought, on this tab - looked up now when it isn't known yet,
   *  its songs asked for too when the row plays, so the next ▶ does. */
  const openRow = (row: RequestRow) => {
    if (!row.release || !onOpenAlbum) return
    const name = row.album || row.title
    const release = row.release
    const known = albumIds.get(release)
    if (known) {
      openRequests.supersede()
      setOpening(null)
      onOpenAlbum({ id: known, name, ...(row.artist ? { artist: row.artist } : {}) })
      return
    }
    const request = openRequests.begin()
    setOpening(row.key)
    storeAlbum({ release_mbid: release }, request.signal).then(
      (answer) => {
        if (!request.current()) return
        setOpening(null)
        if (!answer.navidrome_id) {
          setNotes((before) => new Map(before).set(release, noteFor(answer)))
          return
        }
        found(release, answer.navidrome_id)
        if (row.plays && !inFlight.current.has(release)) askSongs(release, answer.navidrome_id, false, () => mounted.current)
        if (showing.current) onOpenAlbum({ id: answer.navidrome_id, name, ...(row.artist ? { artist: row.artist } : {}) })
      },
      (reason: unknown) => {
        if (!request.current() || isAbort(reason)) return
        setOpening(null)
        setNotes((before) => new Map(before).set(release, navidromeProblem ?? NOT_LOOKED_UP))
      },
    )
  }

  /** A Done row's ▶: its album from the top when its songs are in hand; otherwise open it. */
  const playRow = (row: RequestRow) => {
    const album = row.release ? ready.get(row.release)?.answer : undefined
    if (album && album.song?.length) {
      rememberPlayed(album)
      actions.playTracks(album.song.map((song) => toQueueTrack(song, album)), 0)
      return
    }
    openRow(row)
  }

  //? what the live region says, worked out once per new view (a view is a new object per change)
  const seen = useRef<{ view: RequestsView | null; said: string; moved: string[] }>({ view: null, said: '', moved: [] })
  if (seen.current.view !== view) {
    const { said, moved } = changes(seen.current.view, view)
    seen.current = { view, said: said || seen.current.said, moved }
  }

  //? the card a keyboard was in, so focus can follow it to another heading
  const page = useRef<HTMLElement | null>(null)
  const focusedRow = useRef<string | null>(null)
  const onFocusIn = (event: FocusEvent) => {
    const card = (event.target as HTMLElement | null)?.closest?.('[data-row]') as HTMLElement | null
    focusedRow.current = card?.dataset.row ?? null
  }
  const onFocusOut = (event: FocusEvent) => {
    //? a removed card's focus goes nowhere (no relatedTarget): kept, so it can be put back
    const next = event.relatedTarget as Node | null
    if (next && !page.current?.contains(next)) focusedRow.current = null
  }
  useLayoutEffect(() => {
    const key = focusedRow.current
    if (!key || !seen.current.moved.includes(key)) return
    const active = document.activeElement
    if (active && active !== document.body) return
    const card = page.current?.querySelector<HTMLElement>(`[data-row="${CSS.escape(key)}"]`)
    card?.focus()
  })

  const cancelNow = (row: RequestRow) => {
    setAsking(null)
    if (row.jobId === null || row.cancel !== 'ready') return
    void onCancel(row.jobId).catch((caught: unknown) => console.error(`Cancel error: ${message(caught)}`))
  }

  //? the ✕: cancel, or ask first; a second tap on the ✕ asking closes the question
  const cancel = (row: RequestRow) => {
    if (row.jobId === null || row.cancel !== 'ready') return
    if (asking === row.key) setAsking(null)
    else if (readPreferences().confirmCancel) setAsking(row.key)
    else cancelNow(row)
  }

  const keep = () => setAsking(null)

  const retry = (row: RequestRow, samePeer: boolean) => {
    //? the hook keeps its own refusal for the row (retryProblems); nothing to catch here
    if (row.jobId !== null) void onRetry(row.jobId, samePeer)
  }

  const clear = () => {
    void onClear().catch((caught: unknown) => console.error(`Clear jobs error: ${message(caught)}`))
  }

  const card = (section: Section, row: RequestRow): JSX.Element => {
    const cancelling = { onCancel: cancel, asking: asking === row.key, onKeep: keep, onConfirm: cancelNow }
    if (section === 'downloading') return <DownloadingCard row={row} {...cancelling} />
    if (section === 'waiting') return <WaitingCard row={row} {...cancelling} />
    if (section === 'attention') return <AttentionCard row={row} onRetry={retry} />
    return (
      <DoneRow
        row={row}
        onOpen={openRow}
        onPlay={playRow}
        opening={opening === row.key}
        note={row.release ? notes.get(row.release) ?? null : null}
      />
    )
  }

  return (
    <section class="app-requests" ref={page} onFocusIn={onFocusIn} onFocusOut={onFocusOut}>
      <header class="pl-large-header">
        <h1 class="pl-large-title">Requests</h1>
        <button type="button" class="app-text-button app-clear-done" disabled={!view.clearable} onClick={clear}>
          Clear done
        </button>
      </header>

      <p class="app-visually-hidden" role="status" aria-live="polite" aria-atomic="true">
        {seen.current.said}
      </p>

      {error && (
        <div class="app-card app-placeholder-body" role="status">
          <p class="app-placeholder-lead">Can't get your requests from deadwax</p>
          <p class="app-placeholder-text app-error">{error}</p>
          <p class="app-placeholder-text">
            {view.empty
              ? 'It keeps asking while this tab is open.'
              : "It keeps asking while this tab is open; what's below is from the last answer."}
          </p>
        </div>
      )}

      {!trackingEnabled ? (
        <div class="app-card app-placeholder-body">
          <p class="app-placeholder-lead">Downloads aren't being kept track of</p>
          <p class="app-placeholder-text">
            deadwax can't write its database. Downloads still arrive in slskd's folder, but they can't be
            listed here or filed into your library. Check <span class="app-mono">DB_PATH</span>.
          </p>
        </div>
      ) : view.empty ? (
        !answered ? (
          <div class="pl-spinner" aria-label="Loading" />
        ) : (
          !error && (
            <div class="app-card app-placeholder-body">
              <p class="app-placeholder-lead">Nothing requested yet</p>
              <p class="app-placeholder-text">
                Albums you get show here while they download, and once they've arrived - find one in
                Search and tap Get.
              </p>
            </div>
          )
        )
      ) : (
        SECTIONS.map((section) => {
          const rows = view.sections[section]
          if (!rows.length) return null
          return (
            <section key={section} class="app-requests-section" aria-labelledby={`app-requests-${section}`}>
              <h2 id={`app-requests-${section}`} class="app-section-title">
                {SECTION_TITLES[section]}
              </h2>
              <ul class={section === 'done' ? 'app-done-list' : 'app-jobs'}>
                {rows.map((row) => (
                  <li key={row.key} data-row={row.key} tabIndex={-1}>
                    {card(section, row)}
                  </li>
                ))}
              </ul>
            </section>
          )
        })
      )}
    </section>
  )
}

const message = (caught: unknown) => (caught instanceof Error ? caught.message : String(caught))
