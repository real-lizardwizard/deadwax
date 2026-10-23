import { useEffect, useState } from 'preact/hooks'

import { SIDEBAR_CARE, SIDEBAR_LOG, SIDEBAR_PEOPLE, SIDEBAR_PLAYLISTS, SIDEBAR_QUEUE, SIDEBAR_SETTINGS, SIDEBAR_TOP, type SidebarId, type SidebarItem } from '../lib/appFrame'
import { needsLookLabel } from '../lib/needsLook'
import { managing as managingOf, ALL, type Managing } from '../lib/permissions'
import { badgeLabel, badgeText } from '../lib/requestsView'
import { SEARCH_MAX_CHARS } from '../lib/searchQuery'
import { searchWords } from '../lib/searchResults'
import { SearchIcon, YouIcon } from '../player/icons'
import { onSearchText, searchText, submitSearch, typeSearch } from './searchBox'

/**
 * The desktop's sidebar (2.0.0-player.19), as DesktopLibrary.dc.html draws it: the wordmark, the
 * search field, Home and Requests (with the count of what is arriving, the phone tab's badge), the
 * Library's views (Recently added, Albums, Artists, Songs), Managing, and You at the foot - the
 * phone's five tabs, laid out for a desktop. With logins on and a library of your own (2.0.0-player.52),
 * the Library's views are yours (Recently added, Albums, Artists) and a group of its own under them,
 * Browse, lists the store's (Albums, Artists, Songs) - lib/appFrame.ts libraryItems and browseItems. Every item is App's to interpret through
 * lib/appFrame.ts's sidebarMove: Home, Requests and You are their tabs' buttons (as left, or back to
 * the root when showing); a Library view shows that view at the Library's root. The item for where
 * the app is says so (`aria-current`), in Explorer's selection.
 *
 * THE SEARCH FIELD is the Search tab's box (app/searchBox.ts): typing here is typing there - the
 * search, its pacing and its guards stay Search's - and App shows Search's results at its root as
 * the first key goes in (`onSearch`); Enter asks both halves at once. It keeps saying what was
 * searched for while an album found by it is open, as DesktopRequest.dc.html draws it.
 *
 * PLAYLISTS (2.0.0-player.58), after the Library's (and Browse's) groups and before Managing, as the Mac's Music app
 * has them: All playlists - the Playlists page - then up to 20 playlists by name, yours and then shared with you,
 * never the ones Navidrome made from files (lib/playlists.ts sidebarPlaylists, App's `playlists`); each opens its
 * page (`onPlaylist`), and is the current one while its page is on top (`currentPlaylist`) - a playlist page whose
 * playlist isn't listed makes All playlists current. While the list isn't known, or failed, All playlists alone.
 *
 * MANAGING (2.0.0-player.61: each item by its permission - `managing`, lib/permissions.ts, from what App's
 * /deadwax/me said as the desktop frame shows; with logins off, everyone has all of them, as You's rows, which
 * ask the same - and the group gone with none): "Needs a look" first (2.0.0-player.25), the review queue's page,
 * with how many albums need one (`needsLook`, app/useQueueSummary.ts - no badge while that isn't known, never a
 * 0 over an unknown); then "Library care" (2.0.0-player.42), Rescan and the bulk runs; then "People"
 * (2.0.0-player.61), Navidrome's accounts, a Navidrome admin's with logins on; then "Settings" and "Log"
 * (2.0.0-player.33), the server's settings and the event log as pages of the app - no unread count on
 * the Log, which would need its stream held open. Managing lists only its pages: the link to the main page
 * that closed it (James: "Managing links to / for now") went when that page retired in 2.0.0-player.66.
 *
 * A leaf: props, and the search box's store.
 */
