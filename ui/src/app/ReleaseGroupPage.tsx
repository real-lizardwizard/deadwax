import { Fragment } from 'preact'
import { useEffect, useMemo, useRef, useState } from 'preact/hooks'

import { storeState } from '../api/download'
import { addToMyLibrary } from '../api/me'
import { MusicBrainzUnavailable } from '../api/http'
import { getReleaseGroup } from '../api/musicbrainz'
import type { ReleaseGroup, ReleaseGroupResponse, StoreStateResponse } from '../api/types'
import { storeNotes } from '../lib/candidates'
import { joinDownload } from '../lib/downloadRequests'
import { isAbort, latestOnly } from '../lib/latest'
import { GET_OFF, gets } from '../lib/permissions'
import { announceAddedToLibrary, onAddedToLibrary, onAlbumsFiled } from '../lib/libraryEvents'
import { releaseUrl } from '../lib/albumProperties'
import { describeGroupOwnership, ownedForGroup, type OwnedAlbum } from '../lib/owned'
import { anyYours, groupPagePlace, heldPhrase, isYours, withStoreLine } from '../lib/whose'
import {
  anyPressingDiffers, chosenPressingId, coverAddresses, getGroup, groupMbid, holdingOf, leftOut, metaLine, pageHeader, pressingLabel, pressingsView,
  releaseGroupUrl, summaryLine, trackRows, type PageRelease, type TrackRow,
} from '../lib/pressings'
import { storeStatusFor } from '../lib/perPerson'
import { songIds, songMatcher, songPressing } from '../lib/songs'
import { creditName, currentName } from '../lib/release'
import { buildDownloadRelease } from '../lib/releasePayload'
import { soleCredit } from '../lib/artistPage'
import { ChevronLeftIcon, GetIcon } from '../player/icons'
import { ArchiveCover } from './ArchiveCover'
import { PressingPicker } from './PressingPicker'
import { keep, kept } from './pressingLists'
import type { GetRequest } from './Sources'
import { StoreState } from './StoreState'
import { useAccess } from './access'
import { useGetSettings } from './useGetSettings'
import { takeOpener } from './useSheet'
import { hasLibrary } from './useMyLibrary'
import { refreshOwned, useOwned } from './useOwned'

export { PRESSINGS_KEPT } from './pressingLists'

//? `final`: asking again can't help (the address isn't an album's) - no Try again
type Trouble = { message: string; unavailable: boolean; final?: boolean }

/** What a link that isn't a MusicBrainz album says, with nothing to try again. */
export const NOT_AN_ALBUM_LINK = "That isn't a link to an album on MusicBrainz."

/** What a screen reader hears on the song an album was opened from (2.0.0-player.53) - its row marked. */
export const SONG_WORDS = ', the song you searched for'

//? each page's tracklist heading its own id (a page stays mounted on each tab it was opened on)
let deskTables = 0

/**
 * The desktop's tracklist (2.0.0-player.19), as DesktopRequest.dc.html and DesktopRequestBonus draw
 * it: "Tracklist" with the line saying how this pressing compares, then a table - #, Title, Length -
 * and, when any pressing of the album differs from the usual tracklist, an "Against the usual
 * tracklist" column between the title and the length holding each marked track's chip and its note
 * in the board's short words ("Bonus · only on this pressing", "Other version · usually 3:58" - the
 * phone's longer ones don't fit its 190px), the row tinted as the phone's is. On every pressing then,
 * the usual one too, so choosing another moves no column. A title or a note too long for its cell
 * ends in an ellipsis, and the cell's tooltip has it whole. What it leaves out follows, as on a phone.
 */
