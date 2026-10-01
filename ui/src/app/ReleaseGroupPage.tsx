import { Fragment } from 'preact'
import { useEffect, useMemo, useState } from 'preact/hooks'

import { MusicBrainzUnavailable } from '../api/http'
import { getReleaseGroup } from '../api/musicbrainz'
import type { ReleaseGroup, ReleaseGroupResponse } from '../api/types'
import { isAbort, latestOnly } from '../lib/latest'
import { ownedForGroup } from '../lib/owned'
import {
  coverAddresses, groupMbid, leftOut, metaLine, pageHeader, pressingsView, summaryLine, trackRows, type PageRelease,
} from '../lib/pressings'
import { ChevronLeftIcon } from '../player/icons'
import { ArchiveCover } from './ArchiveCover'
import { PressingPicker } from './PressingPicker'
import { useOwned } from './useOwned'

/** How many albums' pressing lists the session keeps, so Back (and a tab switch) asks nothing again. */
export const PRESSINGS_KEPT = 20

//? the session's pressing lists, by release group - only complete answers, never a failure, and
//? the oldest let go past PRESSINGS_KEPT (a big group's tracklists are a large payload)
const pressings = new Map<string, ReleaseGroupResponse>()

function keep(id: string, answer: ReleaseGroupResponse): void {
  pressings.delete(id)
  pressings.set(id, answer)
  if (pressings.size > PRESSINGS_KEPT) {
    const [oldest] = pressings.keys()
    if (oldest !== undefined) pressings.delete(oldest)
  }
}

//? `final`: asking again can't help (the address isn't an album's) - no Try again
type Trouble = { message: string; unavailable: boolean; final?: boolean }

/** What a link that isn't a MusicBrainz album says, with nothing to try again. */
export const NOT_AN_ALBUM_LINK = "That isn't a link to an album on MusicBrainz."

/**
 * The album you don't have (2.0.0-player.13): a MusicBrainz release group at
 * `#/<tab>/group/<rgid>?release=<mbid>`, opened like an album you do have - James: "an album you
 * don't have opens like one you do". So its header is the album page's: back, the centred cover
 * (from the Cover Art Archive - the pressing's front, else the album's), the title, the artist (not
 * a link: there is no artist page yet), and "{year} · {kind} · not in your library". Where the album
 * page has Play and Shuffle, this has the Pressing dropdown; "Get the album" goes under it in the next
 * slice, and nothing stands in its place meanwhile - a button that does nothing is worse than none.
 *
 * Then the chosen pressing's TRACKLIST, not the release list (James: "for both, I'd like the album
 * page to show the tracklist instead of the release list ... a dropdown somewhere to pick which
 * release you're viewing, with the most common as default"), with what it changes about the usual
 * tracklist marked: a Bonus row, another version, a rename, and what it leaves out - lib/pressings.ts
 * over the port of the main page's own rules (lib/tracklistDiff.ts).
 *
 * Every pressing's tracklist is fetched (`/search_musicbrainz/release_group`) - the base and the
 * differences need them all - through latestOnly(), and kept for the session, so Back costs
 * nothing. MusicBrainz going away (often) is a problem with Try again, never a short list passing
 * for the album's pressings. Works with Navidrome unset or down: nothing here is Navidrome's.
 *
 * The pressing shown is the address's (`release`), else the default; a pick is the page's own
 * address replaced (App, router.update), so a reload or a link shows the same pressing.
 *
 * "in your library" / "not in your library" is said only once the library has answered (useOwned:
 * null until then), and is judged by the group's id AND every pressing's - so a folder tagged with
 * a release id alone (an m4a deadwax filed: Easy MP4 has no group-id key) still counts, as the main
 * page's card counts it (registerGroupReleases). The id in the address is lowercased and checked
 * first: anything else is said to be no album link, with no Try again that could never work.
 */