export function Sidebar({
  current,
  library,
  browse = [],
  personal = false,
  arriving,
  managing = managingOf(ALL),
  needsLook = null,
  playlists = [],
  currentPlaylist = null,
  onPlaylist,
  onSelect,
  onSearch,
}: {
  /** the item for where the app is; null on Search, whose place is the field */
  current: SidebarId | null
  /** the Library's views, Songs left out when Navidrome lists none (lib/appFrame.ts libraryItems) */
  library: readonly SidebarItem[]
  /** (2.0.0-player.52) Browse's views - the store's - with a library of your own; none with logins off */
  browse?: readonly SidebarItem[]
  /** (2.0.0-player.52) a library of your own: the field searches the store first (its name says so) */
  personal?: boolean
  /** downloads on their way: Requests' count, as the phone tab's badge */
  arriving: number
  /** (2.0.0-player.61) which Managing items this person's permissions open - lib/permissions.ts managing */
  managing?: Managing
  /** how many albums need a look (null: not known yet) - Needs a look's count */
  needsLook?: number | null
  /** (2.0.0-player.58) the playlists the group lists, by name - yours, then shared with you (lib/playlists.ts sidebarPlaylists) */
  playlists?: readonly { id: string; name: string }[]
  /** the listed playlist whose page is on top of the tab showing - drawn current in place of All playlists */
  currentPlaylist?: string | null
  onPlaylist?: ((id: string) => void) | undefined
  onSelect: (item: SidebarId) => void
  /** something typed, or Enter: Search's results shown */
  onSearch: () => void
}) {
  const [text, setText] = useState(searchText)
  useEffect(() => onSearchText(setText), [])

  const item = ({ id, label }: SidebarItem) => {
    const chosen = id === current
    const badge = id === 'requests' ? badgeText(arriving) : id === 'queue' ? badgeText(needsLook ?? 0) : ''
    return (
      <li key={id}>
        <button
          type="button"
          class={`app-side-item${chosen ? ' is-current' : ''}`}
          {...(chosen ? { 'aria-current': 'page' as const } : {})}
          {...(badge ? { 'aria-label': id === 'queue' ? needsLookLabel(label, needsLook) : badgeLabel(label, arriving) } : {})}
          onClick={() => onSelect(id)}
        >
          <span class="app-side-item-label">{label}</span>
          {badge && (
            <span class="app-side-badge app-mono" aria-hidden="true">
              {badge}
            </span>
          )}
        </button>
      </li>
    )
  }

  return (
    <nav class="app-side" aria-label="Sections">
      <p class="app-side-brand">deadwax</p>

      <form
        class="app-side-search"
        role="search"
        onSubmit={(event) => {
          event.preventDefault()
          if (!text.trim()) return
          onSearch()
          submitSearch()
        }}
      >
        <label class="app-side-field">
          <SearchIcon class="app-side-field-icon" />
          <input
            class="app-side-input"
            type="search"
            value={text}
            onInput={(event) => {
              const next = (event.currentTarget as HTMLInputElement).value
              setText(next)
              typeSearch(next)
              if (next.trim()) onSearch()
            }}
            maxLength={SEARCH_MAX_CHARS}
            placeholder="Search everything"
            aria-label={searchWords(personal).label}
            enterKeyHint="search"
            autoComplete="off"
            autoCapitalize="none"
            spellcheck={false}
          />
        </label>
      </form>

      <ul class="app-side-list">{SIDEBAR_TOP.map(item)}</ul>

      <section class="app-side-group" aria-labelledby="app-side-library">
        <h2 id="app-side-library" class="app-side-label">
          Library
        </h2>
        <ul class="app-side-list">{library.map(item)}</ul>
      </section>

      {browse.length > 0 && (
        <section class="app-side-group" aria-labelledby="app-side-browse">
          <h2 id="app-side-browse" class="app-side-label">
            Browse
          </h2>
          <ul class="app-side-list">{browse.map(item)}</ul>
        </section>
      )}

      <section class="app-side-group" aria-labelledby="app-side-playlists">
        <h2 id="app-side-playlists" class="app-side-label">
          Playlists
        </h2>
        <ul class="app-side-list">
          {current === 'playlists' && currentPlaylist !== null && playlists.some((one) => one.id === currentPlaylist)
            ? (
              <li key="playlists">
                <button type="button" class="app-side-item" onClick={() => onSelect('playlists')}>
                  <span class="app-side-item-label">{SIDEBAR_PLAYLISTS.label}</span>
                </button>
              </li>
            )
            : item(SIDEBAR_PLAYLISTS)}
          {playlists.map((one) => {
            const chosen = current === 'playlists' && one.id === currentPlaylist
            return (
              <li key={`playlist:${one.id}`}>
                <button
                  type="button"
                  class={`app-side-item app-side-playlist${chosen ? ' is-current' : ''}`}
                  {...(chosen ? { 'aria-current': 'page' as const } : {})}
                  onClick={() => onPlaylist?.(one.id)}
                >
                  <span class="app-side-item-label">{one.name}</span>
                </button>
              </li>
            )
          })}
        </ul>
      </section>

      {managing.any && (
        <section class="app-side-group" aria-labelledby="app-side-managing">
          <h2 id="app-side-managing" class="app-side-label">
            Managing
          </h2>
          <ul class="app-side-list">
            {managing.queue && item(SIDEBAR_QUEUE)}
            {managing.care && item(SIDEBAR_CARE)}
            {managing.people && item(SIDEBAR_PEOPLE)}
            {managing.settings && item(SIDEBAR_SETTINGS)}
            {managing.log && item(SIDEBAR_LOG)}
          </ul>
        </section>
      )}

      <button
        type="button"
        class={`app-side-item app-side-you${current === 'you' ? ' is-current' : ''}`}
        {...(current === 'you' ? { 'aria-current': 'page' as const } : {})}
        onClick={() => onSelect('you')}
      >
        <span class="app-side-avatar" aria-hidden="true">
          <YouIcon class="app-side-avatar-icon" />
        </span>
        <span class="app-side-item-label">You</span>
      </button>
    </nav>
  )
}
