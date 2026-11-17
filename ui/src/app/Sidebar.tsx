import type { FunctionComponent } from 'preact'
import { useEffect, useState } from 'preact/hooks'

import {
  foldCurrent, LIBRARY_SIDES, manageHeadLabel, SIDE_LABELS, SIDEBAR_CARE, SIDEBAR_LOG, SIDEBAR_PEOPLE, SIDEBAR_PLAYLISTS, SIDEBAR_QUEUE,
  SIDEBAR_SETTINGS, SIDEBAR_TOP, sideFlip, sideShown, sidebarRows, type LibrarySide, type SidebarFold, type SidebarFolds, type SidebarId,
  type SidebarItem,
} from '../lib/appFrame'
import { TAB_LABELS } from '../lib/appRoutes'
import { needsLookLabel } from '../lib/needsLook'
import { managing as managingOf, ALL, type Managing } from '../lib/permissions'
import { badgeLabel, badgeText } from '../lib/requestsView'
import { SEARCH_MAX_CHARS } from '../lib/searchQuery'
import { searchWords } from '../lib/searchResults'
import {
  AlbumIcon, ArtistIcon, CareIcon, ChevronDownIcon, ClockIcon, FlagIcon, HomeIcon, LogIcon, PeopleIcon, PlaylistIcon, RequestsIcon, SearchIcon,
  ServerIcon, SettingsIcon, SongIcon,
} from '../player/icons'
import { readSidebarFolds, readSidebarSide, writeSidebarFolds, writeSidebarSide } from '../state/persisted'
import { onSearchText, searchText, submitSearch, typeSearch } from './searchBox'

/** (2.1.35) Each row's glyph - Home and Requests the tab bar's own, the Library's the phone root's rows' (a clock for
 *  Recently added), the playlists' the Playlists row's, and Manage's and Settings' new (player/icons.tsx). */
const ICONS: Readonly<Record<SidebarId, FunctionComponent<{ class?: string }>>> = {
  home: HomeIcon,
  requests: RequestsIcon,
  recent: ClockIcon,
  albums: AlbumIcon,
  artists: ArtistIcon,
  songs: SongIcon,
  store: AlbumIcon,
  storeArtists: ArtistIcon,
  playlists: PlaylistIcon,
  queue: FlagIcon,
  care: CareIcon,
  people: PeopleIcon,
  settings: ServerIcon,
  log: LogIcon,
  you: SettingsIcon,
}

//? (2.1.35) the switch's side and the folds, kept for the page's life as well as on the device (state/persisted.ts):
//? a sidebar made again - the window crossing 1024px and back - finds them where they were, with storage or without
let keptSide: LibrarySide | null = null
let keptFolds: SidebarFolds | null = null

