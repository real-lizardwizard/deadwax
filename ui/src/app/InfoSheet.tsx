import { useEffect, useLayoutEffect, useRef, useState } from 'preact/hooks'

import { aboutRows, type About, type AboutAlbumFields, type AboutDetails } from '../lib/aboutRows'
import type { LevelAnswer } from '../lib/loudness'
import { panelIsModal, type PanelStyle } from '../lib/appFrame'
import type { DeckReport } from '../lib/deckVoice'
import { debugSections, infoTabs, playingRows, shownTab, PLAYING_TITLE, type DebugRow, type DebugSection, type InfoTab, type RecordingState } from '../lib/debugRows'
import type { QueueTrack } from '../lib/playQueue'
import { Cover } from '../player/Cover'
import { ChevronRightIcon } from '../player/icons'
import type { Player } from '../player/usePlayer'
import { hasLibrary } from './useMyLibrary'
import { useSheet } from './useSheet'

/** How often an open Debug reads the speed again (2.0.0-player.39): the song's measured pace moves as it
 *  plays, and none of the speed is React state. */
export const SPEED_READ_MS = 1000

/** What the sheet last drew, kept so it slides away still showing it. */
interface Drawn {
  about: About | null
  /** (2.0.0-player.63) About's Playing group */
  playing: DebugRow[] | null
  debug: DebugSection[] | null
}

/**
 * Info: a sheet over Now Playing, opened from its ••• menu (2.0.0-player.10), with two tabs.
 *
 * - ABOUT: the song, its album and its artist, from what the app already has (lib/aboutRows.ts) -
 *   the queue's copy of the song and the album answer it was played from - and, since
 *   2.0.0-player.17, what App asks for as Info opens (`details`, app/useInfoDetails.ts): the play
 *   count, the writers, the label, "This pressing" and the folder, and who the artist is. A field
 *   Navidrome didn't send is left out, never invented. The album's card goes to the album, like "Go
 *   to album", and the artist's to their page. The folder is a row of its own at the end ("In your
 *   library"), outside every link: a path is the one thing here people copy (review).
 * - DEBUG: what used to be two lines on the now-playing screen - how the song was sent, how the
 *   last song changes and the last seek went - as labelled rows (lib/debugRows.ts), the turntable's
 *   own sound (2.0.0-player.14: ready, or off and why), and the names of the fields Navidrome sent
 *   for the song and its album, to read off a phone.
 *
 * DEBUG IS AN ADMIN'S (2.0.0-player.63, James: "only make the debug info available to an admin"): `admin` is
 * /deadwax/me's (app/access.ts) - a Navidrome admin, break-glass, or everyone with logins off. Everyone else's
 * Info is About alone, with no tab strip (lib/debugRows.ts infoTabs), and About ends, before the folder, with
 * a "Playing" group of the three of Debug's rows a listener can use - Format, Gapless and Normalization - built
 * by Debug's own functions (playingRows). The role going while Debug shows draws About (shownTab).
 *
 * A sheet like the others (useSheet.ts): its own scroll lock, focus in to Done and back to the •••
 * button, Escape, a tap on the backdrop above it; inert while closed. Its body is the one part of
 * the player's sheets that SCROLLS, so it says so itself (`touch-action: pan-y` in app.css): the
 * layer it sits in takes every touch, as Now Playing does, so that nothing on it pans the page
 * behind - and a scroller starts its own count, so its own panning comes back inside it.
 *
 * The rows are worked out only while it is open, and what it last drew is kept while it slides
 * away. The Speed row (2.0.0-player.39) reads what isn't React state - the speed and the song's measured
 * pace - so while Debug shows, it is read again as the speed changes (on a desktop the player bar's chip
 * is beside the panel) and every SPEED_READ_MS (the pace comes after a couple of seconds of playing, and
 * moves), and drawn again only when what it says has changed. `sentFormat` is asked only while Info is open,
 * for Debug and for About's Normalization row: it puts a question to the player's audio element.
 * It stays mounted, and a closed sheet is only hidden, so its one scroller would keep its offset
 * from one opening to the next and from one tab to the other: it is put back at the top as Info
 * opens and as the tab changes - never as it closes, while it is still sliding away in sight.
 *
 * ON A DESKTOP (2.0.0-player.19) it is the side panel, opened from the player bar's Info - a third
 * column from 1280px, a drawer over the page's edge below that (lib/appFrame.ts's panel rule) - and
 * not modal: no backdrop, no scroll lock, the page beside it still usable, and Escape closing it only
 * from inside it (its box takes focus from a click on anything in it that can't). The desktop has no
 * Now Playing sheet for it to sit over; Done closes it, and focus goes back to the bar's Info button.
 *
 * A leaf: props only, so the sim renders it alone.
 */
