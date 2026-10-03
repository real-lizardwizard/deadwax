import { useEffect, useState } from 'preact/hooks'

import { SIDEBAR_TOP, type SidebarId, type SidebarItem } from '../lib/appFrame'
import { badgeLabel, badgeText } from '../lib/requestsView'
import { SEARCH_MAX_CHARS } from '../lib/searchQuery'
import { SearchIcon, YouIcon } from '../player/icons'
import { onSearchText, searchText, submitSearch, typeSearch } from './searchBox'

/**
 * The desktop's sidebar (2.0.0-player.19), as DesktopLibrary.dc.html draws it: the wordmark, the
 * search field, Home and Requests (with the count of what is arriving, the phone tab's badge), the
 * Library's views (Recently added, Albums, Artists, Songs), Managing, and You at the foot - the
 * phone's five tabs, laid out for a desktop. Every item is App's to interpret through
 * lib/appFrame.ts's sidebarMove: Home, Requests and You are their tabs' buttons (as left, or back to
 * the root when showing); a Library view shows that view at the Library's root. The item for where
 * the app is says so (`aria-current`), in Explorer's selection.
 *
 * THE SEARCH FIELD is the Search tab's box (app/searchBox.ts): typing here is typing there - the
 * search, its pacing and its guards stay Search's - and App shows Search's results at its root as
 * the first key goes in (`onSearch`); Enter asks both halves at once. It keeps saying what was
 * searched for while an album found by it is open, as DesktopRequest.dc.html draws it.
 *
 * MANAGING links to the main page for now (James: "Managing links to / for now"): server settings,
 * the albums that need a look, the log and editing an album are there until the app has them. It
 * opens BESIDE the app, as every link out does - in the same tab it would unload the player. Shown
 * unless deadwax says this user isn't an admin (`admin`: App asks /deadwax/me as the desktop frame
 * shows); with logins off, everyone is - as You's row, which asks the same.
 *
 * A leaf: props, and the search box's store.
 */
export function Sidebar({
  current,
  library,
  arriving,
  admin = true,
  onSelect,
  onSearch,
}: {
  /** the item for where the app is; null on Search, whose place is the field */
  current: SidebarId | null
  /** the Library's views, Songs left out when Navidrome lists none (lib/appFrame.ts libraryItems) */
  library: readonly SidebarItem[]
  /** downloads on their way: Requests' count, as the phone tab's badge */
  arriving: number
  /** deadwax's /me says this user is an admin (true until it has answered, as You's rows) */
  admin?: boolean
  onSelect: (item: SidebarId) => void
  /** something typed, or Enter: Search's results shown */
  onSearch: () => void
}) {
  const [text, setText] = useState(searchText)
  useEffect(() => onSearchText(setText), [])

  const item = ({ id, label }: SidebarItem) => {
    const chosen = id === current
    const badge = id === 'requests' ? badgeText(arriving) : ''
    return (
      <li key={id}>
        <button
          type="button"
          class={`app-side-item${chosen ? ' is-current' : ''}`}
          {...(chosen ? { 'aria-current': 'page' as const } : {})}
          {...(badge ? { 'aria-label': badgeLabel(label, arriving) } : {})}
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
            aria-label="Search your library and MusicBrainz"
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

      {admin && (
        <section class="app-side-group" aria-labelledby="app-side-managing">
          <h2 id="app-side-managing" class="app-side-label">
            Managing
          </h2>
          <ul class="app-side-list">
            <li>
              <a
                class="app-side-item"
                href="/"
                target="_blank"
                rel="noopener"
                title="Server settings, albums that need a look, the log and editing an album - on the main page for now"
              >
                <span class="app-side-item-label">Open the main page</span>
              </a>
            </li>
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
