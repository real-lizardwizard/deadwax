import type { ComponentChildren } from 'preact'

import type { NavidromeStatus } from '../player/api'

/** Why the gate is there, said when Navidrome isn't set up - followed by how to set it up. */
export const NAVIDROME_REQUIRED = "deadwax needs Navidrome for your library: the app shows and plays the albums Navidrome "
  + "lists, through deadwax - so the phone never needs Navidrome's password."

/** ...and when it is set up but can't be reached, above Try again. */
export const NAVIDROME_UNREACHED = 'Your library comes from Navidrome, so it shows here once deadwax can reach it.'

/**
 * The Navidrome gate, drawn only INSIDE the parts that play from Navidrome - Home's shelf and the
 * Library tab, the album pages on them included. Before 2.0.0-player.9 the whole player waited on
 * it; now the tab bar, You, Search and Requests work with Navidrome unset or down, since nothing
 * in them needs it.
 *
 * Until the status is known it shows a spinner; then either what it guards, or why not and what to
 * do about it - the titles the player always used, which troubleshooting.md quotes.
 *
 * NAVIDROME IS REQUIRED FOR THE LIBRARY (2.0.0-player.46): the app's library is what Navidrome lists,
 * so the words under the reason say so, and how to set it up - "in deadwax's settings", true of the
 * main page's settings tab the link opens today and of wherever the settings live next. A folder on
 * disk that Navidrome doesn't list is never out of reach: Needs a look raises it ("Not in Navidrome").
 *
 * A leaf: the status and the retry come from App, which asks Navidrome once for every gate. Its
 * link to the settings tab opens beside the app, like every link out of it (app-rules.sim.cjs).
 */
export function NeedsNavidrome({
  status,
  onRetry,
  title,
  children,
}: {
  status: NavidromeStatus | null
  onRetry: () => void
  /** a large title to draw above the reason, where what it guards would have drawn its own */
  title?: string
  children: ComponentChildren
}) {
  if (status?.ok) return <>{children}</>

  return (
    <section class="app-needs">
      {title && (
        <header class="pl-large-header">
          <h1 class="pl-large-title">{title}</h1>
        </header>
      )}
      {!status ? (
        <div class="pl-spinner" aria-label="Connecting" />
      ) : (
        <div class="app-needs-body">
          <h2 class="app-needs-title">{status.configured ? "Can't reach Navidrome" : 'Connect Navidrome'}</h2>
          <p class="app-needs-text">{status.problem}</p>
          {status.configured ? (
            <>
              <p class="app-needs-text">{NAVIDROME_UNREACHED}</p>
              <button type="button" class="app-button" onClick={onRetry}>
                Try again
              </button>
            </>
          ) : (
            <p class="app-needs-text">
              {NAVIDROME_REQUIRED} Set it up in deadwax's <a href="/" target="_blank" rel="noopener">settings</a> (Connections),
              then come back.
            </p>
          )}
        </div>
      )}
    </section>
  )
}
