import { useCallback, useState } from 'preact/hooks'

import {
  clampWidth, defaultOrder, moveColumn, reconcileOrder, reconcileVisible, reconcileWidths,
  TRACK_FIELDS,
} from '../lib/trackFields'
import { readLibraryFields, writeLibraryFields } from '../state/persisted'

const everyId = () => TRACK_FIELDS.map((field) => field.id)

interface Layout {
  /** The fields ticked in the menu, in registry order. The title is always shown, so never here. */
  visible: string[]
  /** Every column including the title, in the order they are drawn. */
  order: string[]
  /** Columns dragged to a width, in px. */
  widths: Record<string, number>
}

export interface TrackFieldsState extends Layout {
  toggle: (id: string, on: boolean) => void
  /** Move a column to just before another, or to the end when `before` is null. */
  move: (id: string, before: string | null) => void
  /** Size a column in px, or null to give it back its own width. */
  resize: (id: string, width: number | null) => void
  /** Pin several columns to px at once - a resize freezes the flexible ones to its left. */
  pin: (widths: Readonly<Record<string, number>>) => void
  /** Everything back to how it started: which fields, their order and their widths. */
  reset: () => void
}

function initial(): Layout {
  const saved = readLibraryFields()
  return {
    visible: reconcileVisible(saved),
    order: reconcileOrder(saved?.order),
    widths: reconcileWidths(saved?.widths),
  }
}

const sameOrder = (a: readonly string[], b: readonly string[]) =>
  a.length === b.length && a.every((id, i) => id === b[i])

/**
 * Which fields the track viewer shows, in what order and how wide, remembered in this browser.
 *
 * One hook instance, in the details pane, and the menu and the table both read from it -
 * two instances would each hold their own copy and the menu would stop moving the columns.
 * Which fields are ticked is kept in registry order whatever order they were ticked in; where
 * they are DRAWN is `order`, which changes only when you drag a header.
 */
export function useTrackFields(): TrackFieldsState {
  const [layout, setLayout] = useState(initial)

  /*
   * The one writer. `seen` is every field that exists NOW, so a field added later can tell
   * "you turned me off" from "you were never asked" - see reconcileVisible. The order goes in
   * only once it differs from the default, and the widths only once there are some, so a later
   * version's defaults still reach everyone who never arranged anything.
   */
  const commit = useCallback((change: (current: Layout) => Layout) => {
    setLayout((current) => {
      const next = change(current)
      writeLibraryFields({
        visible: next.visible,
        seen: everyId(),
        ...(sameOrder(next.order, defaultOrder()) ? {} : { order: next.order }),
        ...(Object.keys(next.widths).length ? { widths: next.widths } : {}),
      })
      return next
    })
  }, [])

  const toggle = useCallback((id: string, on: boolean) => commit((current) => ({
    ...current,
    visible: TRACK_FIELDS
      .filter((field) => (field.id === id ? on : current.visible.includes(field.id)))
      .map((field) => field.id),
  })), [commit])

  const move = useCallback((id: string, before: string | null) => commit((current) => ({
    ...current,
    order: moveColumn(current.order, id, before),
  })), [commit])

  const resize = useCallback((id: string, width: number | null) => commit((current) => {
    const widths = { ...current.widths }
    if (width === null) delete widths[id]
    else widths[id] = clampWidth(width)
    return { ...current, widths }
  }), [commit])

  /*
   * One write, so the pinned neighbours and the dragged column cannot land in separate renders
   * with a reflow in between - which is the flicker this whole freeze exists to remove.
   */
  const pin = useCallback((widths: Readonly<Record<string, number>>) => commit((current) => ({
    ...current,
    widths: {
      ...current.widths,
      ...Object.fromEntries(Object.entries(widths).map(([id, px]) => [id, clampWidth(px)])),
    },
  })), [commit])

  const reset = useCallback(() => commit(() => ({
    visible: TRACK_FIELDS.filter((field) => field.initial).map((field) => field.id),
    order: defaultOrder(),
    widths: {},
  })), [commit])

  return { ...layout, toggle, move, resize, pin, reset }
}