/**
 * The desktop's sidebar (2.0.0-player.19), as DesktopLibrary.dc.html first drew it - the phone's five tabs, laid out
 * for a desktop - and since 2.1.35 with a glyph on every row and one Library group (James: "the left menu bar on
 * desktop isn't super easy to navigate, I would like maybe some icons and to make the layout a bit more intuitive" -
 * and the layout he chose):
 *
 *   the wordmark and the search field; Home and Requests (with the count of what is arriving, the phone tab's badge);
 *   LIBRARY, with a Yours | All switch in its heading; PLAYLISTS and MANAGE, each folding away; Settings at the foot.
 *
 * Every row has its glyph (`ICONS`, aria-hidden, drawn at one weight by app-desktop.css) before its words; a playlist
 * of the Playlists group has none, its name set under All playlists' words - twenty of one glyph in a column would say
 * "playlist" twenty times over, and the names read as All playlists' own under it.
 *
 * THE LIBRARY (2.1.35, lib/appFrame.ts sidebarRows): with a library of your own (`personal`), one group whose switch
 * says whose its rows are - Yours: Recently added, Albums, Artists; All, the collection's: Albums, Artists and Songs
 * (left out when Navidrome lists none). The rows say Albums and Artists plainly; the switch says whose, and the pages'
 * titles keep saying "Your albums" and "All albums". The switch shows where you are while a Library view itself shows
 * (`sideShown`): All on one of the collection's, Yours on one of yours; anywhere else the side last shown - remembered
 * on this device (deadwax-sidebar-side) and for the page's life - and that includes an album, an artist or a playlist
 * pushed above a view (`overView`, lib/appFrame.ts overLibraryView; review of 2.1.35). Turned with a view showing it
 * opens the same kind of view on the other side (`sideFlip`: Albums for Albums, Artists for Artists, Recently added
 * to All's Albums, Songs back to your Albums); anywhere else, over a pushed page too - which opening a view would pop
 * - it only changes the rows. A radio group: a click picks; to the keyboard the arrows move the
 * choice, and the focus with it, and only the chosen side is a tab stop - the Settings page's segmented controls' way. With logins
 * off (and for the break-glass admin) there is no switch and the rows are the library's, as they always were:
 * Recently added, Albums, Artists, Songs.
 *
 * PLAYLISTS AND MANAGE FOLD AWAY (2.1.35): each heading is a button (aria-expanded, aria-controls its list) - both
 * open until folded, what is folded remembered on this device (deadwax-sidebar-folded) and for the page's life. A
 * folded group whose page is showing marks its heading current (`foldCurrent`), and a folded Manage still carries
 * Needs a look's count (`manageHeadLabel` says it). Library, Home and Requests never fold.
 *
 * Every row is App's to interpret through lib/appFrame.ts's sidebarMove: Home, Requests and Settings are their tabs'
 * buttons (as left, or back to the root when showing); a Library view shows that view at the Library's root. The item
 * for where the app is says so (`aria-current`), in Explorer's selection.
 *
 * THE SEARCH FIELD is the Search tab's box (app/searchBox.ts): typing here is typing there - the search, its pacing
 * and its guards stay Search's - and App shows Search's results at its root as the first key goes in (`onSearch`);
 * Enter asks both halves at once. It keeps saying what was searched for while an album found by it is open, as
 * DesktopRequest.dc.html draws it.
 *
 * PLAYLISTS (2.0.0-player.58), as the Mac's Music app has them: All playlists - the Playlists page - then up to 20
 * playlists by name, yours and then shared with you, never the ones Navidrome made from files (lib/playlists.ts
 * sidebarPlaylists, App's `playlists`); each opens its page (`onPlaylist`), and is the current one while its page is on
 * top (`currentPlaylist`) - a playlist page whose playlist isn't listed makes All playlists current. While the list
 * isn't known, or failed, All playlists alone.
 *
 * MANAGE (2.0.0-player.61: each item by its permission - `managing`, lib/permissions.ts, from what App's /deadwax/me
 * said as the desktop frame shows; with logins off, everyone has all of them, as Settings' rows, which ask the same -
 * and the group gone with none): "Needs a look" first (2.0.0-player.25), the review queue's page, with how many albums
 * need one (`needsLook`, app/useQueueSummary.ts - no badge while that isn't known, never a 0 over an unknown); then
 * "Library care" (2.0.0-player.42), Rescan and the bulk runs; then "People" (2.0.0-player.61), Navidrome's accounts, a
 * Navidrome admin's with logins on; then "Server settings" and "Event log" (2.0.0-player.33), the server's settings and
 * the event log as pages of the app - no unread count on the log, which would need its stream held open.
 *
 * A leaf: props, the search box's store, and this device's two remembered choices.
 */
