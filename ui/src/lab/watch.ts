/**
 * Whether the page was hidden while something ran (2.0.0-player.36) - a run of "Turn it for me", a
 * recording, a run of "Check this device". A hidden page (a locked screen, another app or tab) has the
 * deck suspend its sound and the browser hold back the page's timers, so what was recorded then is half a
 * run, and nothing to measure: the bench throws it away and says why, rather than listing it as if whole
 * (review of 2.0.0-player.36). Latched: once hidden, hidden, though it shows again.
 */

export interface HideWatch {
  /** whether the page was hidden at any moment since the watch began */
  readonly hidden: boolean
  stop(): void
}

type Page = Pick<Document, 'visibilityState' | 'addEventListener' | 'removeEventListener'>

/** Watch the page from now: `onHide` is told the first time it is hidden. */
export function watchForHide(onHide?: () => void, page: Page = document): HideWatch {
  let hidden = page.visibilityState === 'hidden'
  const changed = () => {
    if (hidden || page.visibilityState !== 'hidden') return
    hidden = true
    onHide?.()
  }
  page.addEventListener('visibilitychange', changed)
  return {
    get hidden() {
      return hidden
    },
    stop: () => page.removeEventListener('visibilitychange', changed),
  }
}
