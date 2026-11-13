import { useLayoutEffect, useMemo, useRef, useState } from 'preact/hooks'

import { panelIsModal, type PanelStyle } from '../lib/appFrame'
import { dragOffset, dropIndex } from '../lib/pins'
import { LOAD_WITHIN, pastRows, type PastRow } from '../lib/playHistory'
import type { QueueTrack } from '../lib/playQueue'
import { nextRepeat, repeatLabel, upNextView, type Mark, type UpNextQueue, type UpNextRow } from '../lib/upNext'
import { Cover } from '../player/Cover'
import { ChevronDownIcon, ChevronUpIcon, CloseIcon, GripIcon, RepeatIcon, RepeatOneIcon, ShuffleIcon } from '../player/icons'
import { queued } from '../player/levelling'
import type { Player } from '../player/usePlayer'
import { errorNote } from './ErrorNote'
import type { PlayHistory } from './usePlayHistory'
import { useSheet } from './useSheet'

/** Which of Up Next's two groups a row is in: the songs added (Playing Next), or the list's. */
type Group = 'added' | 'list'

/** A row being dragged in Edit: which, in which group, from where, how far, by which pointer, the rows' pitch. */
interface Drag {
  key: number
  group: Group
  start: number
  y: number
  dy: number
  pitch: number
  pointer: number
}

/** (2.1.3) Where a thing in Up Next's scroller sat, from the scroller's top: a row of the queue's by its key, (2.1.15) an
 *  older row by its own (a string with a colon in it, never 'card'), or the song playing's card. */
interface Spot {
  to: 'card' | number | string
  offset: number
}

/** (2.1.3) What Up Next holds its place by: the queue it was measured on - its first entry's mark, which every edit and
 *  move keeps and a new queue doesn't - the entry playing then (by key; none: hold by the spots whatever changed) and
 *  whether Edit was on, and the rows and the card then in view, top first. */
interface Anchor {
  first: Mark | undefined
  playing: number | undefined
  editing: boolean
  /** (2.1.15) what was drawn above the queue's own rows - the older rows, the line at the top (`aboveOf`) */
  above: string
  spots: Spot[]
}

/** Where focus goes once a change has drawn - see `refocus` below. */
type Refocus = { key: number | string; which: 'up' | 'down' | 'remove' | 'play' } | 'done' | 'shuffle' | null

/** (2.1.3 review) A row's tap, kept for the draw after it: the queue it was made on, the row, and what it does to the
 *  view, focus and words - put in place only if that draw shows the tap taken (`took`). */
interface Tap {
  from: UpNextQueue
  key: number | string
  /** a row of History's, or (2.1.15) an older row's: the song again, a new entry */
  again: boolean
  track: QueueTrack
  anchor: Anchor
  refocus: Refocus
  said: string | null
}

/** (2.1.3) The songs already played - Apple Music's word: since 2.1.15 their list's name to a screen reader, no heading
 *  drawn (James: one continuous list). */
export const HISTORY = 'History'
/** (2.1.15) While an older page of them is on its way, at the list's top. */
export const LOADING_EARLIER = 'Loading earlier songs'
/** ...and when it couldn't come - errorNote's `failed` (lib/errorWords.ts). */
export const EARLIER_FAILED = "Couldn't load the songs you played before."
/** No older rows: one array for every render. */
const NO_PAST: readonly PastRow[] = []
/** What Up Next says under the song playing with Repeat One on. */
export const REPEATING_ONE = 'Repeat one: this song plays again until you skip it.'
/** ...and under the Shuffle chip for a whole library's shuffle (Part B), whose order is the shuffle. */
export const SHUFFLING_LIBRARY = 'Shuffling your whole library'

const songLine = (row: { track: { artist: string; album: string } }) => [row.track.artist, row.track.album].filter(Boolean).join(' · ')
const plural = (count: number) => `And ${count.toLocaleString('en-US')} more ${count === 1 ? 'song' : 'songs'}.`

