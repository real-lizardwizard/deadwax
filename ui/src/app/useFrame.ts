import { useEffect, useState } from 'preact/hooks'

import { COLUMN_QUERY, DESKTOP_QUERY, frameOf, type FrameState } from '../lib/appFrame'

/** What the two media queries say now; the phone's frame where the page can't ask. */
function readFrame(): FrameState {
  const matches = (query: string) => {
    try {
      return typeof window.matchMedia === 'function' && window.matchMedia(query).matches
    } catch {
      return false
    }
  }
  return frameOf(matches(DESKTOP_QUERY), matches(COLUMN_QUERY))
}

/**
 * The frame the app is drawn in (2.0.0-player.19, lib/appFrame.ts): the phone's or the desktop's,
 * and how a side panel is drawn - followed as the window is resized or a tablet turned. The same
 * media queries the stylesheets use (app-desktop.css), asked through matchMedia, so the markup and
 * the styles always agree about which frame this is. A new state only when something changed: a
 * resize within one frame re-renders nothing.
 *
 * Called by App, which is never unmounted, so choosing a frame swaps the chrome around the pages and
 * never the engine. (MediaQueryList's addEventListener is iOS 14's; addListener before it.)
 */
export function useFrame(): FrameState {
  const [frame, setFrame] = useState<FrameState>(readFrame)

  useEffect(() => {
    if (typeof window.matchMedia !== 'function') return
    const lists = [DESKTOP_QUERY, COLUMN_QUERY].map((query) => window.matchMedia(query))
    const onChange = () =>
      setFrame((was) => {
        const now = readFrame()
        return now.frame === was.frame && now.panel === was.panel ? was : now
      })
    for (const list of lists) {
      if (typeof list.addEventListener === 'function') list.addEventListener('change', onChange)
      else list.addListener(onChange)
    }
    //? a change between the first render and this effect
    onChange()
    return () => {
      for (const list of lists) {
        if (typeof list.removeEventListener === 'function') list.removeEventListener('change', onChange)
        else list.removeListener(onChange)
      }
    }
  }, [])

  return frame
}
