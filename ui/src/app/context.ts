import { createContext } from 'preact'
import { useContext } from 'preact/hooks'

import type { Player } from '../player/usePlayer'

/**
 * The player, handed down from App - the one place usePlayer() is called (ui/test/app-rules.sim.cjs
 * holds it there). The engine makes ONE audio element for the page's life in its useMemo, so it
 * must live in a component that never unmounts: a tab calling it would make a second element, and
 * iOS unlocks audio per element, from a tap.
 *
 * Two contexts, on purpose. `PlayerContext` is the whole player, a new object on every change of
 * `playing`, `buffering` or the queue, so whatever reads it re-renders then. `ActionsContext` is
 * only the engine's actions, which never change: a heavy screen that only needs to START playback
 * reads that one and is left alone while the music plays.
 *
 * Only pages read these. A leaf component takes what it needs as props, which is what lets the
 * fake-Preact sims render one without a provider.
 */
export const PlayerContext = createContext<Player | null>(null)

/** What can be done to the player, without what it is doing - stable for the page's life. */
export type PlayerActions = Pick<
  Player,
  'playTracks' | 'toggle' | 'next' | 'previous' | 'seek' | 'showAirPlay' | 'setGapless' | 'setMaxRate'
>

export const ActionsContext = createContext<PlayerActions | null>(null)

/**
 * The actions out of the player, for ActionsContext. It names them and calls none: every one of
 * them must still be called straight from a tap (play() in the same turn as the gesture), by the
 * screen the tap is on - see "The one app" in CLAUDE.md.
 */
export function pickActions(player: Player): PlayerActions {
  return {
    playTracks: player.playTracks,
    toggle: player.toggle,
    next: player.next,
    previous: player.previous,
    seek: player.seek,
    showAirPlay: player.showAirPlay,
    setGapless: player.setGapless,
    setMaxRate: player.setMaxRate,
  }
}

/** For a page: the player, which App always provides. */
export function usePlayerState(): Player {
  const player = useContext(PlayerContext)
  if (!player) throw new Error('deadwax: a page read the player outside App')
  return player
}

/** For a page: the player's actions, which never change. */
export function usePlayerActions(): PlayerActions {
  const actions = useContext(ActionsContext)
  if (!actions) throw new Error("deadwax: a page read the player's actions outside App")
  return actions
}