export function Sidebar({
  current,
  hasSongs,
  personal = false,
  overView = false,
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
  /** whether Navidrome's empty search lists songs (null: not known yet) - Songs left out when it lists none */
  hasSongs: boolean | null
  /** (2.0.0-player.52) a library of your own: the Library's switch, and the field searches the store first (its
   *  name says so) */
  personal?: boolean
  /** (2.1.35, review) a page is pushed above the Library's view (lib/appFrame.ts overLibraryView) - an album, an
   *  artist, a playlist: the switch shows the side last shown there, and a turn changes only the rows */
  overView?: boolean
  /** downloads on their way: Requests' count, as the phone tab's badge */
  arriving: number
  /** (2.0.0-player.61) which Manage items this person's permissions open - lib/permissions.ts managing */
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

  const [remembered, setRemembered] = useState<LibrarySide>(() => keptSide ?? (keptSide = readSidebarSide()))
  const [folds, setFolds] = useState<SidebarFolds>(() => keptFolds ?? (keptFolds = readSidebarFolds()))
  const remember = (side: LibrarySide) => {
    keptSide = side
    writeSidebarSide(side)
    setRemembered(side)
  }
  const side = sideShown(current, remembered, overView)
  //? the side shown is the side remembered: a Library view of the other side (reached from its row, Browse the store,
  //? a link) leaves its side's rows in view as you go Home, rather than swapping them back. Keyed on where the app
  //? is, not on the side: a turn of the switch that is still opening its view never reads as the old side shown. A
  //? page pushed above a view shows the side remembered, so writes nothing; back down to the view, it is written
  useEffect(() => {
    const shown = sideShown(current, remembered, overView)
    if (personal && shown !== remembered) remember(shown)
  }, [current, personal, overView])

  //? the switch turned: the rows that side's, and with a Library view of the other side showing the same kind of view
  //? on this one - never over a page pushed above a view, which opening one would pop
  const flip = (to: LibrarySide) => {
    if (to === side) return
    remember(to)
    const opens = sideFlip(current, to, overView)
    if (opens) onSelect(opens)
  }
  //? a radio group's keys, as the Settings page's segmented controls take them: an arrow moves the choice - and the focus with it
  const onSwitchKeyDown = (event: KeyboardEvent) => {
    const step = event.key === 'ArrowDown' || event.key === 'ArrowRight' ? 1 : event.key === 'ArrowUp' || event.key === 'ArrowLeft' ? -1 : 0
    if (!step) return
    event.preventDefault()
    const at = LIBRARY_SIDES.indexOf(side)
    const next = LIBRARY_SIDES[(at + step + LIBRARY_SIDES.length) % LIBRARY_SIDES.length]!
    flip(next)
    ;(event.currentTarget as HTMLElement).querySelector<HTMLElement>(`[data-side="${next}"]`)?.focus()
  }

  //? from what is kept, not this render's copy: two folds before a render draws the first both count
  const toggle = (fold: SidebarFold) => {
    const was = keptFolds ?? folds
    const next = { ...was, [fold]: !was[fold] }
    keptFolds = next
    writeSidebarFolds(next)
    setFolds(next)
  }

  const item = ({ id, label }: SidebarItem) => {
    const chosen = id === current
    const badge = id === 'requests' ? badgeText(arriving) : id === 'queue' ? badgeText(needsLook ?? 0) : ''
    const Icon = ICONS[id]
    return (
      <li key={id}>
        <button
          type="button"
          class={`app-side-item${chosen ? ' is-current' : ''}`}
          {...(chosen ? { 'aria-current': 'page' as const } : {})}
          {...(badge ? { 'aria-label': id === 'queue' ? needsLookLabel(label, needsLook) : badgeLabel(label, arriving) } : {})}
          onClick={() => onSelect(id)}
        >
          <Icon class="app-side-icon" />
          <span class="app-side-item-label" dir="auto">{label}</span>
          {badge && (
            <span class="app-side-badge" aria-hidden="true">
              {badge}
            </span>
          )}
        </button>
      </li>
    )
  }

  //? a heading that folds its group away: a button saying whether the list it controls is open; folded with its page
  //? showing, it is drawn current; Manage's folded carries Needs a look's count (`count`)
  const foldHead = (fold: SidebarFold, id: string, label: string, count = '') => {
    const open = !folds[fold]
    const marked = foldCurrent(fold, folds, current)
    return (
      <h2 class="app-side-label app-side-fold-head">
        <button
          type="button"
          class={`app-side-fold${marked ? ' is-current' : ''}`}
          aria-expanded={open}
          aria-controls={`${id}-list`}
          {...(marked ? { 'aria-current': 'true' as const } : {})}
          {...(count ? { 'aria-label': manageHeadLabel(!open, needsLook) } : {})}
          onClick={() => toggle(fold)}
        >
          <span id={id} class="app-side-fold-label">{label}</span>
          {count && (
            <span class="app-side-badge" aria-hidden="true">
              {count}
            </span>
          )}
          <ChevronDownIcon class="app-side-fold-icon" />
        </button>
      </h2>
    )
  }

  const manageCount = folds.manage && managing.queue ? badgeText(needsLook ?? 0) : ''

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
            //? (2.0.5) "Search" - "Search everything" said "everything" for the collection, and Search's own
            //? "Artists, albums and songs" doesn't fit the sidebar's field; its name (aria-label) says what it searches
            placeholder="Search"
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
        <div class="app-side-head">
          <h2 id="app-side-library" class="app-side-label">
            Library
          </h2>
          {personal && (
            <div class="app-side-switch" role="radiogroup" aria-labelledby="app-side-library" onKeyDown={onSwitchKeyDown}>
              {LIBRARY_SIDES.map((one) => {
                const on = one === side
                return (
                  <button
                    key={one}
                    type="button"
                    role="radio"
                    class="app-side-side"
                    data-side={one}
                    aria-checked={on}
                    //? only the chosen side is a tab stop; the arrows reach the other
                    tabIndex={on ? 0 : -1}
                    onClick={() => flip(one)}
                  >
                    {SIDE_LABELS[one]}
                  </button>
                )
              })}
            </div>
          )}
        </div>
        <ul class="app-side-list">{sidebarRows(side, hasSongs, personal).map(item)}</ul>
      </section>

      <section class="app-side-group" aria-labelledby="app-side-playlists">
        {foldHead('playlists', 'app-side-playlists', 'Playlists')}
        <ul id="app-side-playlists-list" class="app-side-list" hidden={folds.playlists}>
          {current === 'playlists' && currentPlaylist !== null && playlists.some((one) => one.id === currentPlaylist)
            ? (
              <li key="playlists">
                <button type="button" class="app-side-item" onClick={() => onSelect('playlists')}>
                  <PlaylistIcon class="app-side-icon" />
                  <span class="app-side-item-label" dir="auto">{SIDEBAR_PLAYLISTS.label}</span>
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
                  <span class="app-side-item-label" dir="auto">{one.name}</span>
                </button>
              </li>
            )
          })}
        </ul>
      </section>

      {managing.any && (
        <section class="app-side-group" aria-labelledby="app-side-managing">
          {/* (2.0.8, UX batch 5) "Manage", James's word for the admin area - it was "Managing" */}
          {foldHead('manage', 'app-side-managing', 'Manage', manageCount)}
          <ul id="app-side-managing-list" class="app-side-list" hidden={folds.manage}>
            {managing.queue && item(SIDEBAR_QUEUE)}
            {managing.care && item(SIDEBAR_CARE)}
            {managing.people && item(SIDEBAR_PEOPLE)}
            {managing.settings && item(SIDEBAR_SETTINGS)}
            {managing.log && item(SIDEBAR_LOG)}
          </ul>
        </section>
      )}

      {/* (2.1.35) Settings - You until then, as the iPhone app names it - a gear where the avatar was, on a foot that
          stays in view while the groups above it scroll (twenty playlists put it below a laptop's fold) */}
      <div class="app-side-foot">
        <button
          type="button"
          class={`app-side-item app-side-you${current === 'you' ? ' is-current' : ''}`}
          {...(current === 'you' ? { 'aria-current': 'page' as const } : {})}
          onClick={() => onSelect('you')}
        >
          <SettingsIcon class="app-side-icon" />
          <span class="app-side-item-label" dir="auto">{TAB_LABELS.you}</span>
        </button>
      </div>
    </nav>
  )
}
