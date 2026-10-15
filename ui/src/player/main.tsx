import { render } from 'preact'

import { loginsOn } from '../api/auth'
import { App } from '../app/App'
import { reloadWhenLoginsComeOn, startWithLogins } from '../app/signInGate'

/**
 * Entry point for the app at /player/ - a page of its own, built beside the main interface's
 * bundle (see ui/vite.config.ts) and sharing its components' code but none of its page. Since
 * 2.0.0-player.9 it is the one app - five tabs with the player inside them (ui/src/app/) - grown
 * in place at /player/, so the home-screen app James installed, and its settings, carry on.
 *
 * With logins on (2.0.0-player.48 - the page says so, api/auth.ts) the sign-in gate decides when the
 * app is drawn (app/signInGate.tsx); with them off it is drawn at once, as it always was - and loaded
 * again if logins are switched on under it (its first 401: reloadWhenLoginsComeOn).
 */
const host = document.getElementById('player-root')

if (!host) console.warn('deadwax: no #player-root in the page')
else if (loginsOn()) startWithLogins(host)
else {
  render(<App />, host)
  reloadWhenLoginsComeOn()
}
