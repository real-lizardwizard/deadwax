import { useLayoutEffect, useRef, useState } from 'preact/hooks'

import { dragOffset, dropIndex, pinKey, pinLine, pinOpens, type Pin } from '../lib/pins'
import { dropPrefetch, prefetchAlbum, type Album } from '../player/api'
import { Cover } from '../player/Cover'
import { ChevronDownIcon, ChevronUpIcon, CloseIcon, GripIcon } from '../player/icons'

/** An artist a card opens: Navidrome's id for them, or their MusicBrainz id - App's openArtist. */
export interface PinnedArtist {
  navidrome?: string | null
  mbid?: string | null
  name?: string
  coverArt?: string | null
}

/** A row being dragged in Edit: which, from where, how far, by which pointer, and the rows' pitch. */
interface Drag {
  key: string
  start: number
  y: number
  dy: number
  pitch: number
  pointer: number
}

/** What Home says under "Pinned" with nothing pinned yet. */
export const NOTHING_PINNED = 'Pin an album or an artist from its page, and it shows here.'

/**
 * Home's Pinned (2.0.0-player.18), as Home.dc.html draws it: "Pinned" with **Edit** at its right,
 * then two columns of cards - an artist's picture round, an album's cover square, its name over
 * "Artist" or the album's artist. James: "Pinned albums and artists come next, at the top (pin from
 * an album or artist page)".
 *
 * A card OPENS what it pins - an album on the tab showing, as a tile does, its songs asked for as the
 * finger lands (prefetchAlbum, called off if the press becomes a scroll); an artist's page, by their
 * MusicBrainz id where the pin has one (the page finds Navidrome's artist for it as it opens, so a
 * Navidrome id gone stale since the pin was made - a rename re-files their albums - doesn't open a
 * broken page), else by Navidrome's id - and plays nothing: Play is pressed on the page, in the tap.
 * An album that can't be opened is drawn as words, not a button, saying why: "Removed from the store"
 * (deadwax deleted it), "Not on disk just now" (its folder isn't there - an unmounted share, as often
 * as not), "Not in Navidrome yet"; a closed card gives those words two lines and its title one.
 *
 * **Edit** turns the cards into one column of rows, each with **up** and **down** buttons, a button
 * to unpin it, and a grip to drag it by (only the grip takes the drag, so the page still scrolls
 * under a finger anywhere else). Each change is saved as it is made (onMove, onRemove - usePins.ts),
 * shown at once; a move by a button keeps focus on that button where the row went, an unpin puts it
 * on the next row's unpin (the one before, at the end; Done, with none left), and what changed is
 * read out. **Done** goes back to the cards (with nothing left pinned, focus goes to the heading). A
 * pin made a moment ago and not saved yet can't be moved until it is. One of these changes deadwax
 * didn't keep says so UNDER the list, never above it, so nothing a finger is on moves.
 *
 * A leaf: what it draws and what it calls come from Home (props only).
 */
