import type { ComponentChildren } from 'preact'

import type { NavidromeStatus } from '../player/api'
import { DOWN, OFFLINE, OFFLINE_RETRY, TELL } from '../lib/errorWords'
import { accessNow, seesDetail } from './access'
import { setUpNavidrome } from './navidromeSetUp'

/** Why the gate is there, said when Navidrome isn't set up - followed by how to set it up. */
export const NAVIDROME_REQUIRED = "deadwax needs Navidrome for your library: the app shows and plays the albums Navidrome "
  + "lists, through deadwax - so the phone never needs Navidrome's password."

/** ...and when it is set up but can't be reached, above Try again. */
export const NAVIDROME_UNREACHED = 'Your library comes from Navidrome, so it shows here once deadwax can reach it.'

/**
 * (2.0.4) What a listener reads in the gate's place - someone who doesn't run deadwax (access.ts seesDetail), who
 * can do nothing about Navidrome's address or its password: what is wrong in their words, and what they can do.
 * Navidrome's own words, and Set up Navidrome, are for whoever runs it.
 */
export const MUSIC_UNAVAILABLE = "Your music isn't available right now"
export const MUSIC_NOT_YET = "Your music isn't available yet"
//? above the gate's own Try again: the advice leaves trying again to it
export const MUSIC_UNREACHED = `${DOWN.music} If it keeps happening, tell whoever runs deadwax.`
/** ...when it was deadwax itself that didn't answer (lib/navidromeCheck.ts offline): the music server may be fine */
export const DEADWAX_UNREACHED = `${OFFLINE} ${OFFLINE_RETRY}`
export const MUSIC_UNSET = `deadwax hasn't been connected to a music server yet. ${TELL}`
/** someone with Settings and the log, who isn't an admin: Navidrome's rows are an admin's alone (routes/settings.py) */
export const ADMIN_SETS_UP = 'An admin can set it up in Server settings (Connections).'

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
 * so the words under the reason say so, and how to set it up - "in deadwax's settings", true of
 * Server settings, where the button opens (it was true of the main page's settings tab too). A folder on
 * disk that Navidrome doesn't list is never out of reach: Needs a look raises it ("Not in Navidrome").
 *
 * A leaf: the status and the retry come from App, which asks Navidrome once for every gate. Not set
 * up, its "Set up Navidrome" opens the app's own Server settings at Connections, on every frame
 * (2.0.0-player.47, navidromeSetUp.ts - it pointed at the main page's settings tab until then).
 *
 * IN A LISTENER'S WORDS (2.0.4): all of the above is for whoever runs deadwax - an admin, or someone given
 * Settings and the log (access.ts seesDetail) - and Set up Navidrome for an admin alone. Everyone else reads
 * MUSIC_UNAVAILABLE / MUSIC_NOT_YET and what they can do: try again, or tell whoever runs deadwax - never
 * Navidrome's address, its error, or a setting's name.
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
  //? (2.0.4) read, not watched: App draws the gate again with every status, and what /me says changes it rarely - a
  //? leaf with no hooks, as the sims call it
  const access = accessNow()
  const runs = seesDetail(access)

  if (status && !runs) {
    return (
      <section class="app-needs">
        {title && (
          <header class="pl-large-header">
            <h1 class="pl-large-title">{title}</h1>
          </header>
        )}
        <div class="app-needs-body">
          <h2 class="app-needs-title">{status.configured ? MUSIC_UNAVAILABLE : MUSIC_NOT_YET}</h2>
          <p class="app-needs-text">{status.offline ? DEADWAX_UNREACHED : status.configured ? MUSIC_UNREACHED : MUSIC_UNSET}</p>
          {status.configured && (
            <button type="button" class="app-button" onClick={onRetry}>
              Try again
            </button>
          )}
        </div>
      </section>
    )
  }

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
            <>
              <p class="app-needs-text">
                {NAVIDROME_REQUIRED} {access.admin ? "Set it up in deadwax's settings (Connections), then come back." : ADMIN_SETS_UP}
              </p>
              {/* (2.0.4) an admin's: Navidrome's rows in Server settings are theirs alone */}
              {access.admin && (
                <button type="button" class="app-button app-needs-setup" onClick={setUpNavidrome}>
                  Set up Navidrome
                </button>
              )}
            </>
          )}
        </div>
      )}
    </section>
  )
}
