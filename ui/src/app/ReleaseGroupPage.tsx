import { Fragment } from 'preact'
import { useEffect, useMemo, useState } from 'preact/hooks'

import { storeState } from '../api/download'
import { MusicBrainzUnavailable } from '../api/http'
import { getReleaseGroup } from '../api/musicbrainz'
import type { ReleaseGroup, ReleaseGroupResponse, StoreStateResponse } from '../api/types'
import { storeNotes, storeStatus } from '../lib/candidates'
import { isAbort, latestOnly } from '../lib/latest'
import { onAlbumsFiled } from '../lib/libraryEvents'
import { ownedForGroup } from '../lib/owned'
import {
  coverAddresses, getGroup, groupMbid, leftOut, metaLine, pageHeader, pressingLabel, pressingsView, summaryLine, trackRows,
  type PageRelease,
} from '../lib/pressings'
import { buildDownloadRelease } from '../lib/releasePayload'
import { ChevronLeftIcon, GetIcon } from '../player/icons'
import { ArchiveCover } from './ArchiveCover'
import { PressingPicker } from './PressingPicker'
import { keep, kept } from './pressingLists'
import type { GetRequest } from './Sources'
import { StoreState } from './StoreState'
import { takeOpener } from './useSheet'
import { useOwned } from './useOwned'

export { PRESSINGS_KEPT } from './pressingLists'

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
 * page has Play and Shuffle, this has the Pressing dropdown, and under it (2.0.0-player.15) "Get the
 * album", the screen's ONE solid purple button, and under that what the library and the downloads
 * already have of the pressing chosen - POST /download/store_state, which searches nothing
 * ("Already in your library", "Already downloading", "You have 9 of 10 tracks", "You also have
 * another pressing"). Get downloads the CHOSEN pressing (James: the dropdown decides what Get and the
 * sources are for): it opens the Sources sheet for that pressing, built by the one payload builder
 * (lib/releasePayload.ts) from the album's group, so the main page's Find on the same pressing sends
 * the same. It shows once a pressing is chosen - before that there is nothing it could get.
 *
 * What is already here sits UNDER Get, not between the pressing and it (review): its answer lands
 * after Get is drawn, and is a few lines tall, so above Get it moved the button under a finger
 * reaching for it. It is asked for the pressing chosen, again as another is chosen, as an album is
 * filed, and as the page comes back into view (`shown`: its tab current, the Sources sheet closed,
 * the app in front - so after a Get, or a download cancelled in Requests, it says so). Asked again
 * for the SAME pressing, the last answer stays until the new one lands; another pressing's never
 * stands for this one.
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
  shown,
  onBack,
  backLabel,
  onPick,
  onGet,
}: {
  id: string
  release: string | null
  /** the group as Search showed it, for the header before (or without) the pressings */
  preview: ReleaseGroup | null
  /** the page is what shows - its tab current, no sheet over it, the app in front (App) */
  shown: boolean
  onBack: () => void
  backLabel: string
  /** a pressing chosen: its id, or null for the default */
  onPick: (groupId: string, releaseId: string | null) => void
  /** Get: open the Sources sheet for the chosen pressing, focus given back to `opener` as it closes */
  onGet: (request: Omit<GetRequest, 'key'>, opener: HTMLElement | null) => void
}) {
  //? the id as MusicBrainz writes it, or null for an address that isn't an album's
  const mbid = groupMbid(id)
  const [answer, setAnswer] = useState<ReleaseGroupResponse | null>(() => (mbid && kept(mbid)) || null)
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
    const held = kept(mbid)
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

  //? What Get would download: the chosen pressing, as the one payload builder makes it from the
  //? album's group - and what the library and the downloads already have of it, asked of the store
  //? (no Soulseek search) as the pressing is chosen, as an album is filed, and as the page shows again
  const group = mbid && chosen ? getGroup(mbid, preview, releases, chosen) : null
  //? the chosen pressing as MusicBrainz sent it (the page reads it through tracklistDiff's types)
  const pressing = answer?.releases.find((release) => release.id === chosen?.id) ?? null
  const download = group && pressing ? buildDownloadRelease(group, pressing) : null
  const stateRequests = useMemo(latestOnly, [])
  const [store, setStore] = useState<{ id: string; state: StoreStateResponse } | null>(null)
  const [filed, setFiled] = useState(0)
  useEffect(() => onAlbumsFiled(() => setFiled((n) => n + 1)), [])
  useEffect(() => {
    if (!download || !chosen) {
      stateRequests.supersede()
      return
    }
    //? out of view (another tab, the sheet over it, the app in the background): asked as it comes back
    if (!shown) return
    const request = stateRequests.begin()
    //? the last answer stays while this pressing is asked about again - it is still the best known,
    //? and clearing it would empty the line for a moment; another pressing's is never drawn (`known`)
    const asked = chosen.id
    storeState(download.release, request.signal).then(
      (state) => {
        if (request.current()) setStore({ id: asked, state })
      },
      () => {
        //? a check that can't be made says nothing - Get asks again, and the server refuses a second copy
      },
    )
    return () => stateRequests.supersede()
  }, [chosen?.id, group?.id, filed, shown])
  const known = store && store.id === chosen?.id ? store.state : null

  const get = (event: MouseEvent) => {
    if (!download || !chosen) return
    onGet({ release: download.release, subtitle: [header.title, pressingLabel(chosen)].filter(Boolean).join(' · ') }, takeOpener(event))
  }

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

        {/* where the album page has Play and Shuffle: the pressing, Get, and what's already here of
            it - under Get, where an answer landing late moves nothing a finger is reaching for */}
        <div class="app-rg-actions">
          {view && <PressingPicker view={view} onPick={(picked) => onPick(id, picked === view.defaultId ? null : picked)} />}
          {download && (
            <button type="button" class="app-rg-get" onClick={get}>
              <GetIcon class="app-rg-get-icon" />
              Get the album
            </button>
          )}
          <div class="app-rg-store" aria-live="polite">
            {known && <StoreState status={storeStatus(known, 'Requests')} notes={storeNotes(known)} />}
          </div>
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
