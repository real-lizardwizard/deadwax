import { render } from 'preact'

import { Bench } from './Bench'

/**
 * Entry point for the turntable's test bench at /player/lab/ (2.0.0-player.36): a page of its own beside
 * the app, built as the `deadwax-lab` entry (ui/vite.config.ts). Not on any tab and not in the manifest -
 * Info > Debug links to it, opening beside the app.
 */
const host = document.getElementById('lab-root')

if (host) render(<Bench />, host)
else console.warn('deadwax: no #lab-root in the page')
