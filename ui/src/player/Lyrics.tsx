import { useEffect, useLayoutEffect, useMemo, useRef, useState } from 'preact/hooks'

import type { LyricLine } from '../api/types'
import { errorNote } from '../app/ErrorNote'
import type { LyricsAnswers } from '../app/useLyrics'
import { errorKind } from '../lib/errorWords'
import { lyricTime } from '../lib/lyrics'
import {
  FOLLOW_AGAIN_MS, LOADING_LYRICS, LYRICS, LYRICS_FAILED, NO_LYRICS, NOT_SYNCED, NOTHING_PLAYING, SCROLL_KEYS, SONG_GONE,
  clockRuns, endRoom, follows, followTop, lineAfterKey, litAt, lyricsClock, sameLit, sung, tabStop, withIntro, type Lit,
} from '../lib/lyricsView'
import type { Player } from './usePlayer'

const NOT_LIT: Lit = { range: null, dots: 0 }
const NO_LINES: readonly LyricLine[] = []
const DOTS = [1, 2, 3] as const

/** Reduce Motion asked for: following jumps rather than scrolls. Read as it scrolls, so a change applies at once. An
 *  explicit 'smooth' would override the theme's `scroll-behavior: auto !important` for it, so it is asked here. */
function reducedMotion(): boolean {
  return typeof matchMedia === 'function' && matchMedia('(prefers-reduced-motion: reduce)').matches
}

/** Whether the page is in view: the clock stands on a locked phone, or with the page in the background. */
function usePageVisible(): boolean {
  const [visible, setVisible] = useState(() => document.visibilityState !== 'hidden')
  useEffect(() => {
    const onChange = () => setVisible(document.visibilityState !== 'hidden')
    document.addEventListener('visibilitychange', onChange)
    return () => document.removeEventListener('visibilitychange', onChange)
  }, [])
  return visible
}

/**
 * The song's lyrics as it plays (2.1.6, notes/app-lyrics.md 3.2-3.3, 3.6) - one view, drawn in the cover's place on a
 * phone's Now Playing and as the body of a desktop's Lyrics panel (app/LyricsPanel.tsx). Its answers are App's
 * (app/useLyrics.ts); its rules lib/lyricsView.ts's.
 *
 *  - THE LIT LINE is the song's, judged once a frame by lyricsClock() while the lyrics show, the song plays, nothing is
 *    over them and the page is in view - and redrawn only when it (or a break's dots) changes. Stopped, it is redrawn
 *    from the player's reported position alone, so a seek while paused lights its line. Nothing announced as lines
 *    change: no live region.
 *  - FOLLOWING: the lit line is scrolled to LYRICS_ANCHOR of the view's height - smoothly, or a jump for Reduce
 *    Motion. The listener's own wheel, touch, scroll key or scroll bar holds it, and it comes back FOLLOW_AGAIN_MS after
 *    the last such input while the song plays - a timer, not the clock; paused, it stays put until the song plays.
 *    Keyboard focus in the lines holds it too, while there and for FOLLOW_AGAIN_MS after it leaves - never focus a tap
 *    or a click put there (Chromium focuses a clicked button), which would stop following for good after a click. A new
 *    song starts at its top, and opening the lyrics and a change of size follow at once, without a scroll.
 *  - A TAP ON A LINE plays from it: its seek, and the player's toggle when paused - both in the tap, nothing awaited
 *    (the gesture rule: ui/test/app-rules.sim.cjs allows this file `toggle`, the one place both frames' taps go
 *    through), and following comes back on that line at once.
 *  - ONE TAB STOP: a roving tabIndex on the lit line (else the first), Up and Down to the line sung before or after,
 *    Home and End; Enter and Space play from the line (a button's own).
 */