function DeskTracklist({
  rows,
  missing,
  summary,
  against,
  titleId,
}: {
  rows: readonly TrackRow[]
  missing: readonly { title: string; length: string }[]
  summary: { text: string; differs: boolean } | null
  against: boolean
  /** its heading's id: the page's own, since a page stays mounted on each tab it was opened on */
  titleId: string
}) {
  const columns = against ? 4 : 3
  return (
    <section class="app-rg-tracks app-rg-desk" aria-labelledby={titleId}>
      <div class="app-rg-desk-head">
        <h2 id={titleId} class="app-rg-desk-title">
          Tracklist
        </h2>
        {summary && summary.text && <p class={`app-rg-summary${summary.differs ? ' is-differs' : ''}`}>{summary.text}</p>}
      </div>
      <table class={`app-rg-table${against ? ' has-against' : ''}`}>
        <thead>
          <tr>
            <th scope="col" class="app-rg-number">#</th>
            <th scope="col">Title</th>
            {against && <th scope="col">Against the usual tracklist</th>}
            <th scope="col" class="app-rg-length">Length</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((row) => (
            <Fragment key={row.key}>
              {row.heading && (
                <tr class="app-rg-table-disc">
                  <th scope="colgroup" colSpan={columns}>
                    {row.heading}
                  </th>
                </tr>
              )}
              <tr class={`app-rg-row${row.mark ? ` is-marked is-${row.mark.kind}` : ''}${row.song ? ' is-song' : ''}`}>
                <td class="app-rg-number">{row.number}</td>
                <td class="app-rg-title" title={row.title}>
                  {row.title}
                  {row.song && <span class="app-visually-hidden">{SONG_WORDS}</span>}
                </td>
                {against && (
                  <td class="app-rg-against" title={row.mark ? `${row.mark.chip} · ${row.mark.note}` : undefined}>
                    {row.mark && (
                      <>
                        <span class="app-rg-chip">{row.mark.chip}</span>
                        <span class="app-rg-note">{row.mark.brief}</span>
                      </>
                    )}
                  </td>
                )}
                <td class="app-rg-length">{row.length}</td>
              </tr>
            </Fragment>
          ))}
        </tbody>
      </table>
      {missing.length > 0 && (
        <section class="app-rg-left">
          <h2 class="app-rg-left-title">Not on this pressing</h2>
          <table class="app-rg-table">
            <tbody>
              {missing.map((track, index) => (
                <tr key={`${index}:${track.title}`} class="app-rg-row is-left">
                  <td class="app-rg-number" aria-hidden="true">–</td>
                  <td class="app-rg-title" title={track.title}>
                    {track.title}
                  </td>
                  <td class="app-rg-length">{track.length}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </section>
      )}
    </section>
  )
}

/**
 * The album you don't have (2.0.0-player.13): a MusicBrainz release group at
 * `#/<tab>/group/<rgid>?release=<mbid>`, opened like an album you do have - James: "an album you
 * don't have opens like one you do". So its header is the album page's: back, the centred cover
 * (from the Cover Art Archive - the pressing's front, else the album's), the title, the artist (a
 * link to their page since 2.0.0-player.17, when the album is credited to one artist MusicBrainz
 * knows), and "{year} · {kind} · not in your library". Where the album
 * page has Play and Shuffle, this has the Pressing dropdown, and under it (2.0.0-player.15) "Get the
 * album", the screen's ONE solid purple button, and under that what the library and the downloads
 * already have of the pressing chosen - POST /download/store_state, which searches nothing
 * ("Already in your library", "Already downloading", "You have 9 of 10 tracks", "You also have
 * another pressing"). Get downloads the CHOSEN pressing (James: the dropdown decides what Get and the
 * sources are for): it opens the Sources sheet for that pressing, built by the one payload builder
 * (lib/releasePayload.ts) from the album's group, so it sends what the main page's Find on the same
 * pressing sent. It shows once a pressing is chosen - before that there is nothing it could get.
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
 *
 * ON A DESKTOP (2.0.0-player.19), as DesktopRequest.dc.html draws it: the cover beside the title
 * (app-desktop.css), "Get the album" with the pressing dropdown inline after it, and the tracklist
 * as a table with its "Against the usual tracklist" column (DeskTracklist). Get opens the Sources
 * PANEL beside the page, which stays usable - so while the panel shows the sources of the pressing
 * shown (`sourcesPressing`, the pressing App's panel searched for this album), Get is drawn pressed and
 * a click on it closes them; and while it shows another pressing's of this album - one chosen here, or
 * the panel left open from this album's page as you went back and came to it again - the page asks App
 * to search again for the one it shows (`again`: the chips stay as set, nothing is picked for you).
 * Only the page that shows asks (`shown`): the same album open on two tabs never takes turns.
 *
 * ANOTHER PRESSING OF AN ALBUM YOU HOLD (2.0.0-player.41): the album you have links here ("Other
 * pressings", by the group its folders carry), so the deluxe beside the standard you hold can be got.
 * The pressing list marks every pressing your library holds ("In your library", by release id from
 * /library/owned - the same answer the meta line reads), and never folds one away; Get on a held one
 * goes the way it always went - the store line says "Already in your library", and the Sources sheet
 * shows that box in place of any search (the server searches nothing for it). Opened from there it
 * has no group from Search to draw its header from, so `title` - the album's name as the page that
 * opened it knew it - stands in as the title until MusicBrainz's own group arrives with the pressings.
 *
 * OPENED FROM A SONG (2.0.0-player.53, Search's songs): `song` is the song's recordings, from the address.
 * The page opens on a pressing that HAS the song - the usual one when it has it, else the most usual of
 * those that do (lib/songs.ts songPressing: the bonus-track case) - and marks it in the tracklist (tinted,
 * an accent bar, and SONG_WORDS for a screen reader), brought into view once as it is first drawn, unless
 * the page was scrolled meanwhile or came back with its scroll put back. A pressing chosen from then on is
 * written into the address whatever it is - the usual one too - so the song never overrules a choice.
 *
 * SEARCH EXTRAS (2.0.0-player.50), as the main page had them: the chosen pressing's FACTS under the
 * picker - status, full date, labels, catalogue number, barcode, as MusicBrainz gives them, one line of
 * fixed height (two on a phone) so choosing another pressing moves nothing under it - with every
 * pressing's in the dropdown, and a filter there for an album of many pressings (PressingPicker);
 * "MAYBE IN YOUR LIBRARY", dashed as the main page's card said it, when no folder holds the album by an
 * id but one with no MusicBrainz ids has its name (lib/owned.ts's name match - its folders in the
 * tooltip); and its page and the chosen pressing's on musicbrainz.org, at the foot, opening beside the
 * app.
 */
export function ReleaseGroupPage({
  id,
  release,
  song = null,
  preview,
  title = '',
  shown,
  onBack,
  backLabel,
  onPick,
  onGet,
  onArtist,
  desktop = false,
  sourcesPressing = null,
  onCloseSources,
}: {
  id: string
  release: string | null
  /** opened from a song Search found (2.0.0-player.53): its recordings, as the address carries them */
  song?: string | null
  /** the group as Search showed it, for the header before (or without) the pressings */
  preview: ReleaseGroup | null
  /** the album's name as the page that opened it knew it (2.0.0-player.41): the title until the
   *  header has one - never used for what Get downloads */
  title?: string
  /** the page is what shows - its tab current, no sheet over it, the app in front (App) */
  shown: boolean
  onBack: () => void
  backLabel: string
  /** a pressing chosen: its id, or null for the default */
  onPick: (groupId: string, releaseId: string | null) => void
  /** Get: open the Sources sheet for the chosen pressing, focus given back to `opener` as it closes */
  onGet: (request: Omit<GetRequest, 'key'>, opener: HTMLElement | null) => void
  /** the artist's page, by MusicBrainz id (2.0.0-player.17) */
  onArtist?: (artist: { mbid: string; name: string }) => void
  /** drawn in the desktop's frame (2.0.0-player.19) */
  desktop?: boolean
  /** a desktop's Sources panel is showing a Get of this album: the pressing it searched for (null:
   *  none, or another album's) */
  sourcesPressing?: string | null
  /** ...and Get, pressed while that is the pressing shown, closes it */
  onCloseSources?: () => void
}) {
  //? (2.0.0-player.61) Get albums: without it, its words in Get's place (and no join)
  const getsAlbums = gets(useAccess().permissions)
  //? the id as MusicBrainz writes it, or null for an address that isn't an album's
  const mbid = groupMbid(id)
  const [answer, setAnswer] = useState<ReleaseGroupResponse | null>(() => (mbid && kept(mbid)) || null)
  const [trouble, setTrouble] = useState<Trouble | null>(null)
  const requests = useMemo(latestOnly, [])
  //? what the library holds - asked again EVERY time the page shows (second review), as the store line under
  //? Get is: with logins on whose an album is moves outside this tab (an unstar in Amperfy read back, a Remove
  //? on another device), and an answer kept from earlier in the session said "in your library" over a fresh
  //? "In the store, not in your library". Cheap: an unchanged library is a 304
  const owned = useOwned(false)
  useEffect(() => {
    if (shown) void refreshOwned()
  }, [shown])

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
  //? the album as credited - Search's group, else the one the pressings carry - for its title and the
  //? names it could be filed under
  const credited = preview ?? releases.find((each) => each['release-group'])?.['release-group'] ?? null
  //? (2.0.0-player.53) opened from a song: the pressing asked for is the address's, else one with the song -
  //? null when the usual pressing has it, as the page would open anyway
  const songKey = songIds(song).join(',')
  const asked = useMemo(() => release ?? (songKey ? songPressing(releases, songKey.split(',')) : null), [answer, release, songKey])
  const isSong = useMemo(() => (songKey ? songMatcher(releases, songKey.split(',')) : null), [answer, songKey])
  //? what the library holds of this album: its folders by the group's id or any pressing's - null
  //? until the library has answered, and the meta line then says neither. And, held by no id, a folder
  //? with no MusicBrainz ids that has the album's name and an artist's it could be filed under - the
  //? credit, or the name they go by now - said as a MAYBE (2.0.0-player.50), as the main page's card
  //? said it: the name can't tell which album it is, let alone which pressing
  const ownership = owned ? ownedForGroup(owned.index, {
    groupId: mbid,
    releaseIds: releases.map((release) => release.id),
    title: credited?.title || releases[0]?.title || title,
    artists: [creditName(credited?.['artist-credit']), currentName(credited?.['artist-credit'])],
  }) : null
  //? (second review) ...and whose each folder is as the line under Get last said it of the pressing on screen -
  //? that line is asked as the page shows, and the two lines on screen must never disagree (lib/whose.ts)
  const [store, setStore] = useState<{ id: string; state: StoreStateResponse } | null>(null)
  const shownId = useMemo(() => chosenPressingId(releases, asked), [answer, asked])
  const said = store && store.id === shownId ? store.state : null
  const holding = ownership ? withStoreLine(ownership.held, said) : null
  const held = holding ? holding.length > 0 : null
  const maybe = holdingOf(ownership) === 'maybe' ? describeGroupOwnership(ownership!) : null
  //? (2.0.0-player.52) with logins on and a library of your own: held by the store isn't yours unless a folder
  //? of it is - the meta line says "in the store" then, as the store line under Get does (its place below)
  const personal = hasLibrary()
  //? ...and which pressings those are, by release id: each marked in the pressing list (2.0.0-player.41) -
  //? and which of them are yours (null with logins off: the store is your library)
  const releaseIds = (albums: readonly OwnedAlbum[]) =>
    [...new Set(albums.map((album) => (album.release_mbid ?? '').trim().toLowerCase()).filter(Boolean))].sort().join(' ')
  const heldKey = releaseIds(holding ?? [])
  const yoursKey = personal ? releaseIds((holding ?? []).filter(isYours)) : null
  const heldIds = useMemo(() => new Set(heldKey ? heldKey.split(' ') : []), [heldKey])
  const yoursIds = useMemo(() => (yoursKey === null ? null : new Set(yoursKey ? yoursKey.split(' ') : [])), [yoursKey])
  const view = useMemo(() => (releases.length ? pressingsView(releases, asked, heldIds, yoursIds) : null), [answer, asked, heldIds, yoursIds])
  const chosen = releases.find((candidate) => candidate.id === view?.chosenId) ?? null
  //? ...and with a pressing of it yours but the one on screen the store's, "another pressing in your library":
  //? never "in your library" over a store line saying "In the store, not in your library" (review)
  const place = groupPagePlace(personal, holding ?? [], view?.chosenId)
  const header = pageHeader(releases, chosen, preview)
  const diff = view && chosen ? view.diffs.get(chosen.id) ?? null : null
  const rows = trackRows(chosen, diff, isSong)
  const missing = leftOut(diff)
  const summary = view ? summaryLine(view, releases.length) : null
  //? the artist, a link to their page when the album is credited to ONE artist MusicBrainz knows
  const artistLink = onArtist ? soleCredit(credited?.['artist-credit']?.length ? credited['artist-credit'] : chosen?.['artist-credit']) : null

  //? What Get would download: the chosen pressing, as the one payload builder makes it from the
  //? album's group - and what the library and the downloads already have of it, asked of the store
  //? (no Soulseek search) as the pressing is chosen, as an album is filed, and as the page shows again
  const group = mbid && chosen ? getGroup(mbid, preview, releases, chosen) : null
  //? the chosen pressing as MusicBrainz sent it (the page reads it through tracklistDiff's types)
  const pressing = answer?.releases.find((release) => release.id === chosen?.id) ?? null
  const download = group && pressing ? buildDownloadRelease(group, pressing) : null
  const stateRequests = useMemo(latestOnly, [])
  const [filed, setFiled] = useState(0)
  useEffect(() => onAlbumsFiled(() => setFiled((n) => n + 1)), [])
  //? (2.0.0-player.51) added to your library - from this page's line, or the Sources panel's beside it: the
  //? store asked again, so the line says "Already in your library"
  useEffect(() => onAddedToLibrary(() => setFiled((n) => n + 1)), [])
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
  //? the store's answer for the pressing on screen (`said`, above: chosen and shownId are the same pressing)
  const known = said
  //? (2.0.0-player.49) a download somebody else asked for: judged against your quality floor, and
  //? joined from the line - which then asks the store again, and says it's yours
  const { settings } = useGetSettings(shown)
  const floor = settings?.quality_floor ?? null
  const join = (jobId: number) => joinDownload(jobId).then(() => setFiled((n) => n + 1))
  //? (2.0.0-player.51) a pressing the store holds that isn't yours, added from the line - which then asks
  //? the store again (onAddedToLibrary, above), and says it's in your library
  const add = () => (download ? addToMyLibrary(download.release).then(announceAddedToLibrary) : Promise.reject(new Error('Choose a pressing first.')))

  //? a desktop's Sources panel shows the sources of the pressing on screen: Get is drawn pressed
  const sourcesHere = sourcesPressing !== null && sourcesPressing === chosen?.id

  const get = (event: MouseEvent) => {
    //? a desktop's Get, pressed while the panel shows this pressing's sources: a toggle - it closes them
    if (sourcesHere) {
      onCloseSources?.()
      return
    }
    if (!download || !chosen) return
    onGet({ release: download.release, subtitle: [header.title, pressingLabel(chosen)].filter(Boolean).join(' · '), from: id }, takeOpener(event))
  }

  //? A DESKTOP's Sources panel follows the pressing (2.0.0-player.19): the page stays usable beside
  //? it, so while it shows another pressing's sources of this album - one chosen here, or the panel
  //? left open as you went back and came to this album again - the page shown searches for its own in
  //? turn: `again`, the chips as set and nothing picked, focus still going back to Get as the panel
  //? closes. Only the page that shows (`shown`), so the album open on two tabs never takes turns.
  const getButton = useRef<HTMLButtonElement>(null)
  const tableTitle = useMemo(() => `app-rg-desk-title-${++deskTables}`, [])
  useEffect(() => {
    if (!shown || sourcesPressing === null || !download || !chosen || sourcesPressing === chosen.id) return
    onGet(
      { release: download.release, subtitle: [header.title, pressingLabel(chosen)].filter(Boolean).join(' · '), from: id, again: true },
      getButton.current,
    )
  }, [shown, sourcesPressing, chosen?.id])

  //? a pick on a page opened from a song is written into the address even when it is the usual pressing, so the
  //? song's own choice never comes back over it (2.0.0-player.53)
  const picker = view && <PressingPicker view={view} onPick={(picked) => onPick(id, songKey || picked !== view.defaultId ? picked : null)} />

  //? (2.0.0-player.53) the song brought into view as it is first drawn - once for the page, only while it shows
  //? (a page on another tab mustn't scroll this one), and only from the top: a page scrolled meanwhile, or come
  //? back to with its scroll put back, is left where it is. `nearest` leaves a row already in view still
  const page = useRef<HTMLElement>(null)
  const songShown = useRef(false)
  useEffect(() => {
    if (songShown.current || !shown || !rows.some((row) => row.song)) return
    const row = page.current?.querySelector<HTMLElement>('.is-song')
    if (!row) return
    songShown.current = true
    if (typeof window === 'undefined' || window.scrollY > 0) return
    row.scrollIntoView({ block: 'nearest' })
  }, [rows, shown])
  //? the chosen pressing's facts (2.0.0-player.50): status, full date, labels, catalogue number,
  //? barcode, as MusicBrainz gives them - drawn with the picker, one fixed height (app.css), so another
  //? pressing chosen moves nothing under it; the whole of it in its tooltip, and in the list's rows
  const chosenRow = view ? [...view.shown, ...view.more].find((row) => row.id === view.chosenId) ?? null : null
  const facts = view && (
    <p class="app-rg-facts" title={chosenRow?.facts || undefined}>
      {chosenRow?.facts ?? ''}
    </p>
  )

  return (
    <section ref={page} class="pl-album-page app-rg">
      <header class="pl-nav-bar">
        <button type="button" class="pl-back" onClick={onBack}>
          <ChevronLeftIcon class="pl-back-icon" />
          <span class="pl-back-label">{backLabel}</span>
        </button>
      </header>

      <div class="pl-album-hero">
        <ArchiveCover addresses={mbid ? coverAddresses(chosen?.id ?? release, mbid) : []} class="pl-hero-cover" />
        <h1 class="pl-hero-title">{header.title || title}</h1>
        {artistLink ? (
          <button type="button" class="pl-hero-artist app-hero-link" onClick={() => onArtist?.(artistLink)}>
            {header.artist}
          </button>
        ) : (
          <p class="pl-hero-artist app-hero-plain">{header.artist}</p>
        )}
        {/* said once something is known - a cold link has nothing to say until the pressings come; a
            folder of this name with no ids is a dashed "maybe", its folders in the tooltip */}
        <p class="pl-hero-meta">
          {!(preview || answer) ? '' : maybe ? (
            <>
              {metaLine(header, null)}
              {metaLine(header, null) ? ' · ' : ''}
              <span class="app-rg-maybe" title={maybe.title}>
                maybe {heldPhrase(personal, anyYours(ownership?.guessed ?? []))}
              </span>
            </>
          ) : metaLine(header, held, place)}
        </p>

        {/* where the album page has Play and Shuffle: the pressing, Get, and what's already here of
            it - under Get, where an answer landing late moves nothing a finger is reaching for */}
        <div class="app-rg-actions">
          {!desktop && picker}
          {!desktop && facts}
          {download && getsAlbums && (
            //? a desktop's Get says whether the panel shows its sources: pressed, a click closes them
            <button ref={getButton} type="button" class="app-rg-get" onClick={get} {...(desktop ? { 'aria-pressed': sourcesHere } : {})}>
              <GetIcon class="app-rg-get-icon" />
              Get the album
            </button>
          )}
          {download && !getsAlbums && <p class="app-footnote app-get-off">{GET_OFF}</p>}
          {/* a desktop's pressing dropdown sits inline after Get, as its board has it - its facts under both */}
          {desktop && picker}
          {desktop && facts}
          <div class="app-rg-store" aria-live="polite">
            {known && <StoreState status={storeStatusFor(known, 'Requests', floor)} notes={storeNotes(known)} {...(getsAlbums ? { onJoin: join } : {})} onAdd={add} />}
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
      ) : desktop ? (
        <DeskTracklist
          rows={rows}
          missing={missing}
          summary={summary}
          against={anyPressingDiffers(view) || rows.some((row) => row.mark)}
          titleId={tableTitle}
        />
      ) : (
        <section class="app-rg-tracks" aria-label="Tracklist">
          {summary && summary.text && (
            <p class={`app-rg-summary${summary.differs ? ' is-differs' : ''}`}>{summary.text}</p>
          )}
          <ol class="app-rg-list">
            {rows.map((row) => (
              <Fragment key={row.key}>
                {row.heading && <li class="app-rg-disc">{row.heading}</li>}
                <li class={`app-rg-track${row.mark ? ` is-marked is-${row.mark.kind}` : ''}${row.song ? ' is-song' : ''}`}>
                  <span class="app-rg-number">{row.number}</span>
                  <span class="app-rg-text">
                    <span class="app-rg-title">
                      {row.title}
                      {row.song && <span class="app-visually-hidden">{SONG_WORDS}</span>}
                    </span>
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

      {/* on musicbrainz.org (2.0.0-player.50), opening beside the app - following a link in the page
          would unload the player: the album, and the pressing chosen */}
      {mbid && (
        <p class="app-rg-links">
          <span class="app-rg-links-label">On MusicBrainz</span>
          <a class="app-rg-link" href={releaseGroupUrl(mbid)} target="_blank" rel="noopener">
            The album ↗
          </a>
          {chosen && (
            <a class="app-rg-link" href={releaseUrl(chosen.id)} target="_blank" rel="noopener">
              This pressing ↗
            </a>
          )}
        </p>
      )}
    </section>
  )
}
