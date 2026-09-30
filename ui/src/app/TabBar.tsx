import type { FunctionComponent } from 'preact'

import { TAB_LABELS, TABS, type Tab } from '../lib/appRoutes'
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
 */
export function TabBar({ current, onSelect }: { current: Tab; onSelect: (tab: Tab) => void }) {
  return (
    <nav class="app-tabbar" aria-label="Sections">
      {TABS.map((tab) => {
        const Icon = ICONS[tab]
        const chosen = tab === current
        return (
          <button
            key={tab}
            type="button"
            class={`app-tab${chosen ? ' is-current' : ''}`}
            {...(chosen ? { 'aria-current': 'page' as const } : {})}
            onClick={() => onSelect(tab)}
          >
            <Icon class="app-tab-icon" />
            <span class="app-tab-label">{TAB_LABELS[tab]}</span>
          </button>
        )
      })}
    </nav>
  )
}
