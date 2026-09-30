import { render } from 'preact'

import { App } from '../app/App'

/**
 * Entry point for the app at /player/ - a page of its own, built beside the main interface's
 * bundle (see ui/vite.config.ts) and sharing its components' code but none of its page. Since
 * 2.0.0-player.9 it is the one app - five tabs with the player inside them (ui/src/app/) - grown
 * in place at /player/, so the home-screen app James installed, and its settings, carry on.
 */
const host = document.getElementById('player-root')

if (host) render(<App />, host)
else console.warn('deadwax: no #player-root in the page')