/**
 * Up Next (2.0.0-player.57) - James: "i'd like to be able to see the queue somewhere in the player, but I don't
 * want to disrupt the theme we have going". Opened from Now Playing's Up Next button, as a sheet over it on a
 * phone, and from the player bar's Up Next as the side panel on a desktop - Info's shell, so it looks like Info.
 * What it draws is lib/upNext.ts's upNextView: History - the songs already played, oldest first (2.1.3) - then the
 * song playing (and, with Repeat One, that it repeats); Shuffle and Repeat, the iPhone's Music app's place for them,
 * so Now Playing's own screen gets nothing but the button; Playing Next - the songs added, with Clear - when there
 * are any; the rest of the album or list this time round (up to UP_NEXT_DRAWN, then "And N more songs."); and what
 * comes after it. Neither Repeat One's copies nor the later times round are drawn.
 *
 * A ROW'S TAP plays it now (player.jumpTo, straight from the click - a tap, so it may start a stream as a song's
 * tap on an album does). Nothing is dropped (2.1.3, James: "6 and 7 stay behind 8"): the rows it passes stay where
 * they are, behind it, where Previous and History find them, and Playing Next stays next. A row of HISTORY's plays
 * its song again, now - the songs after it as they were. Rows are the queue's own keys, so a song in twice is two
 * rows, and a tap names the row even if the queue moved on under the finger - a key gone does nothing.
 *
 * WHERE IT OPENS, AND KEEPS ITS PLACE (2.1.3): every opening puts the song playing's card at the top of the
 * scroller, History above it, scrolled up to - as Apple Music opens its queue - on a phone's sheet and a desktop's
 * panel alike; the card and what follows it are at least the scroller's height (app.css .app-upnext-now), so the card
 * reaches the top even with only a song or two after it. What is in view is measured as it scrolls (`anchor`: the
 * rows and the card in view, by key). A change ABOVE the card - the song playing changed (History grew or shrank: a
 * song's end, Next, Previous, a tap), or Edit on or off (History hidden or back) - puts it back, so nothing moves under
 * the eye: a song ending by itself leaves whatever was topmost where it was (at the card, the new card stays at the
 * top - a panel left open doesn't creep a row a song), a History tap leaves the row tapped under the finger, and a
 * tap in the list or Playing Next brings the new card to the top, what plays next straight under it. A change below
 * it - Shuffle, Repeat, Clear, a song added, Edit's moves, drags and removals (2.1.3 review: following a row there
 * followed it out of view) - leaves the scroll where it is, as it always has. A tap the engine doesn't take (a key gone,
 * an edit the stream can't make this moment) moves, focuses and says nothing. The browser's own scroll anchoring is
 * off for this scroller (app.css), so the two never fight.
 *
 * HISTORY, to a keyboard and VoiceOver: one Tab stop for all of it (a roving tabindex - the newest row, or the one
 * last focused), Up and Down, Home and End inside it; the song playing's title a heading, then Playing Next's and the
 * list's. Hidden in Edit, which moves only what is still to play.
 *
 * PLAY HISTORY THAT LASTS (2.1.15, notes/play-history.md - James: "so you can always look back and see what you played
 * yesterday"): above History, ONE CONTINUOUS LIST goes on back through every song the person has played, on this app
 * or the iPhone - no heading anywhere, no days, no times (James), skips like the rest, newest nearest the song
 * playing. `history` (app/usePlayHistory.ts) holds deadwax's pages and this page's own starts; lib/playHistory.ts
 * pastRows() leaves out every start the queue's own rows draw, so each is drawn once. Its next older page is asked for
 * as the scroller comes within LOAD_WITHIN of its height of the top - a spinner there while it comes, the error in a
 * listener's words with Try again if it can't - and a page landing above holds the view where it was, as History's
 * changes do. An older row's tap plays its song again, now, as History's does: Play Next's entry (queued at the
 * Normalization setting's level), moved to - the queue carrying on after it - in the click, nothing awaited.
 *
 * EDIT, as Home's Pinned does it: each group's rows with Move up, Move down and Remove, and a grip to drag by
 * (lib/pins.ts dropIndex and dragOffset - only the grip takes the pointer, so the sheet still scrolls under a
 * finger elsewhere); a move stays within its group; each change made as it is tapped, nothing to save. Focus is
 * kept as Pinned keeps it - on a move's button where the row went; after a removal on the next row's Remove,
 * the one before at the end, Done with none left - and what changed is read out. The header's Done ends Edit;
 * Escape and the backdrop close the sheet, ending it.
 *
 * A sheet like the others (useSheet.ts) - its own scroll lock, focus in to Done and back to the button that
 * opened it, Escape, the backdrop - and on a desktop the panel, not modal, as Info is. A leaf: props only.
 */
