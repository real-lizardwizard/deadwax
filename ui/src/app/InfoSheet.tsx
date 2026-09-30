import { useLayoutEffect, useRef, useState } from 'preact/hooks'

import { aboutRows, type About, type AboutAlbumFields } from '../lib/aboutRows'
import { debugSections, type DebugSection } from '../lib/debugRows'
import type { QueueTrack } from '../lib/playQueue'
import { Cover } from '../player/Cover'
import { ChevronRightIcon } from '../player/icons'
import type { Player } from '../player/usePlayer'
import { useSheet } from './useSheet'

export type InfoTab = 'about' | 'debug'

export const INFO_TABS: readonly { id: InfoTab; label: string }[] = [
  { id: 'about', label: 'About' },
  { id: 'debug', label: 'Debug' },
]

/** What the sheet last drew, kept so it slides away still showing it. */
interface Drawn {
  about: About | null
  debug: DebugSection[] | null
}

/**
 * Info: a sheet over Now Playing, opened from its ••• menu (2.0.0-player.10), with two tabs.
 *
 * - ABOUT: the song, its album and its artist, from what the app already has (lib/aboutRows.ts) -
 *   the queue's copy of the song and the album answer it was played from. A field Navidrome didn't
 *   send is left out, never invented. The album's card goes to the album, like "Go to album".
 * - DEBUG: what used to be two lines on the now-playing screen - how the song was sent, how the
 *   last song changes and the last seek went - as labelled rows (lib/debugRows.ts), and the names
 *   of the fields Navidrome sent for the song and its album, to read off a phone.
 *
 * A sheet like the others (useSheet.ts): its own scroll lock, focus in to Done and back to the •••
 * button, Escape, a tap on the backdrop above it; inert while closed. Its body is the one part of
 * the player's sheets that SCROLLS, so it says so itself (`touch-action: pan-y` in app.css): the
 * layer it sits in takes every touch, as Now Playing does, so that nothing on it pans the page
 * behind - and a scroller starts its own count, so its own panning comes back inside it.
 *
 * The rows are worked out only while it is open, and what it last drew is kept while it slides
 * away. `sentFormat` is asked only for Debug: it puts a question to the player's audio element.
 * It stays mounted, and a closed sheet is only hidden, so its one scroller would keep its offset
 * from one opening to the next and from one tab to the other: it is put back at the top as Info
 * opens and as the tab changes - never as it closes, while it is still sliding away in sight.
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
}: {
  open: boolean
  opener?: { current: HTMLElement | null } | undefined
  onClose: () => void
  /** close everything and open the song's album; null when it names none to go to */
  onAlbum: (() => void) | null
  player: Pick<Player, 'track' | 'gapless' | 'maxRate' | 'gaps' | 'lastSeek' | 'wrapped'>
  /** the album answer the queue was played from, as Navidrome sent it; null when not in hand */
  album: AboutAlbumFields | null
  sentFormat: (track: QueueTrack) => 'raw' | 'mp3' | null
}) {
  const done = useRef<HTMLButtonElement>(null)
  const scroller = useRef<HTMLDivElement>(null)
  const [tab, setTab] = useState<InfoTab>('about')
  const drawn = useRef<Drawn>({ about: null, debug: null })
  useSheet({ open, onClose, lockClass: 'app-info-open', first: done, opener })

  //? the list from its top, whichever song and tab it opens on - Format and Sent as, not the end
  useLayoutEffect(() => {
    if (open && scroller.current) scroller.current.scrollTop = 0
  }, [open, tab])

  const track = player.track
  if (open && track) {
    if (tab === 'about') {
      drawn.current = { about: aboutRows(track, album), debug: null }
    } else {
      const answer = album as Readonly<Record<string, unknown>> | null
      const song = album?.song?.find((candidate) => candidate.id === track.id) ?? null
      drawn.current = {
        about: null,
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
        }),
      }
    }
  }
  const { about, debug } = drawn.current

  //? a tab list's keys: the arrows move the choice, and the focus with it, between the two
  const onTabKeyDown = (event: KeyboardEvent) => {
    const step = event.key === 'ArrowRight' ? 1 : event.key === 'ArrowLeft' ? -1 : 0
    if (!step) return
    event.preventDefault()
    const at = INFO_TABS.findIndex((entry) => entry.id === tab)
    const other = INFO_TABS[(at + step + INFO_TABS.length) % INFO_TABS.length]!
    setTab(other.id)
    ;(event.currentTarget as HTMLElement).querySelector<HTMLElement>(`[data-tab="${other.id}"]`)?.focus()
  }

  return (
    <div class={`app-layer app-info-layer${open ? ' is-open' : ''}`} aria-hidden={!open} inert={!open}>
      <div class="app-backdrop" onClick={onClose} />
      <div class="app-info" role="dialog" aria-modal="true" aria-labelledby="app-info-title">
        <header class="app-info-head">
          <h2 id="app-info-title" class="app-info-title">
            Info
          </h2>
          <button ref={done} type="button" class="app-info-done" onClick={onClose}>
            Done
          </button>
        </header>

        <div class="app-segmented" role="tablist" aria-label="Info" onKeyDown={onTabKeyDown}>
          {INFO_TABS.map((entry) => {
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

        <div
          ref={scroller}
          id="app-info-panel"
          class="app-info-scroll"
          role="tabpanel"
          aria-labelledby={`app-info-tab-${tab}`}
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
                      </span>
                      <ChevronRightIcon class="app-chevron" />
                    </button>
                  ) : (
                    <div class="app-card app-info-card">
                      <Cover id={about.album.coverArt} size={120} class="app-info-cover" />
                      <div class="app-info-text">
                        <p class="app-info-name">{about.album.title}</p>
                        {about.album.line && <p class="app-info-line">{about.album.line}</p>}
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
                  <div class="app-card app-info-card">
                    <div class="app-info-text">
                      <p class="app-info-name">{about.artist.name}</p>
                      {about.artist.note && <p class="app-info-line">{about.artist.note}</p>}
                    </div>
                  </div>
                </section>
              )}
            </>
          )}

          {debug?.map((section, index) => (
            <section key={section.title} class="app-info-section" aria-labelledby={`app-info-debug-${index}`}>
              <h3 id={`app-info-debug-${index}`} class="app-section-title">
                {section.title}
              </h3>
              <dl class="app-group app-kv">
                {section.rows.map((row) => (
                  <div key={row.label} class="app-kv-row">
                    <dt class="app-kv-label">{row.label}</dt>
                    <dd class={`app-kv-value${row.mono ? ' app-mono' : ''}`}>{row.value}</dd>
                    {row.note && <dd class="app-kv-note app-mono">{row.note}</dd>}
                  </div>
                ))}
              </dl>
            </section>
          ))}
        </div>
      </div>
    </div>
  )
}
