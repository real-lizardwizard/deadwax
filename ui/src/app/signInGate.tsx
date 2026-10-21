import { render } from 'preact'

import { onSignedOut } from '../api/auth'
import { ApiError, newSession } from '../api/http'
import { me, type Me } from '../api/me'
import { latestOnly } from '../lib/latest'
import { afterSignIn, returnTarget, signInProblem } from '../lib/signIn'
import { App } from './App'
import { noteAccess } from './access'
import { sessionMe, setSessionMe } from './session'
import { SignIn } from './SignIn'

/**
 * The app with logins on (2.0.0-player.48) - player/main.tsx hands over here only when the page says
 * logins are on (api/auth.ts loginsOn); off, it draws the app at once, exactly as before.
 *
 * - FIRST, WHO: `/deadwax/me` is asked before anything is drawn. Signed in, the app is drawn - knowing
 *   already whether this is an admin (session.ts), so a user never sees an admin's rows for a moment.
 *   Signed out (a 401), the sign-in screen is drawn ALONE, and the app only once someone has signed in:
 *   it would only have asked for everything to be told no.
 * - A SESSION ENDING MID-USE - any 401, from any request (api/http.ts says so as an event) - brings the
 *   sign-in screen back OVER the app: the app is left mounted and made inert under it, so nothing it
 *   holds is lost and the song playing plays on as far as the device already has it. A 401 for a request
 *   sent BEFORE the latest sign-in isn't one (api/http.ts `newSession`, called as the screen goes): it
 *   was sent with the cookie that sign-in replaced. The same person signing in again carries on where
 *   they were - focus back where it was; someone else signing in starts the app again, since what it
 *   holds - the pins, Getting albums, the queue - was the other's.
 * - THE PLAYER'S OWN REQUESTS don't go through api/http.ts - the audio element fetches its song itself,
 *   and the gapless stream with fetch - so a song that fails to load (a media element's `error`, heard
 *   here as it passes the document) asks who is signed in: a 401 then brings the sign-in screen up as the
 *   first song fails, not at the next tap. What the player does with songs it can't fetch is the
 *   engine's (untouched): it tries each once more and skips on, to the end of the queue.
 * - Who is asked again as the page comes back to the front, and as the browser shows a page it kept
 *   (Back) - never on a timer: a session the re-check ended while the phone was in a pocket shows the
 *   sign-in as it is picked up, and a sign-in screen left showing after signing in elsewhere (another
 *   tab, or Back to this one) goes, as /me now answers.
 * - The sign-in coming up leaves full screen (the desktop visualizer's): nothing outside a full-screen
 *   element shows (leaveFullScreen).
 * - Nothing here plays anything: the sign-in screen's one button signs in, and the app's own buttons are
 *   where playback starts, in their taps - as ever.
 * - `/player/?return=/` (the main page's "Sign in", components/SignedOutNotice.tsx) goes back to the main
 *   page once signed in - and to nowhere else (lib/signIn.ts returnTarget) - REPLACING this page in the
 *   history, so Back from the main page doesn't land on a sign-in that is already done.
 */
/**
 * Leave full screen, if anything is in it, and call `left` once the browser has. The desktop visualizer
 * takes the whole screen with requestFullscreen on its own element (player/Visualizer.tsx), which puts
 * it in the browser's top layer: nothing drawn outside it shows there - the sign-in screen included,
 * whatever its z-index - and the browser keeps everything outside it inert, so the name field's focus
 * doesn't take. So a session ending under it left the sign-in hidden behind a visualizer whose songs
 * failed one after another (found in review). Leaving full screen closes the visualizer (its own
 * fullscreenchange), and the sign-in shows; `left` then puts focus in it.
 */
function leaveFullScreen(left: () => void): void {
  const page = document as Document & { webkitFullscreenElement?: Element | null; webkitExitFullscreen?: () => void }
  if (!(page.fullscreenElement ?? page.webkitFullscreenElement)) return
  const gone = () => {
    if (page.fullscreenElement ?? page.webkitFullscreenElement) return
    page.removeEventListener('fullscreenchange', gone)
    page.removeEventListener('webkitfullscreenchange', gone)
    left()
  }
  page.addEventListener('fullscreenchange', gone)
  page.addEventListener('webkitfullscreenchange', gone)
  try {
    const leaving = page.exitFullscreen ? page.exitFullscreen() : page.webkitExitFullscreen?.()
    ;(leaving as Promise<void> | undefined)?.catch?.(() => undefined)
  } catch {
    // already left
  }
}