export function UpNext({
  open,
  opener,
  onClose,
  player,
  history,
  panel = 'sheet',
  covered = false,
}: {
  open: boolean
  opener?: { current: HTMLElement | null } | undefined
  onClose: () => void
  player: Pick<Player, 'queue' | 'track' | 'playing' | 'shuffle' | 'repeat' | 'setShuffle' | 'setRepeat' | 'jumpTo' | 'playNext' | 'moveInQueue' | 'removeFromQueue' | 'clearPlayingNext'>
  /** (2.1.15) the songs played before History's: none without it */
  history?: Pick<PlayHistory, 'plays' | 'more' | 'loading' | 'error' | 'older' | 'retry'> | undefined
  /** how it is drawn: a sheet over Now Playing (a phone), or a desktop's side panel */
  panel?: PanelStyle
  /** something over it - the desktop's visualizer: inert, out of a screen reader's reach, until it goes */
  covered?: boolean
}) {
  const modal = panelIsModal(panel)
  const done = useRef<HTMLButtonElement>(null)
  const box = useRef<HTMLDivElement>(null)
  const scroller = useRef<HTMLDivElement>(null)
  const shuffleChip = useRef<HTMLButtonElement>(null)
  const [editing, setEditing] = useState(false)
  const [drag, setDrag] = useState<Drag | null>(null)
  //? what is read out, each a new node in the region (`id`) - so the same words twice are said twice (2.1.3 review)
  const [said, setSaid] = useState<{ text: string; id: number }>({ text: '', id: 0 })
  const say = (text: string) => setSaid((was) => ({ text, id: was.id + 1 }))
  //? (2.1.3) History's one Tab stop: the row last focused, while it is drawn - else the newest (2.1.15: an older row's
  //? key too)
  const [historyStop, setHistoryStop] = useState<number | string | null>(null)
  //? where focus goes once a change has drawn - Pinned's rule: a move's button where the row went, the next
  //? row's Remove after a removal, Done with none left, the Shuffle chip after Clear; Done as Edit starts (the
  //? Edit button pressed goes from the head); after a row's tap - that row now the song playing, so gone from the
  //? list - what plays next: Playing Next's head after a list row's (2.1.3: it is carried after the row), the row
  //? after it otherwise, or Done with none (focus never left on nothing, where Escape can't reach the panel); after
  //? History's, that row still (Done if it fell off History's far end)
  const refocus = useRef<Refocus>(null)
  //? (2.1.15) the older rows above History - none in Edit - and what is drawn above the queue's rows, which the view is
  //? held through (`above`). Built and drawn only while open (the review): closed, Up Next stays mounted, and a month
  //? scrolled back is thousands of rows rebuilt and re-diffed at every song's change. The rows drawn as it closes stay
  //? until the queue next changes - the sheet long gone by then - so nothing above the card moves as it slides away
  const drawnPast = useRef<{ queue: UpNextQueue; rows: readonly PastRow[] }>({ queue: player.queue, rows: NO_PAST })
  const past = useMemo(() => {
    const rows = !history || editing
      ? NO_PAST
      : open
        ? pastRows(history.plays, player.queue)
        : drawnPast.current.queue === player.queue ? drawnPast.current.rows : NO_PAST
    drawnPast.current = { queue: player.queue, rows }
    return rows
  }, [open, history?.plays, player.queue, editing])
  const loadingEarlier = !editing && !!history?.loading
  const earlierFailed = !editing && history?.error ? history.error : null
  const above = `${past.length}:${past[0]?.key ?? ''}:${past[past.length - 1]?.key ?? ''}:${loadingEarlier ? 1 : 0}:${earlierFailed ? 1 : 0}`
  //? (2.1.3) where the view is held - see "WHERE IT OPENS" above
  const anchor = useRef<Anchor>({ first: undefined, playing: undefined, editing: false, above: '', spots: [{ to: 'card', offset: 0 }] })
  //? (2.1.3 review) the last row's tap, until the draw after it
  const tapped = useRef<Tap | null>(null)
  useSheet({ open, covered, onClose, lockClass: 'app-upnext-open', first: done, opener, modal, area: box })

  const marks0 = () => player.queue.upNext?.marks[0]
  const playingKey = () => player.queue.upNext?.marks[player.queue.index]?.key
  const atCard = (): Anchor => ({ first: marks0(), playing: undefined, editing, above, spots: [{ to: 'card', offset: 0 }] })
  /** Every row and the card in the scroller, top first, where it sits from the scroller's top - and whether a pixel of
   *  it is in view. Found by their own data, never a selector built from a key. */
  const placed = (): { spot: Spot; seen: boolean }[] => {
    const scroll = scroller.current
    if (!scroll) return []
    const view = scroll.getBoundingClientRect()
    return [...scroll.querySelectorAll<HTMLElement>('[data-key], [data-past], [data-playing]')].map((element) => {
      const rect = element.getBoundingClientRect()
      const to = element.dataset.key !== undefined ? Number(element.dataset.key) : element.dataset.past ?? 'card'
      return {
        spot: { to, offset: rect.top - view.top },
        seen: rect.bottom - view.top >= 1 && view.bottom - rect.top >= 1,
      }
    })
  }
  /** What is in view now, kept to hold the place by - nothing in view (hidden, closed): what was kept before. */
  const measure = () => {
    const seen = placed().filter((each) => each.seen).map((each) => each.spot)
    if (seen.length) anchor.current = { first: marks0(), playing: playingKey(), editing, above, spots: seen }
  }
  /** (2.1.15) Near the top - within LOAD_WITHIN of the scroller's height - the next older page asked for: only while one
   *  is there to ask, none is on its way, and the last didn't fail (Try again asks then). */
  const nearTop = () => {
    const scroll = scroller.current
    if (!scroll || !history || editing || !player.track || !history.more || history.loading || history.error) return
    if (scroll.scrollTop < scroll.clientHeight * LOAD_WITHIN) history.older()
  }
  /** The view put back: the first thing kept that is still drawn, where it was - for a new queue (another album
   *  tapped, a queue put back) or with none of them drawn, the song playing's card at the top. With the same song
   *  playing, Edit as it was and (2.1.15) the same drawn above History, nothing above the card changed: the scroll
   *  stays where it is. */
  const restore = () => {
    const scroll = scroller.current
    if (!scroll) return
    const held = anchor.current
    const same = held.first === marks0()
    if (same && held.playing !== undefined && held.playing === playingKey() && held.editing === editing && held.above === above) return
    const spots: Spot[] = same ? held.spots : [{ to: 'card', offset: 0 }]
    const now = placed()
    const found = spots.map((spot) => ({ spot, there: now.find((each) => each.spot.to === spot.to) })).find((each) => each.there)
      ?? { spot: { to: 'card', offset: 0 }, there: now.find((each) => each.spot.to === 'card') }
    if (!found.there) return
    const delta = found.there.spot.offset - found.spot.offset
    if (Math.abs(delta) >= 1) scroll.scrollTop += delta
  }

  //? every opening starts at the song playing - History above it, scrolled up to - and out of Edit
  useLayoutEffect(() => {
    if (!open) return
    setEditing(false)
    setDrag(null)
    anchor.current = atCard()
  }, [open])

  //? (2.1.3) ...and keeps its place through every change: what was in view put back, then measured again - a tap's
  //? place, focus and words first, if the queue now shows it taken
  useLayoutEffect(() => {
    if (!open) return
    const tap = tapped.current
    tapped.current = null
    if (tap && took(tap)) {
      anchor.current = tap.anchor
      refocus.current = tap.refocus
      if (tap.said) say(tap.said)
    }
    restore()
    measure()
    //? (2.1.15) ...and, held where it was, still near the top: the next older page
    nearTop()
  }, [open, editing, player.queue, player.repeat, above])

  //? (2.1.3 review) ...and a tap the draw after it doesn't show taken is let go: the view, focus and words as they were
  useLayoutEffect(() => {
    tapped.current = null
  })

  useLayoutEffect(() => {
    const wanted = refocus.current
    refocus.current = null
    if (!wanted) return
    if (wanted === 'done' || wanted === 'shuffle') {
      ;(wanted === 'done' ? done.current : shuffleChip.current)?.focus()
      return
    }
    //? by the row's own data, never a selector built from it - a queue row's key, or (2.1.15) an older row's
    const row = scroller.current
      ? [...scroller.current.querySelectorAll<HTMLElement>('[data-key], [data-past]')].find((each) => (each.dataset.key ?? each.dataset.past) === String(wanted.key))
      : undefined
    const live = (which: string) => row?.querySelector<HTMLButtonElement>(`.app-pin-${which}:not([aria-disabled="true"])`) ?? null
    const target = wanted.which === 'play'
      ? row?.querySelector<HTMLButtonElement>('.app-result') ?? done.current
      : wanted.which === 'remove'
        ? row?.querySelector<HTMLButtonElement>('.app-pin-remove') ?? done.current
        : live(wanted.which) ?? live(wanted.which === 'up' ? 'down' : 'up')
    target?.focus()
  })

  const view = upNextView(player.queue, player.repeat)
  const paged = !!player.queue.upNext?.paged
  const playing = view.playing
  const groups: { group: Group; rows: UpNextRow[] }[] = [
    { group: 'added', rows: view.added },
    { group: 'list', rows: view.list?.rows ?? [] },
  ]
  const editable = view.added.length + (view.list?.rows.length ?? 0) > 0
  //? (2.1.15) the older rows and History's one list: one Tab stop across both
  const played = [...past.map((row) => row.key), ...view.history.map((row) => row.key)]
  const stop = historyStop !== null && played.includes(historyStop) ? historyStop : played[played.length - 1]

  const toggleShuffle = () => {
    if (paged) return
    const on = !player.shuffle
    player.setShuffle(on)
    say(on ? 'Shuffle on' : 'Shuffle off')
  }
  const cycleRepeat = () => {
    const mode = nextRepeat(player.repeat)
    player.setRepeat(mode)
    say(mode === 'off' ? 'Repeat off' : repeatLabel(mode))
  }
  const clear = () => {
    refocus.current = 'shuffle'
    player.clearPlayingNext()
    say('Playing Next cleared')
  }

  const move = (row: UpNextRow, rows: readonly UpNextRow[], from: number, by: -1 | 1) => {
    const to = from + by
    if (to < 0 || to >= rows.length) return
    refocus.current = { key: row.key, which: by < 0 ? 'up' : 'down' }
    player.moveInQueue(row.key, to)
    say(`${row.track.title}: ${to + 1} of ${rows.length}`)
  }
  const remove = (row: UpNextRow, rows: readonly UpNextRow[], index: number) => {
    const next = rows[index + 1] ?? rows[index - 1]
    refocus.current = next ? { key: next.key, which: 'remove' } : 'done'
    player.removeFromQueue(row.key)
    say(`${row.track.title} removed`)
  }

  //? the drag: by the grip only, one pointer, the rows' pitch measured as it starts - Pinned's own
  const startDrag = (event: PointerEvent, row: UpNextRow, group: Group, index: number) => {
    if (drag || event.button > 0) return
    const grip = event.currentTarget as HTMLElement
    const item = grip.closest('li')
    if (!item) return
    const after = item.nextElementSibling as HTMLElement | null
    const before = item.previousElementSibling as HTMLElement | null
    const pitch = after ? after.offsetTop - item.offsetTop : before ? item.offsetTop - before.offsetTop : item.offsetHeight
    grip.setPointerCapture?.(event.pointerId)
    event.preventDefault()
    setDrag({ key: row.key, group, start: index, y: event.clientY, dy: 0, pitch, pointer: event.pointerId })
  }
  const followDrag = (event: PointerEvent) => {
    if (drag && event.pointerId === drag.pointer) setDrag({ ...drag, dy: event.clientY - drag.y })
  }
  const endDrag = (event: PointerEvent, rows: readonly UpNextRow[]) => {
    if (!drag || event.pointerId !== drag.pointer) return
    const to = dropIndex(drag.start, event.clientY - drag.y, drag.pitch, rows.length)
    setDrag(null)
    if (to === drag.start) return
    player.moveInQueue(drag.key, to)
    const row = rows[drag.start]
    if (row) say(`${row.track.title}: ${to + 1} of ${rows.length}`)
  }
  const dropDrag = (event: PointerEvent) => {
    if (drag && event.pointerId === drag.pointer) setDrag(null)
  }

  const toggleEditing = () => {
    if (editing) {
      setEditing(false)
      setDrag(null)
      return
    }
    //? the Edit button goes as Edit starts: focus to Done, which now ends it
    refocus.current = 'done'
    setEditing(true)
  }

  /** Whether the queue drawn now shows `tap` taken: another queue than the one it was made on, playing the row tapped -
   *  or, for History's and (2.1.15) an older row's, a new entry of its song (or a new queue of it: Play Next on a queue
   *  played out plays it from the first). */
  const took = (tap: Tap): boolean => {
    const queue = player.queue
    const mark = queue.upNext?.marks[queue.index]
    if (queue === tap.from || !mark) return false
    if (!tap.again) return mark.key === tap.key
    const fresh = queue.upNext?.id !== tap.from.upNext?.id
    return (fresh || mark.key >= (tap.from.upNext?.nextKey ?? Infinity)) && queue.tracks[queue.index]?.id === tap.track.id
  }

  /** A row's tap: it plays now, so it leaves the list - focus to what plays next: after a list row's, Playing Next's
   *  head (carried after it, 2.1.3), else the row after it; after Playing Next's last, the list's first; Done with
   *  none. The new card at the top, what plays next straight under it, so focus lands in view - once the tap is
   *  taken (`tapped`, put in place by the draw that shows it). */
  const jump = (group: Group, rows: readonly UpNextRow[], index: number) => {
    const row = rows[index]!
    const after = group === 'added' ? rows[index + 1] ?? groups[1]!.rows[0] : view.added[0] ?? rows[index + 1]
    tapped.current = { from: player.queue, key: row.key, again: false, track: row.track, anchor: atCard(), refocus: after ? { key: after.key, which: 'play' } : 'done', said: null }
    player.jumpTo(row.key)
  }

  /** (2.1.3) A row of History's tap: the song again, now. History isn't rewritten, so the row stays - held where it is
   *  under the finger, focus kept on it - and since nothing in view moves, what started is said aloud; all once the tap
   *  is taken, as a list row's. */
  const replay = (row: UpNextRow) => {
    const now = placed()
    const under = now.find((each) => each.spot.to === row.key)
    const spots = [...(under ? [under.spot] : []), ...now.filter((each) => each.seen).map((each) => each.spot)]
    tapped.current = {
      from: player.queue, key: row.key, again: true, track: row.track,
      anchor: { first: marks0(), playing: undefined, editing, above, spots }, refocus: { key: row.key, which: 'play' }, said: `Playing ${row.track.title}`,
    }
    player.jumpTo(row.key)
  }

  /** (2.1.15) An older row's tap: the song again, now - as History's, a new entry after the song playing's copies that
   *  plays at once, the queue carrying on after it: Play Next's (queued at the setting's level, as a song's ••• queues
   *  it) moved to by the key it is given. With nothing to play next to (a queue played out) Play Next plays it from the
   *  first itself. An edit the stream can't take this moment is held, the key isn't there yet, and the song waits as
   *  Playing Next - as a History tap's refusal leaves it. Held under the finger and said, once taken, as History's. */
  const replayPast = (row: PastRow) => {
    const now = placed()
    const under = now.find((each) => each.spot.to === row.key)
    const spots = [...(under ? [under.spot] : []), ...now.filter((each) => each.seen).map((each) => each.spot)]
    tapped.current = {
      from: player.queue, key: row.key, again: true, track: row.track,
      anchor: { first: marks0(), playing: undefined, editing, above, spots }, refocus: { key: row.key, which: 'play' }, said: `Playing ${row.track.title}`,
    }
    const key = player.queue.upNext?.nextKey
    const began = player.playNext(queued([row.track], 'songs'))
    if (!began && key !== undefined) player.jumpTo(key)
  }

  /** (2.1.3) Inside History, one Tab stop: Up and Down to the row before and after, Home and End to its ends. */
  const moveInHistory = (event: KeyboardEvent) => {
    const rows = [...(event.currentTarget as HTMLElement).querySelectorAll<HTMLButtonElement>('.app-result')]
    const at = rows.indexOf(event.target as HTMLButtonElement)
    if (at < 0) return
    const to = event.key === 'ArrowDown' ? rows[Math.min(rows.length - 1, at + 1)]
      : event.key === 'ArrowUp' ? rows[Math.max(0, at - 1)]
        : event.key === 'Home' ? rows[0]
          : event.key === 'End' ? rows[rows.length - 1]
            : undefined
    if (!to) return
    event.preventDefault()
    to.focus()
  }

  /** One group's rows: to tap (play now), or in Edit to move, remove and drag. */
  const rowsOf = (group: Group, rows: readonly UpNextRow[]) => {
    if (!rows.length) return null
    if (!editing) {
      return (
        <ul class="app-results">
          {rows.map((row, index) => (
            <li key={row.key} data-key={row.key}>
              <button type="button" class="app-result" aria-label={`${row.track.title}, play now`} onClick={() => jump(group, rows, index)}>
                <Cover id={row.track.coverArt} size={96} class="app-result-cover" />
                <span class="app-result-text">
                  <span class="app-result-title" dir="auto">{row.track.title}</span>
                  <span class="app-result-line">{songLine(row)}</span>
                </span>
              </button>
            </li>
          ))}
        </ul>
      )
    }
    const dragging = drag?.group === group ? drag : null
    const landing = dragging ? dropIndex(dragging.start, dragging.dy, dragging.pitch, rows.length) : -1
    return (
      <ol class="app-pins-edit">
        {rows.map((row, index) => {
          const offset = dragging ? dragOffset(index, dragging.start, landing, dragging.dy, dragging.pitch) : 0
          return (
            <li
              key={row.key}
              data-key={row.key}
              class={`app-pin-row app-card${dragging?.key === row.key ? ' is-dragging' : ''}`}
              style={offset ? { transform: `translateY(${offset}px)` } : undefined}
            >
              <span class="app-pin-text">
                <span class="app-pin-title" dir="auto">{row.track.title}</span>
                <span class="app-pin-line" dir="auto">{songLine(row)}</span>
              </span>
              <button type="button" class="app-pin-move app-pin-up" aria-label={`Move ${row.track.title} up`} aria-disabled={index === 0} onClick={() => move(row, rows, index, -1)}>
                <span class="app-pin-move-face">
                  <ChevronUpIcon class="app-pin-move-icon" />
                </span>
              </button>
              <button type="button" class="app-pin-move app-pin-down" aria-label={`Move ${row.track.title} down`} aria-disabled={index === rows.length - 1} onClick={() => move(row, rows, index, 1)}>
                <span class="app-pin-move-face">
                  <ChevronDownIcon class="app-pin-move-icon" />
                </span>
              </button>
              <button type="button" class="app-pin-move app-pin-remove" aria-label={`Remove ${row.track.title}`} onClick={() => remove(row, rows, index)}>
                <span class="app-pin-move-face">
                  <CloseIcon class="app-pin-move-icon" />
                </span>
              </button>
              <span
                class="app-pin-grip"
                aria-hidden="true"
                onPointerDown={(event) => startDrag(event, row, group, index)}
                onPointerMove={followDrag}
                onPointerUp={(event) => endDrag(event, rows)}
                onPointerCancel={dropDrag}
                onLostPointerCapture={dropDrag}
              >
                <GripIcon class="app-pin-grip-icon" />
              </span>
            </li>
          )
        })}
      </ol>
    )
  }

  return (
    <div class={`app-layer app-info-layer app-upnext-layer${open ? ' is-open' : ''}${modal ? '' : ` is-panel is-${panel}`}`} aria-hidden={!open || covered} inert={!open || covered}>
      <div class="app-backdrop" onClick={onClose} />
      {/* a panel's box takes focus from a click on anything in it that can't, so Escape there is still from inside it */}
      <div ref={box} class="app-info app-upnext" role="dialog" aria-modal={modal ? 'true' : 'false'} aria-labelledby="app-upnext-title" tabIndex={modal ? undefined : -1}>
        <header class="app-info-head">
          {!editing && editable && (
            <button type="button" class="app-upnext-edit" onClick={toggleEditing}>
              Edit
            </button>
          )}
          <h2 id="app-upnext-title" class="app-info-title">
            Up Next
          </h2>
          {/* closes - or, while editing, ends Edit: one Done */}
          <button ref={done} type="button" class="app-info-done" onClick={editing ? toggleEditing : onClose}>
            Done
          </button>
        </header>
        {/* what a change made here was, read out - always in the page, as iOS reads only a region already there */}
        <p class="app-visually-hidden" role="status" aria-live="polite" aria-atomic="true">{said.text && <span key={said.id}>{said.text}</span>}</p>

        <div ref={scroller} class="app-info-scroll" tabIndex={0} onScroll={() => { if (open) { measure(); nearTop() } }}>
          {playing && (
            <>
              {/* (2.1.3) the songs already played, above the song playing - scrolled up to; not in Edit. (2.1.15) One list
                  with no heading: every song played before, oldest at the top, then the queue's own History */}
              {!editing && (played.length > 0 || loadingEarlier || earlierFailed) && (
                <section class="app-upnext-history" aria-label={HISTORY}>
                  {loadingEarlier && <div class="pl-spinner" aria-label={LOADING_EARLIER} />}
                  {earlierFailed ? (
                    <div class="pl-notice">
                      {errorNote(earlierFailed, { failed: EARLIER_FAILED, retry: true })}
                      <button type="button" class="pl-text-button" onClick={history?.retry}>
                        Try again
                      </button>
                    </div>
                  ) : null}
                  {played.length > 0 && (
                    <ul class="app-results" onKeyDown={moveInHistory}>
                      {past.map((row) => (
                        <li key={row.key} data-past={row.key}>
                          <button
                            type="button"
                            class="app-result"
                            aria-label={`${row.track.title}, play again`}
                            tabIndex={row.key === stop ? 0 : -1}
                            onFocus={() => setHistoryStop(row.key)}
                            onClick={() => replayPast(row)}
                          >
                            <Cover id={row.track.coverArt} size={96} class="app-result-cover" />
                            <span class="app-result-text">
                              <span class="app-result-title" dir="auto">{row.track.title}</span>
                              <span class="app-result-line">{songLine(row)}</span>
                            </span>
                          </button>
                        </li>
                      ))}
                      {view.history.map((row) => (
                        <li key={row.key} data-key={row.key}>
                          <button
                            type="button"
                            class="app-result"
                            aria-label={`${row.track.title}, play again`}
                            tabIndex={row.key === stop ? 0 : -1}
                            onFocus={() => setHistoryStop(row.key)}
                            onClick={() => replay(row)}
                          >
                            <Cover id={row.track.coverArt} size={96} class="app-result-cover" />
                            <span class="app-result-text">
                              <span class="app-result-title" dir="auto">{row.track.title}</span>
                              <span class="app-result-line">{songLine(row)}</span>
                            </span>
                          </button>
                        </li>
                      ))}
                    </ul>
                  )}
                </section>
              )}

              {/* the song playing and what follows it: at least the scroller's height, so the card can reach its top */}
              <div class="app-upnext-now">
                <div class="app-card app-info-card app-upnext-playing" data-playing="">
                  <Cover id={playing.coverArt} size={128} class="app-info-cover" />
                  <div class="app-info-text">
                    <p class="app-info-name" dir="auto" role="heading" aria-level={3}>{playing.title}</p>
                    <p class="app-info-line" dir="auto">{[playing.artist, playing.album].filter(Boolean).join(' · ')}</p>
                  </div>
                </div>
                {view.repeatOne && <p class="app-store-line">{REPEATING_ONE}</p>}

                <div class="app-upnext-modes" role="group" aria-label="Shuffle and repeat">
                  <button
                    ref={shuffleChip}
                    type="button"
                    class={`app-chip app-upnext-shuffle${player.shuffle ? ' is-on' : ''}`}
                    aria-pressed={player.shuffle}
                    aria-disabled={paged}
                    onClick={toggleShuffle}
                  >
                    <ShuffleIcon class="app-chip-icon" />
                    Shuffle
                  </button>
                  <button
                    type="button"
                    class={`app-chip app-upnext-repeat${player.repeat === 'off' ? '' : ' is-on'}`}
                    aria-pressed={player.repeat !== 'off'}
                    onClick={cycleRepeat}
                  >
                    {player.repeat === 'one' ? <RepeatOneIcon class="app-chip-icon" /> : <RepeatIcon class="app-chip-icon" />}
                    {repeatLabel(player.repeat)}
                  </button>
                </div>
                {paged && <p class="app-store-line">{SHUFFLING_LIBRARY}</p>}

                {view.added.length > 0 && (
                  <section class="app-upnext-group" aria-labelledby="app-upnext-added">
                    <div class="app-section-head">
                      <h3 id="app-upnext-added" class="app-section-title">Playing Next</h3>
                      <button type="button" class="app-text-button app-upnext-clear" onClick={clear}>
                        Clear
                      </button>
                    </div>
                    {rowsOf('added', groups[0]!.rows)}
                  </section>
                )}

                {view.list && (
                  <section class="app-upnext-group" aria-labelledby="app-upnext-list">
                    <div class="app-section-head">
                      <h3 id="app-upnext-list" class="app-section-title">{view.list.title}</h3>
                    </div>
                    {rowsOf('list', groups[1]!.rows)}
                    {view.list.more > 0 && <p class="app-store-line">{plural(view.list.more)}</p>}
                  </section>
                )}

                {view.then && <p class="app-store-line app-upnext-then">{view.then}</p>}
              </div>
            </>
          )}
        </div>
      </div>
    </div>
  )
}