export function Pinned({
  pins,
  problem,
  onOpenAlbum,
  onOpenArtist,
  onMove,
  onRemove,
}: {
  /** null until deadwax has answered */
  pins: readonly Pin[] | null
  /** the last change not saved, or the first read unanswered */
  problem: string | null
  onOpenAlbum: (album: Album) => void
  onOpenArtist: (artist: PinnedArtist) => void
  onMove: (key: string, to: number) => void
  onRemove: (key: string) => void
}) {
  const [editing, setEditing] = useState(false)
  const [drag, setDrag] = useState<Drag | null>(null)
  const [said, setSaid] = useState('')
  const list = useRef<HTMLOListElement>(null)
  const editButton = useRef<HTMLButtonElement>(null)
  const heading = useRef<HTMLHeadingElement>(null)
  //? where focus goes once a change has drawn: back to a move's button, in the row where it went; to
  //? the next row's unpin after an unpin (whose own row - and button - has left the page); Done, with
  //? no row left; the heading, once Done itself has gone. Never to the page, which drops a keyboard's
  //? or VoiceOver's place in the list
  const refocus = useRef<{ key: string; which: 'up' | 'down' | 'remove' } | 'edit' | 'heading' | null>(null)

  useLayoutEffect(() => {
    const wanted = refocus.current
    refocus.current = null
    if (!wanted) return
    if (wanted === 'edit' || wanted === 'heading') {
      ;(wanted === 'edit' ? editButton.current : heading.current)?.focus()
      return
    }
    //? by the row's own data, never a selector built from its key (a ref holds a colon)
    const row = list.current
      ? [...list.current.querySelectorAll<HTMLElement>('[data-pin]')].find((each) => each.dataset.pin === wanted.key)
      : undefined
    const live = (which: string) => row?.querySelector<HTMLButtonElement>(`.app-pin-${which}:not([aria-disabled="true"])`) ?? null
    const target = wanted.which === 'remove'
      ? row?.querySelector<HTMLButtonElement>('.app-pin-remove') ?? editButton.current
      : live(wanted.which) ?? live(wanted.which === 'up' ? 'down' : 'up')
    target?.focus()
  })

  if (pins === null) {
    return problem ? (
      <section class="app-section app-pinned" aria-labelledby="app-pinned-title">
        <h2 id="app-pinned-title" class="app-section-title">Pinned</h2>
        <p class="app-pinned-note is-said">{problem}</p>
      </section>
    ) : null
  }

  //? where the row being dragged would land: the rows between make way for it, by transform alone -
  //? the list's own order never changes under a drag, since moving the dragged row's element in the
  //? page would take the pointer's capture from its grip
  const landing = drag ? dropIndex(drag.start, drag.dy, drag.pitch, pins.length) : -1

  const openAlbum = (pin: Pin) => {
    if (!pin.navidrome_id) return
    onOpenAlbum({ id: pin.navidrome_id, name: pin.label, ...(pin.sub ? { artist: pin.sub } : {}), ...(pin.cover ? { coverArt: pin.cover } : {}) })
  }
  const open = (pin: Pin) => {
    if (pin.kind === 'album') openAlbum(pin)
    //? by MusicBrainz id where there is one: the Navidrome id kept since it was pinned may name nobody now
    else if (pin.mbid) onOpenArtist({ mbid: pin.mbid, name: pin.label, coverArt: pin.cover })
    else onOpenArtist({ navidrome: pin.navidrome_id, name: pin.label, coverArt: pin.cover })
  }

  const move = (pin: Pin, from: number, by: -1 | 1) => {
    const to = from + by
    if (pin.pending || to < 0 || to >= pins.length) return
    refocus.current = { key: pinKey(pin), which: by < 0 ? 'up' : 'down' }
    onMove(pinKey(pin), to)
    setSaid(`${pin.label}: ${to + 1} of ${pins.length}`)
  }
  const remove = (pin: Pin, index: number) => {
    if (pin.pending) return
    const next = pins[index + 1] ?? pins[index - 1]
    refocus.current = next ? { key: pinKey(next), which: 'remove' } : 'edit'
    onRemove(pinKey(pin))
    setSaid(`${pin.label} unpinned`)
  }
  const toggleEditing = () => {
    //? Done with nothing left pinned takes the button away: focus to the heading, not the page
    if (editing && !pins.length) refocus.current = 'heading'
    setEditing(!editing)
  }

  //? the drag: by the grip only, one pointer, the rows' pitch measured as it starts
  const startDrag = (event: PointerEvent, pin: Pin, index: number) => {
    if (drag || pin.pending || event.button > 0) return
    const grip = event.currentTarget as HTMLElement
    const row = grip.closest('li')
    if (!row) return
    const next = row.nextElementSibling as HTMLElement | null
    const before = row.previousElementSibling as HTMLElement | null
    const pitch = next ? next.offsetTop - row.offsetTop : before ? row.offsetTop - before.offsetTop : row.offsetHeight
    grip.setPointerCapture?.(event.pointerId)
    event.preventDefault()
    setDrag({ key: pinKey(pin), start: index, y: event.clientY, dy: 0, pitch, pointer: event.pointerId })
  }
  const followDrag = (event: PointerEvent) => {
    if (drag && event.pointerId === drag.pointer) setDrag({ ...drag, dy: event.clientY - drag.y })
  }
  const endDrag = (event: PointerEvent) => {
    if (!drag || event.pointerId !== drag.pointer) return
    const to = dropIndex(drag.start, event.clientY - drag.y, drag.pitch, pins.length)
    setDrag(null)
    if (to === drag.start) return
    onMove(drag.key, to)
    const pin = pins[drag.start]
    if (pin) setSaid(`${pin.label}: ${to + 1} of ${pins.length}`)
  }
  const dropDrag = (event: PointerEvent) => {
    if (drag && event.pointerId === drag.pointer) setDrag(null)
  }

  return (
    <section class="app-section app-pinned" aria-labelledby="app-pinned-title">
      <div class="app-section-head app-pinned-head">
        <h2 id="app-pinned-title" ref={heading} tabIndex={-1} class="app-section-title">Pinned</h2>
        {(pins.length > 0 || editing) && (
          <button ref={editButton} type="button" class="app-text-button app-pinned-edit" onClick={toggleEditing}>
            {editing ? 'Done' : 'Edit'}
          </button>
        )}
      </div>
      {/* what an Edit changed, read out - always in the page, as iOS reads only a region already there */}
      <p class="app-visually-hidden" role="status" aria-live="polite" aria-atomic="true">{said}</p>

      {!pins.length ? (
        <p class="app-pinned-empty">{NOTHING_PINNED}</p>
      ) : editing ? (
        <ol ref={list} class="app-pins-edit">
          {pins.map((pin, index) => {
            const key = pinKey(pin)
            const dragging = drag?.key === key
            const offset = drag ? dragOffset(index, drag.start, landing, drag.dy, drag.pitch) : 0
            return (
              <li
                key={key}
                data-pin={key}
                class={`app-pin-row app-card${dragging ? ' is-dragging' : ''}${pin.pending ? ' is-pending' : ''}${pinOpens(pin) ? '' : ' is-closed'}`}
                style={offset ? { transform: `translateY(${offset}px)` } : undefined}
              >
                <span class="app-pin-text">
                  <span class="app-pin-title">{pin.label}</span>
                  <span class="app-pin-line">{pinLine(pin)}</span>
                </span>
                <button
                  type="button"
                  class="app-pin-move app-pin-up"
                  aria-label={`Move ${pin.label} up`}
                  aria-disabled={index === 0 || !!pin.pending}
                  onClick={() => move(pin, index, -1)}
                >
                  <span class="app-pin-move-face">
                    <ChevronUpIcon class="app-pin-move-icon" />
                  </span>
                </button>
                <button
                  type="button"
                  class="app-pin-move app-pin-down"
                  aria-label={`Move ${pin.label} down`}
                  aria-disabled={index === pins.length - 1 || !!pin.pending}
                  onClick={() => move(pin, index, 1)}
                >
                  <span class="app-pin-move-face">
                    <ChevronDownIcon class="app-pin-move-icon" />
                  </span>
                </button>
                <button
                  type="button"
                  class="app-pin-move app-pin-remove"
                  aria-label={`Unpin ${pin.label}`}
                  aria-disabled={!!pin.pending}
                  onClick={() => remove(pin, index)}
                >
                  <span class="app-pin-move-face">
                    <CloseIcon class="app-pin-move-icon" />
                  </span>
                </button>
                <span
                  class="app-pin-grip"
                  aria-hidden="true"
                  onPointerDown={(event) => startDrag(event, pin, index)}
                  onPointerMove={followDrag}
                  onPointerUp={endDrag}
                  onPointerCancel={dropDrag}
                  onLostPointerCapture={dropDrag}
                >
                  <GripIcon class="app-pin-grip-icon" />
                </span>
              </li>
            )
          })}
        </ol>
      ) : (
        <ul class="app-pins">
          {pins.map((pin) => {
            const face = (
              <>
                <Cover id={pin.cover} size={96} class={`app-pin-thumb${pin.kind === 'artist' ? ' is-round' : ''}`} />
                <span class="app-pin-text">
                  <span class="app-pin-title">{pin.label}</span>
                  <span class="app-pin-line">{pinLine(pin)}</span>
                </span>
              </>
            )
            return (
              <li key={pinKey(pin)} class="app-pins-item">
                {pinOpens(pin) ? (
                  <button
                    type="button"
                    class={`app-pin-card is-${pin.kind}`}
                    onPointerDown={() => pin.kind === 'album' && pin.navidrome_id && prefetchAlbum(pin.navidrome_id)}
                    onPointerCancel={() => pin.kind === 'album' && pin.navidrome_id && dropPrefetch(pin.navidrome_id)}
                    onClick={() => open(pin)}
                  >
                    {face}
                  </button>
                ) : (
                  <div class={`app-pin-card is-${pin.kind} is-closed`}>{face}</div>
                )}
              </li>
            )
          })}
        </ul>
      )}
      {/* one of Edit's changes not kept: under the list, so its arriving and going move no row - and a
          region always in the page, read out as it arrives */}
      <p class={`app-pinned-note${problem ? ' is-said' : ''}`} role="status" aria-live="polite" aria-atomic="true">{problem}</p>
    </section>
  )
}