export function InfoSheet({
  open,
  opener,
  onClose,
  onAlbum,
  player,
  album,
  sentFormat,
  admin,
  turntable = null,
  recording = null,
  onRecord = null,
  details = null,
  level = null,
  onArtist = null,
  panel = 'sheet',
  covered = false,
}: {
  open: boolean
  opener?: { current: HTMLElement | null } | undefined
  onClose: () => void
  /** close everything and open the song's album; null when it names none to go to */
  onAlbum: (() => void) | null
  /** the speed's reading too, and a way to hear of it changing, where the player has one
   *  (2.0.0-player.39 - the app's always does) */
  player: Pick<Player, 'track' | 'gapless' | 'maxRate' | 'gaps' | 'lastSeek' | 'wrapped'> & Partial<Pick<Player, 'speedReading' | 'onSpeed'>>
  /** the album answer the queue was played from, as Navidrome sent it; null when not in hand */
  album: AboutAlbumFields | null
  sentFormat: (track: QueueTrack) => 'raw' | 'mp3' | null
  /** (2.0.0-player.63) /deadwax/me's `admin` (app/access.ts): Debug is drawn only for an admin */
  admin: boolean
  /** the turntable's sound (2.0.0-player.14), for Debug's "Turntable sound": null while none shows */
  turntable?: DeckReport | null
  /** a recording of it, running or made, and what starts one (2.0.0-player.32) */
  recording?: RecordingState | null
  onRecord?: (() => void) | null
  /** what App asked for as Info opened (2.0.0-player.17): null until it answers */
  details?: AboutDetails | null
  /** (2.0.0-player.62) what deadwax says of the song's level, for Debug's Normalization row (App asks,
   *  useLevelAnswer): null until it answers, and for a song asked for no level */
  level?: LevelAnswer | null
  /** close everything and open the artist's page, by Navidrome's id for them; null for none */
  onArtist?: ((artist: { id: string; name: string }) => void) | null
  /** how it is drawn: a sheet over Now Playing (a phone), or a desktop's side panel */
  panel?: PanelStyle
  /** something over the whole screen - the desktop's visualizer (2.0.0-player.20): a panel left open
   *  under it is inert, and out of what a screen reader can reach, until it goes */
  covered?: boolean
}) {
  const modal = panelIsModal(panel)
  const done = useRef<HTMLButtonElement>(null)
  const scroller = useRef<HTMLDivElement>(null)
  const box = useRef<HTMLDivElement>(null)
  const [picked, setTab] = useState<InfoTab>('about')
  //? (2.0.0-player.63) the tabs this person has, and the one shown: About once the admin role goes
  const tabs = infoTabs(admin)
  const tab = shownTab(picked, admin)
  const drawn = useRef<Drawn>({ about: null, playing: null, debug: null })
  useSheet({ open, covered, onClose, lockClass: 'app-info-open', first: done, opener, modal, area: box })

  //? ...and forgotten: the role coming back opens on About, never on a Debug chosen before it went
  useEffect(() => {
    if (picked !== tab) setTab(tab)
  }, [picked, tab])

  //? (review of 2.0.0-player.63) the strip going while it has focus - the role taken away with a tab focused - would
  //? drop focus to <body>, outside the sheet (and, on a desktop's panel, out of reach of its Escape): seen here, in
  //? the render that removes it, while it is still in the page, and given to the list once it has gone
  const strip = useRef<HTMLDivElement>(null)
  const refocus = useRef(false)
  if (tabs.length < 2 && strip.current?.contains(document.activeElement)) refocus.current = true
  useLayoutEffect(() => {
    if (!refocus.current) return
    refocus.current = false
    scroller.current?.focus({ preventScroll: true })
  }, [tabs.length])

  //? the list from its top, whichever song and tab it opens on - Format and Sent as, not the end
  useLayoutEffect(() => {
    if (open && scroller.current) scroller.current.scrollTop = 0
  }, [open, tab])

  //? the Speed row, kept current while Debug shows (review of 2.0.0-player.39: it read 1.50x beside a
  //? song the bar's chip had put back to 1x): read again as the speed changes and every SPEED_READ_MS,
  //? drawn again only when what it says changed - the measured pace to the hundredth, as the row says it
  const [, setSpeedSeen] = useState('')
  const { speedReading, onSpeed } = player
  useEffect(() => {
    if (!open || tab !== 'debug' || !speedReading) return undefined
    const look = () => {
      const reading = speedReading()
      setSpeedSeen(JSON.stringify({ ...reading, measured: reading.measured === null ? null : Math.round(reading.measured * 100) }))
    }
    const off = onSpeed?.(look)
    const timer = setInterval(look, SPEED_READ_MS)
    return () => {
      off?.()
      clearInterval(timer)
    }
  }, [open, tab, speedReading, onSpeed])

  const track = player.track
  if (open && track) {
    if (tab === 'about') {
      drawn.current = {
        about: aboutRows(track, album, details, hasLibrary()),
        playing: playingRows({ track, wrapped: player.wrapped, gapless: player.gapless, format: sentFormat(track), level }),
        debug: null,
      }
    } else {
      const answer = album as Readonly<Record<string, unknown>> | null
      const song = album?.song?.find((candidate) => candidate.id === track.id) ?? null
      drawn.current = {
        about: null,
        playing: null,
        debug: debugSections({
          track,
          gapless: player.gapless,
          maxRate: player.maxRate,
          gaps: player.gaps,
          lastSeek: player.lastSeek,
          wrapped: player.wrapped,
          format: sentFormat(track),
          song: song as Readonly<Record<string, unknown>> | null,
          album: answer,
          turntable,
          recording,
          onRecord,
          speed: player.speedReading?.() ?? null,
          level,
        }),
      }
    }
  }
  const { about, playing, debug } = drawn.current

  //? a tab list's keys: the arrows move the choice, and the focus with it, between the two
  const onTabKeyDown = (event: KeyboardEvent) => {
    const step = event.key === 'ArrowRight' ? 1 : event.key === 'ArrowLeft' ? -1 : 0
    if (!step) return
    event.preventDefault()
    const at = tabs.findIndex((entry) => entry.id === tab)
    const other = tabs[(at + step + tabs.length) % tabs.length]!
    setTab(other.id)
    ;(event.currentTarget as HTMLElement).querySelector<HTMLElement>(`[data-tab="${other.id}"]`)?.focus()
  }

  return (
    <div class={`app-layer app-info-layer${open ? ' is-open' : ''}${modal ? '' : ` is-panel is-${panel}`}`} aria-hidden={!open || covered} inert={!open || covered}>
      <div class="app-backdrop" onClick={onClose} />
      {/* a panel's box takes focus from a click on anything in it that can't (its heading, and in
          Safari a tab), so Escape there is still from inside it */}
      <div ref={box} class="app-info" role="dialog" aria-modal={modal ? 'true' : 'false'} aria-labelledby="app-info-title" tabIndex={modal ? undefined : -1}>
        <header class="app-info-head">
          <h2 id="app-info-title" class="app-info-title">
            Info
          </h2>
          <button ref={done} type="button" class="app-info-done" onClick={onClose}>
            Done
          </button>
        </header>

        {/* (2.0.0-player.63) a strip only where there is a choice: an admin's About and Debug */}
        {tabs.length > 1 && (
          <div ref={strip} class="app-segmented" role="tablist" aria-label="Info" onKeyDown={onTabKeyDown}>
            {tabs.map((entry) => {
              const chosen = entry.id === tab
              return (
                <button
                  key={entry.id}
                  type="button"
                  role="tab"
                  id={`app-info-tab-${entry.id}`}
                  class={`app-segment${chosen ? ' is-on' : ''}`}
                  data-tab={entry.id}
                  aria-selected={chosen}
                  aria-controls="app-info-panel"
                  //? only the chosen one is a tab stop; the arrows reach the other
                  tabIndex={chosen ? 0 : -1}
                  onClick={() => setTab(entry.id)}
                >
                  {entry.label}
                </button>
              )
            })}
          </div>
        )}

        {/* a tab's panel beside a strip; with none, a region named by the sheet's title */}
        <div
          ref={scroller}
          id="app-info-panel"
          class="app-info-scroll"
          role={tabs.length > 1 ? 'tabpanel' : 'region'}
          aria-labelledby={tabs.length > 1 ? `app-info-tab-${tab}` : 'app-info-title'}
          tabIndex={0}
        >
          {about && (
            <>
              <section class="app-info-section" aria-labelledby="app-info-song">
                <h3 id="app-info-song" class="app-section-title">
                  The song
                </h3>
                <div class="app-card app-info-card">
                  <div class="app-info-text">
                    <p class="app-info-name">{about.song.title}</p>
                    {about.song.artist && <p class="app-info-line">{about.song.artist}</p>}
                    {about.song.lines.map((line) => (
                      <p key={line} class="app-info-line">
                        {line}
                      </p>
                    ))}
                    {about.song.writtenBy && <p class="app-info-line">Written by {about.song.writtenBy}</p>}
                  </div>
                </div>
              </section>

              {about.album && (
                <section class="app-info-section" aria-labelledby="app-info-album">
                  <h3 id="app-info-album" class="app-section-title">
                    The album
                  </h3>
                  {about.album.id && onAlbum ? (
                    <button type="button" class="app-card app-info-card is-link" onClick={onAlbum}>
                      <Cover id={about.album.coverArt} size={120} class="app-info-cover" />
                      <span class="app-info-text">
                        <span class="app-info-name">{about.album.title}</span>
                        {about.album.line && <span class="app-info-line">{about.album.line}</span>}
                        {about.album.pressing && <span class="app-info-line">{about.album.pressing}</span>}
                      </span>
                      <ChevronRightIcon class="app-chevron" />
                    </button>
                  ) : (
                    <div class="app-card app-info-card">
                      <Cover id={about.album.coverArt} size={120} class="app-info-cover" />
                      <div class="app-info-text">
                        <p class="app-info-name">{about.album.title}</p>
                        {about.album.line && <p class="app-info-line">{about.album.line}</p>}
                        {about.album.pressing && <p class="app-info-line">{about.album.pressing}</p>}
                      </div>
                    </div>
                  )}
                </section>
              )}

              {about.artist && (
                <section class="app-info-section" aria-labelledby="app-info-artist">
                  <h3 id="app-info-artist" class="app-section-title">
                    The artist
                  </h3>
                  {about.artist.id && onArtist ? (
                    <button type="button" class="app-card app-info-card is-link" onClick={() => onArtist({ id: about.artist!.id!, name: about.artist!.pageName ?? about.artist!.name })}>
                      <span class="app-info-text">
                        <span class="app-info-name">{about.artist.name}</span>
                        {about.artist.facts && <span class="app-info-line">{about.artist.facts}</span>}
                        {about.artist.count && <span class="app-info-line">{about.artist.count}</span>}
                        {about.artist.note && <span class="app-info-line">{about.artist.note}</span>}
                      </span>
                      <ChevronRightIcon class="app-chevron" />
                    </button>
                  ) : (
                    <div class="app-card app-info-card">
                      <div class="app-info-text">
                        <p class="app-info-name">{about.artist.name}</p>
                        {about.artist.facts && <p class="app-info-line">{about.artist.facts}</p>}
                        {about.artist.count && <p class="app-info-line">{about.artist.count}</p>}
                        {about.artist.note && <p class="app-info-line">{about.artist.note}</p>}
                      </div>
                    </div>
                  )}
                </section>
              )}

              {/* (2.0.0-player.63) what a listener can use of Debug's rows, for everyone - in Debug's words */}
              {playing && (
                <section class="app-info-section" aria-labelledby="app-info-playing">
                  <h3 id="app-info-playing" class="app-section-title">
                    {PLAYING_TITLE}
                  </h3>
                  {infoRows(playing)}
                </section>
              )}

              {/* the album's folder, last: a path to copy (never inside the album's link, where it
                  couldn't be selected and was read out with every press), and a line landing late
                  here moves no card a finger is reaching for */}
              {about.album?.folder && (
                <section class="app-info-section" aria-labelledby="app-info-where">
                  <h3 id="app-info-where" class="app-section-title">
                    {/* (2.0.0-player.52) the album's folder in the store - with a library of your own, said so */}
                    {hasLibrary() ? 'In the store' : 'In your library'}
                  </h3>
                  <dl class="app-group app-kv">
                    <div class="app-kv-row">
                      <dt class="app-kv-label">Folder</dt>
                      <dd class="app-kv-value app-mono app-info-folder">{about.album.folder}</dd>
                    </div>
                  </dl>
                </section>
              )}
            </>
          )}

          {debug?.map((section, index) => (
            <section key={section.title} class="app-info-section" aria-labelledby={`app-info-debug-${index}`}>
              <h3 id={`app-info-debug-${index}`} class="app-section-title">
                {section.title}
              </h3>
              {infoRows(section.rows)}
            </section>
          ))}
        </div>
      </div>
    </div>
  )
}