export function Lyrics({
  player,
  answers,
  shows,
  covered,
  place,
}: {
  player: Pick<Player, 'track' | 'playing' | 'position' | 'onPosition' | 'seek' | 'toggle'>
  /** the song playing's lyrics, App's (app/useLyrics.ts) */
  answers: LyricsAnswers
  /** they are on screen: Now Playing open, or the panel open */
  shows: boolean
  /** something is over them: Up Next, Info or the menu over Now Playing; the visualizer over the panel */
  covered: boolean
  /** a phone's Now Playing, in the cover's place - or a desktop's side panel */
  place: 'face' | 'panel'
}) {
  const visible = usePageVisible()
  const lyrics = answers.lyrics
  const synced = !!lyrics && lyrics.synced && lyrics.lines.length > 0
  const lines = useMemo(() => (lyrics ? (lyrics.synced ? withIntro(lyrics.lines) : lyrics.lines) : NO_LINES), [lyrics])
  const scroller = useRef<HTMLElement>(null)
  const list = useRef<HTMLOListElement>(null)
  const [lit, setLitShown] = useState<Lit>(NOT_LIT)
  const litNow = useRef(lit)
  //? the view's height, for the room after the last line (so it, too, can reach the anchor)
  const [height, setHeight] = useState(0)
  //? the line focus is on (the tab stop follows it), and whether it is the keyboard's - which holds following
  const [focusAt, setFocusAt] = useState<number | null>(null)
  const focused = useRef(false)
  const pointered = useRef(false)
  //? when the listener last scrolled the lyrics themselves (performance.now()), null while following
  const heldAt = useRef<number | null>(null)
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null)
  //? the player's last reported position - a seek's target until it lands (lib/scrub reportedPosition)
  const reported = useRef(player.position())
  //? what the listeners and the timer read: this render's
  const live = useRef({ player, lines, synced })
  live.current = { player, lines, synced }

  const draw = (t: number) => {
    const next = live.current.synced ? litAt(live.current.lines, t) : NOT_LIT
    if (sameLit(next, litNow.current)) return
    litNow.current = next
    setLitShown(next)
  }
  const clock = () => lyricsClock(live.current.player.position(), reported.current)
  const followsNow = () => follows(performance.now(), heldAt.current, live.current.player.playing, focused.current)

  //? the lit line to the anchor - the top before the first line (an intro too short for its dots)
  const follow = (smooth: boolean) => {
    const box = scroller.current
    const range = litNow.current.range
    if (!box) return
    const line = range ? (list.current?.children[range.first] as HTMLElement | undefined) : undefined
    const top = line ? followTop(line.offsetTop, box.clientHeight) : 0
    box.scrollTo({ top, behavior: smooth && !reducedMotion() ? 'smooth' : 'auto' })
  }

  const stopTimer = () => {
    if (timer.current !== null) clearTimeout(timer.current)
    timer.current = null
  }
  //? FOLLOW_AGAIN_MS after the last input (or focus leaving), following comes back - if the song plays
  const comeBack = () => {
    timer.current = null
    const held = heldAt.current
    if (held === null) return
    const left = FOLLOW_AGAIN_MS - (performance.now() - held)
    if (left > 0) {
      timer.current = setTimeout(comeBack, left)
      return
    }
    if (!followsNow()) return
    heldAt.current = null
    follow(true)
  }
  const hold = () => {
    heldAt.current = performance.now()
    stopTimer()
    timer.current = setTimeout(comeBack, FOLLOW_AGAIN_MS)
  }

  //? a new song: its lines from their top, following on - before the paint. No seek is on its way in a song just
  //? begun, so the clock starts from where the player says the new song is
  useLayoutEffect(() => {
    heldAt.current = null
    stopTimer()
    reported.current = live.current.player.position()
    draw(clock())
    if (scroller.current) scroller.current.scrollTop = 0
  }, [answers.song])

  //? its answer come (or come again): the lit line, followed at once if following
  useLayoutEffect(() => {
    draw(clock())
    if (followsNow()) follow(false)
  }, [lines])

  //? the lyrics opened again: following, at once
  const wasShowing = useRef(shows)
  useLayoutEffect(() => {
    const opened = shows && !wasShowing.current
    wasShowing.current = shows
    if (!opened) return
    heldAt.current = null
    stopTimer()
    reported.current = live.current.player.position()
    draw(clock())
    follow(false)
  }, [shows])

  //? the reported position, while they show: a seek's target (and, stopped, the one redraw)
  useEffect(() => {
    if (!shows) return
    reported.current = live.current.player.position()
    return player.onPosition((seconds) => {
      reported.current = seconds
      draw(clock())
    })
  }, [shows, player.onPosition])

  //? the clock, once a frame - only while it runs
  const runs = synced && clockRuns({ shows, playing: player.playing, covered, visible })
  useEffect(() => {
    if (!runs) return
    let frame = requestAnimationFrame(function tick() {
      draw(clock())
      frame = requestAnimationFrame(tick)
    })
    return () => cancelAnimationFrame(frame)
  }, [runs])

  //? a new lit line, followed smoothly - unless the listener holds the lyrics
  useLayoutEffect(() => {
    if (!followsNow()) return
    heldAt.current = null
    follow(true)
  }, [lit.range?.first])

  //? a play after a hold that has run its time: following comes back at once (paused, it waited)
  useEffect(() => {
    if (!player.playing || heldAt.current === null || !followsNow()) return
    heldAt.current = null
    stopTimer()
    follow(true)
  }, [player.playing])

  //? a change of size - a phone turned, the panel's column appearing - re-follows at once
  useEffect(() => {
    const box = scroller.current
    if (!box || typeof ResizeObserver !== 'function') return
    const observer = new ResizeObserver(() => {
      setHeight(box.clientHeight)
      if (followsNow()) follow(false)
    })
    observer.observe(box)
    return () => observer.disconnect()
  }, [])
  //? ...and again once the room after the last line has its new height, so the last lines can reach the anchor
  useLayoutEffect(() => {
    if (followsNow()) follow(false)
  }, [height])

  //? the listener's own scroll: a wheel, a touch that moves, a scroll key, the scroll bar - never the scroll event,
  //? which following's own scrolls fire too
  useEffect(() => {
    const box = scroller.current
    if (!box) return
    const onKey = (event: KeyboardEvent) => {
      pointered.current = false
      if (SCROLL_KEYS.includes(event.key)) hold()
    }
    const onPointer = (event: PointerEvent) => {
      pointered.current = true
      //? on the scroller itself, not a line in it: its scroll bar
      if (event.target === box) hold()
    }
    const onFocusIn = (event: FocusEvent) => {
      const at = Number((event.target as HTMLElement | null)?.dataset?.line)
      setFocusAt(Number.isInteger(at) ? at : null)
      if (pointered.current) return
      focused.current = true
      stopTimer()
    }
    const onFocusOut = (event: FocusEvent) => {
      if (box.contains(event.relatedTarget as Node | null)) return
      setFocusAt(null)
      if (!focused.current) return
      focused.current = false
      hold()
    }
    box.addEventListener('wheel', hold, { passive: true })
    box.addEventListener('touchmove', hold, { passive: true })
    box.addEventListener('keydown', onKey)
    box.addEventListener('pointerdown', onPointer)
    box.addEventListener('focusin', onFocusIn)
    box.addEventListener('focusout', onFocusOut)
    return () => {
      box.removeEventListener('wheel', hold)
      box.removeEventListener('touchmove', hold)
      box.removeEventListener('keydown', onKey)
      box.removeEventListener('pointerdown', onPointer)
      box.removeEventListener('focusin', onFocusIn)
      box.removeEventListener('focusout', onFocusOut)
      stopTimer()
    }
  }, [])

  //? a tap on a line: from there, playing - in the tap, nothing awaited first - and followed at once
  const playFrom = (index: number) => {
    const line = live.current.lines[index]
    if (!line || line.time === null) return
    player.seek(line.time)
    if (!player.playing) player.toggle()
    heldAt.current = null
    stopTimer()
    const was = litNow.current.range?.first
    draw(line.time)
    //? a line newly lit is followed by the lit line's own effect; the line already lit, here
    if (litNow.current.range?.first === was) follow(true)
  }
  const onLineKey = (event: KeyboardEvent, index: number) => {
    const to = lineAfterKey(live.current.lines, index, event.key)
    if (to === null) return
    event.preventDefault()
    list.current?.children[to]?.querySelector('button')?.focus()
  }

  let body
  let waiting = true
  if (!player.track) {
    body = <p class="app-lyrics-none">{NOTHING_PLAYING}</p>
  } else if (!lyrics) {
    body = answers.error && !answers.asking ? (
      <div class="app-lyrics-failed">
        {errorNote(answers.error, { class: 'app-lyrics-error', failed: LYRICS_FAILED, gone: SONG_GONE, retry: true })}
        {/* a gone has nothing to try again */}
        {errorKind(answers.error) !== 'not-found' && (
          <button type="button" class="app-button" onClick={answers.retry}>
            Try again
          </button>
        )}
      </div>
    ) : (
      <div class="pl-spinner" aria-label={LOADING_LYRICS} />
    )
  } else if (!lines.length) {
    body = <p class="app-lyrics-none">{NO_LYRICS}</p>
  } else if (synced) {
    waiting = false
    const stop = tabStop(lines, lit.range, focusAt)
    const isLit = (index: number) => !!lit.range && index >= lit.range.first && index <= lit.range.last
    body = (
      <>
        <ol ref={list} class="app-lyric-lines">
          {lines.map((line, index) =>
            sung(line) ? (
              <li>
                <button
                  type="button"
                  class="app-lyric"
                  data-line={index}
                  dir="auto"
                  aria-current={isLit(index) ? 'true' : undefined}
                  tabIndex={index === stop ? 0 : -1}
                  onClick={() => playFrom(index)}
                  onKeyDown={(event) => onLineKey(event, index)}
                >
                  {line.text}
                  <span class="app-visually-hidden">, {lyricTime(line.time ?? 0)}</span>
                </button>
              </li>
            ) : (
              //? a break between verses - three dots in it while it is the lit line of a long gap (decorative)
              <li class="app-lyric-break" aria-hidden="true">
                {lit.dots > 0 && lit.range?.first === index && (
                  <span class="app-lyric-dots">
                    {DOTS.map((dot) => (
                      <span class={`app-lyric-dot${lit.dots >= dot ? ' is-lit' : ''}`}>•</span>
                    ))}
                  </span>
                )}
              </li>
            ),
          )}
        </ol>
        {/* the room after the last line, so it can reach the anchor too */}
        <div class="app-lyrics-end" style={{ '--app-lyrics-room': `${endRoom(height)}px` }} />
      </>
    )
  } else {
    waiting = false
    body = (
      <>
        <p class="app-lyrics-note">{NOT_SYNCED}</p>
        <ol ref={list} class="app-lyric-lines">
          {lines.map((line) =>
            sung(line) ? (
              <li>
                <p class="app-lyric is-plain" dir="auto">{line.text}</p>
              </li>
            ) : (
              <li class="app-lyric-break" aria-hidden="true" />
            ),
          )}
        </ol>
      </>
    )
  }

  return (
    <section
      ref={scroller}
      class={`app-lyrics is-${place}${waiting ? ' is-waiting' : ''}`}
      aria-label={LYRICS}
      //? plain lyrics have no line to tab to: the view itself takes focus, so a keyboard can scroll them
      tabIndex={lyrics && !synced && lines.length ? 0 : undefined}
    >
      {body}
    </section>
  )
}
