import { useCallback, useEffect, useRef, useState } from 'preact/hooks'

import type { SongLyrics } from '../api/types'
import { isAbort, latestOnly } from '../lib/latest'
import { asksAhead, keepLyrics, keptLyrics } from '../lib/lyricsView'
import { songLyrics } from '../player/api'
import type { Player } from '../player/usePlayer'

/**
 * The song playing's lyrics (2.1.6, notes/app-lyrics.md 2.6), as App keeps them for Now Playing's Lyrics and the
 * desktop's Lyrics panel. Called once, in App.
 *
 *  - ASKED AT EVERY SONG CHANGE, on both frames, Now Playing open or not - one small ask a song (a 304 for one asked
 *    before, the route sends an ETag), and it buys the right button the moment Now Playing opens: asked only on
 *    opening, the button would start enabled and dim a moment later for an instrumental, and lyrics left on would
 *    open on a spinner. The desktop's bar shows its Lyrics all the time, dimmed for a song with none.
 *  - NEVER WHILE THE PAGE IS HIDDEN (a locked phone asks nothing): a song changing then is asked for when the page
 *    shows again, if its answer isn't in hand - and so is one whose ask failed, and again at the next opening of the
 *    lyrics (a failed ask keeps nothing).
 *  - THE NEXT SONG'S too, while the lyrics show, once the song playing has NEXT_LYRICS_S left - so they are in hand at
 *    the join. Read off the position's listener, never its state: nothing here re-renders App as the song plays.
 *  - KEPT IN MEMORY, the last LYRICS_KEPT songs' answers, the least recently used going first - drawn at once while
 *    the ask (a 304, usually) is on its way. Never stored.
 *  - ONLY THE NEWEST ANSWER DRAWS (lib/latest.ts): a song changing mid-ask never draws the last one's words.
 */
export interface SongLyricsState {
  /** the song these are for - the song playing's id; null with nothing playing */
  song: string | null
  /** its answer in hand, kept or just come; null while there is none */
  lyrics: SongLyrics | null
  /** an ask is on its way */
  asking: boolean
  /** the last ask's failure (null when it didn't fail) - drawn only while no answer is in hand */
  error: unknown
}

export interface LyricsAnswers extends SongLyricsState {
  /** ask again: Try again */
  retry: () => void
}

const NOTHING: SongLyricsState = { song: null, lyrics: null, asking: false, error: null }

export function useLyrics(
  player: Pick<Player, 'track' | 'queue' | 'duration' | 'onPosition'>,
  /** the lyrics are on screen: Now Playing open with Lyrics on, or the desktop's panel open */
  showing: boolean,
  /** the page is showing (App's usePageShown) */
  shown: boolean,
): LyricsAnswers {
  const song = player.track?.id ?? null
  const kept = useRef(new Map<string, SongLyrics>())
  const latest = useRef(latestOnly())
  const ahead = useRef(latestOnly())
  const askedAhead = useRef<string | null>(null)
  const [state, setStateShown] = useState<SongLyricsState>(NOTHING)
  //? what is drawn, read in the effects without being one of their reasons to run
  const now = useRef(state)
  const setState = (next: SongLyricsState) => {
    now.current = next
    setStateShown(next)
  }
  //? the queue and the length as they are when the position's listener hears a tick
  const playing = useRef(player)
  playing.current = player

  const ask = useCallback((id: string) => {
    const ticket = latest.current.begin()
    //? a kept answer draws at once, while its ask (a 304, usually) is on its way
    const inHand = keptLyrics(kept.current, id)
    setState({ song: id, lyrics: inHand, asking: true, error: null })
    songLyrics(id, ticket.signal).then(
      (lyrics) => {
        keepLyrics(kept.current, id, lyrics)
        if (ticket.current()) setState({ song: id, lyrics, asking: false, error: null })
      },
      (error: unknown) => {
        if (!ticket.current() || isAbort(error)) return
        //? a failed ask keeps nothing - the answer in hand, if any, is still drawn: a revalidation that failed is no news
        setState({ song: id, lyrics: inHand, asking: false, error })
      },
    )
  }, [])

  useEffect(() => {
    if (song === null) {
      latest.current.supersede()
      setState(NOTHING)
      return
    }
    const was = now.current
    const changed = was.song !== song
    if (!shown) {
      //? a locked phone asks nothing: what is kept of the new song is drawn, and it is asked for once the page shows
      if (changed) {
        latest.current.supersede()
        setState({ song, lyrics: keptLyrics(kept.current, song), asking: false, error: null })
      }
      return
    }
    //? a new song; or this one with no answer in hand and none on its way - the page shown again, or the lyrics
    //? opened again after a failure
    if (changed || (!was.lyrics && !was.asking)) ask(song)
  }, [song, shown, showing])

  //? the next song's, while the lyrics show and the page is in view, once the song playing is near its end
  useEffect(() => {
    if (!showing || !shown) return
    return player.onPosition((seconds) => {
      const { queue, duration } = playing.current
      const next = queue.tracks[queue.index + 1]
      if (!next || !asksAhead(seconds, duration)) return
      if (askedAhead.current === next.id || kept.current.has(next.id)) return
      askedAhead.current = next.id
      const id = next.id
      const ticket = ahead.current.begin()
      songLyrics(id, ticket.signal).then(
        (lyrics) => keepLyrics(kept.current, id, lyrics),
        //? nothing to say: the join asks for them again
        () => undefined,
      )
    })
  }, [showing, shown, player.onPosition])

  const retry = useCallback(() => {
    if (song !== null) ask(song)
  }, [song])

  //? never another song's answer under this one's id, even for the one render before the effect above runs - what
  //? is kept of the new one draws in it, and the ask the effect is about to make is as good as on its way
  const mine: SongLyricsState = state.song === song
    ? state
    : { song, lyrics: song === null ? null : kept.current.get(song) ?? null, asking: song !== null && shown, error: null }
  return { ...mine, retry }
}
