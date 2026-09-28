import { render } from 'preact'

import { PlayerApp } from './PlayerApp'

/**
 * Entry point for the player at /player/ - a page of its own, built beside the main interface's
 * bundle (see ui/vite.config.ts) and sharing its components' code but none of its page.
 */
const host = document.getElementById('player-root')

if (host) render(<PlayerApp />, host)
else console.warn('deadwax player: no #player-root in the page')
