import type { FunctionComponent } from 'preact'

import { TAB_LABELS, TABS, type Tab } from '../lib/appRoutes'
import { badgeLabel, badgeText } from '../lib/requestsView'
import { HomeIcon, LibraryIcon, RequestsIcon, SearchIcon, YouIcon } from '../player/icons'

const ICONS: Record<Tab, FunctionComponent<{ class?: string }>> = {
  home: HomeIcon,
  library: LibraryIcon,
  search: SearchIcon,
  requests: RequestsIcon,
  you: YouIcon,
}

/**
 * The five tabs along the bottom: Home, Library, Search, Requests and You, You at the right end.
 * Flat, as STYLE.md draws it - no pill, no blur - the chosen tab in the accent.
 *
 * A tap is App's to interpret (lib/appRoutes.ts's selectTab): another tab shows it as it was
 * left; the tab showing pops back to its root, and at its root scrolls to the top. So these are
 * buttons, not links - the address is App's to set.
 *
 * Requests carries a small count of the downloads on their way (2.0.0-player.12) - what the main
 * page's Downloads badge counts, and exactly what Home's Arriving lists: App hands it that list's
 * length - and none at zero. Heard as "Requests, 2 arriving"; the number itself is only drawn. On
 * a phone on its side the count sits beside the icon, in the row (app.css), where it can't run
 * over the label.
 */
export function TabBar({
  current,
  onSelect,
  arriving = 0,
}: {
  current: Tab
  onSelect: (tab: Tab) => void
  /** downloads on their way: the Requests tab's badge */
  arriving?: number
}) {
  return (
    <nav class="app-tabbar" aria-label="Sections">
      {TABS.map((tab) => {
        const Icon = ICONS[tab]
        const chosen = tab === current
        const badge = tab === 'requests' ? badgeText(arriving) : ''
        return (
          <button
            key={tab}
            type="button"
            class={`app-tab${chosen ? ' is-current' : ''}`}
            {...(chosen ? { 'aria-current': 'page' as const } : {})}
            {...(badge ? { 'aria-label': badgeLabel(TAB_LABELS[tab], arriving) } : {})}
            onClick={() => onSelect(tab)}
          >
            <span class="app-tab-art">
              <Icon class="app-tab-icon" />
              {badge && (
                <span class="app-tab-badge" aria-hidden="true">
                  {badge}
                </span>
              )}
            </span>
            <span class="app-tab-label">{TAB_LABELS[tab]}</span>
          </button>
        )
      })}
    </nav>
  )
}