export function startWithLogins(host: HTMLElement): void {
  const layer = document.createElement('div')
  layer.id = 'signin-root'
  document.body.appendChild(layer)
  let appShown = false
  let signInShown = false
  //? what had focus in the app as the sign-in came over it, to give it back when the same person carries on
  let focusBefore: HTMLElement | null = null
  const asks = latestOnly()

  const signedIn = (who: Me) => {
    const before = sessionMe()?.user ?? null
    setSessionMe(who)
    //? (2.0.0-player.61 review) every answer the gate has - coming back to the front, a song failing, a sign-in
    //? again - is what the app draws by too (access.ts): an admin's change reaches a desktop, which asks /me
    //? nowhere else, without a reload
    noteAccess(who)
    const back = returnTarget(location.search)
    if (back) {
      location.replace(back)
      return
    }
    if (appShown && afterSignIn(before, who.user) === 'start-again') {
      location.reload()
      return
    }
    if (signInShown) {
      signInShown = false
      newSession()
      render(null, layer)
      document.documentElement.classList.remove('has-signin')
      host.inert = false
      host.removeAttribute('aria-hidden')
      const restore = focusBefore
      focusBefore = null
      if (restore?.isConnected) restore.focus({ preventScroll: true })
    }
    if (!appShown) {
      appShown = true
      render(<App />, host)
    }
  }

  const showSignIn = (reason: string | null) => {
    asks.supersede()
    if (signInShown) return
    signInShown = true
    if (appShown) {
      const active = document.activeElement as HTMLElement | null
      focusBefore = active && active !== document.body && typeof active.focus === 'function' ? active : null
      host.inert = true
      host.setAttribute('aria-hidden', 'true')
    }
    document.documentElement.classList.add('has-signin')
    render(<SignIn reason={reason} onSignedIn={signedIn} />, layer)
    leaveFullScreen(() => {
      if (signInShown) layer.querySelector<HTMLElement>('input')?.focus({ preventScroll: true })
    })
  }

  onSignedOut(showSignIn)

  const ask = () => {
    const request = asks.begin()
    me(request.signal).then(
      (who) => {
        //? signed in - also when the sign-in screen shows: someone signed in elsewhere (another tab, or
        //? this page before Back brought it again), and it goes as a sign-in here would
        if (request.current()) signedIn(who)
      },
      (error: unknown) => {
        if (!request.current() || appShown) return
        //? a 401 has already brought the sign-in up (api/http.ts); anything else - deadwax down, logins
        //? that can't work - is said there too, and signing in is the way to try again
        showSignIn(error instanceof ApiError && error.status === 401 ? error.detail : signInProblem(error))
      },
    )
  }

  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible' && (appShown || signInShown)) ask()
  })
  //? the browser showing this page again from its back-forward cache, as it was - who may have changed
  globalThis.addEventListener('pageshow', (event) => {
    if ((event as PageTransitionEvent).persisted && (appShown || signInShown)) ask()
  })
  //? a song that failed to load: media errors don't bubble, but they pass the document on the way in
  //? (the player puts its audio elements in the page)
  document.addEventListener(
    'error',
    (event) => {
      const media = typeof HTMLMediaElement !== 'undefined' && event.target instanceof HTMLMediaElement
      if (media && appShown && !signInShown) ask()
    },
    true,
  )
  ask()
}

//? the tab's note of the last reload below, and how long it holds off another
const RELOADED_KEY = 'deadwax-reloaded-for-logins'
export const RELOAD_AGAIN_MS = 60_000

/**
 * The app drawn with logins OFF (player/main.tsx, no mark in the page): a 401 can only mean they have
 * been switched on since this page loaded. AUTH_MODE is the environment's, so the container was
 * recreated under a page kept open - the home-screen app iOS held in memory, a tab left open - which
 * has no gate to bring the sign-in up, so everything it asked for failed with "Sign in" and nothing
 * else changed until the app was killed (found in review). The page is loaded again instead, once: the
 * page that comes back carries the mark and starts at the sign-in. With logins off nothing answers
 * 401, so until they come on this does nothing at all.
 *
 * Not again within a minute of the last time (noted for the tab, where the browser keeps it - it may
 * not, and then the page reloads regardless), so something else answering 401 to the app's requests
 * but not to its page - a proxy in front - can't set it reloading over and over.
 */
export function reloadWhenLoginsComeOn(): () => void {
  const stop = onSignedOut(() => {
    stop()
    if (!reloadedLately(Date.now())) location.reload()
  })
  return stop
}

function reloadedLately(now: number): boolean {
  try {
    const last = Number(sessionStorage.getItem(RELOADED_KEY))
    if (last > 0 && now - last >= 0 && now - last < RELOAD_AGAIN_MS) return true
    sessionStorage.setItem(RELOADED_KEY, String(now))
  } catch {
    // storage refused: reload regardless - logins coming on is what a 401 here is
  }
  return false
}