/** Labelled rows, as Debug draws them and About's Playing group (2.0.0-player.63) - a row's control too. Called,
 *  not mounted, so the rows are the sheet's own elements. */
function infoRows(rows: DebugRow[]) {
  return (
    <dl class="app-group app-kv">
      {rows.map((row) => (
        <div key={row.label} class="app-kv-row">
          <dt class="app-kv-label">{row.label}</dt>
          <dd class={`app-kv-value${row.mono ? ' app-mono' : ''}`}>{row.value}</dd>
          {row.note && <dd class="app-kv-note app-mono">{row.note}</dd>}
          {row.action && (
            <dd class="app-kv-action">
              {row.action.href && row.action.beside ? (
                //? a page of its own (2.0.0-player.36, the turntable's test bench): beside the app, never over it
                <a class="app-button app-info-action" href={row.action.href} target="_blank" rel="noopener">
                  {row.action.label}
                </a>
              ) : row.action.href ? (
                <a class="app-button app-info-action" href={row.action.href} download={row.action.download}>
                  {row.action.label}
                </a>
              ) : (
                <button type="button" class="app-button app-info-action" onClick={row.action.onClick}>
                  {row.action.label}
                </button>
              )}
            </dd>
          )}
        </div>
      ))}
    </dl>
  )
}