export function ReleaseGroupPage({
  id,
  release,
  preview,
  onBack,
  backLabel,
  onPick,
}: {
  id: string
  release: string | null
  /** the group as Search showed it, for the header before (or without) the pressings */
  preview: ReleaseGroup | null
  onBack: () => void
  backLabel: string
  /** a pressing chosen: its id, or null for the default */
  onPick: (groupId: string, releaseId: string | null) => void
}) {
  //? the id as MusicBrainz writes it, or null for an address that isn't an album's
  const mbid = groupMbid(id)
  const [answer, setAnswer] = useState<ReleaseGroupResponse | null>(() => (mbid && pressings.get(mbid)) || null)
  const [trouble, setTrouble] = useState<Trouble | null>(null)
  const requests = useMemo(latestOnly, [])
  const owned = useOwned(true)

  function load() {
    if (!mbid) {
      requests.supersede()
      setAnswer(null)
      setTrouble({ message: NOT_AN_ALBUM_LINK, unavailable: false, final: true })
      return
    }
    const held = pressings.get(mbid)
    if (held) {
      setAnswer(held)
      setTrouble(null)
      return
    }
    const request = requests.begin()
    setAnswer(null)
    setTrouble(null)
    getReleaseGroup(mbid, request.signal).then(
      (found) => {
        if (!request.current()) return
        //? a list MusicBrainz broke off is not the album's pressings
        if (found.problem) {
          setTrouble({ message: found.problem, unavailable: true })
          return
        }
        keep(mbid, found)
        setAnswer(found)
      },
      (reason: unknown) => {
        if (!request.current() || isAbort(reason)) return
        setTrouble({ message: reason instanceof Error ? reason.message : String(reason), unavailable: reason instanceof MusicBrainzUnavailable })
      },
    )
  }

  useEffect(() => {
    load()
    return () => requests.supersede()
  }, [mbid, requests])

  const releases = (answer?.releases ?? []) as PageRelease[]
  const view = useMemo(() => (releases.length ? pressingsView(releases, release) : null), [answer, release])
  const chosen = releases.find((candidate) => candidate.id === view?.chosenId) ?? null
  const header = pageHeader(releases, chosen, preview)
  //? null until the library has answered: the meta line then says neither
  const held = owned ? ownedForGroup(owned.index, { groupId: mbid, releaseIds: releases.map((release) => release.id) }).held.length > 0 : null
  const diff = view && chosen ? view.diffs.get(chosen.id) ?? null : null
  const rows = trackRows(chosen, diff)
  const missing = leftOut(diff)
  const summary = view ? summaryLine(view, releases.length) : null

  return (
    <section class="pl-album-page app-rg">
      <header class="pl-nav-bar">
        <button type="button" class="pl-back" onClick={onBack}>
          <ChevronLeftIcon class="pl-back-icon" />
          <span class="pl-back-label">{backLabel}</span>
        </button>
      </header>

      <div class="pl-album-hero">
        <ArchiveCover addresses={mbid ? coverAddresses(chosen?.id ?? release, mbid) : []} class="pl-hero-cover" />
        <h1 class="pl-hero-title">{header.title}</h1>
        <p class="pl-hero-artist">{header.artist}</p>
        {/* said once something is known - a cold link has nothing to say until the pressings come */}
        <p class="pl-hero-meta">{preview || answer ? metaLine(header, held) : ''}</p>

        {/* where the album page has Play and Shuffle: the pressing, and (from the next slice) Get */}
        <div class="app-rg-actions">
          {view && <PressingPicker view={view} onPick={(picked) => onPick(id, picked === view.defaultId ? null : picked)} />}
        </div>
      </div>

      {trouble ? (
        <div class="pl-notice app-rg-trouble">
          <p>
            {trouble.unavailable
              ? "MusicBrainz isn't answering just now, so this album's pressings couldn't be loaded - it often goes away for a few minutes."
              : trouble.message}
          </p>
          {!trouble.final && (
            <button type="button" class="app-button" onClick={load}>
              Try again
            </button>
          )}
        </div>
      ) : !answer ? (
        <div class="app-asking app-rg-asking" role="status">
          <span class="app-sweep" aria-hidden="true" />
          <span class="app-asking-text">Asking MusicBrainz…</span>
        </div>
      ) : !releases.length ? (
        <p class="pl-notice">MusicBrainz lists no pressings of this album.</p>
      ) : (
        <section class="app-rg-tracks" aria-label="Tracklist">
          {summary && summary.text && (
            <p class={`app-rg-summary${summary.differs ? ' is-differs' : ''}`}>{summary.text}</p>
          )}
          <ol class="app-rg-list">
            {rows.map((row) => (
              <Fragment key={row.key}>
                {row.heading && <li class="app-rg-disc">{row.heading}</li>}
                <li class={`app-rg-track${row.mark ? ` is-marked is-${row.mark.kind}` : ''}`}>
                  <span class="app-rg-number">{row.number}</span>
                  <span class="app-rg-text">
                    <span class="app-rg-title">{row.title}</span>
                    {row.mark && <span class="app-rg-note">{row.mark.note}</span>}
                  </span>
                  {row.mark && <span class="app-rg-chip">{row.mark.chip}</span>}
                  <span class="app-rg-length">{row.length}</span>
                </li>
              </Fragment>
            ))}
          </ol>
          {missing.length > 0 && (
            <section class="app-rg-left">
              <h2 class="app-rg-left-title">Not on this pressing</h2>
              <ul class="app-rg-list">
                {missing.map((track, index) => (
                  <li key={`${index}:${track.title}`} class="app-rg-track is-left">
                    <span class="app-rg-number" aria-hidden="true">–</span>
                    <span class="app-rg-text">
                      <span class="app-rg-title">{track.title}</span>
                    </span>
                    <span class="app-rg-length">{track.length}</span>
                  </li>
                ))}
              </ul>
            </section>
          )}
        </section>
      )}
    </section>
  )
}
