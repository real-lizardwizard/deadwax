/**
 * The app's glyphs, drawn here rather than borrowed: SF Symbols can't be used on the web, and a
 * font of icons would be a download for a few shapes. All take their colour from the text. The tab
 * bar's five are the canvas boards' own paths.
 */

import type { ComponentChildren } from 'preact'

type IconProps = { class?: string }

const solid = (path: ComponentChildren) => ({ class: cls }: IconProps) => (
  <svg class={cls} viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
    {path}
  </svg>
)

const line = (path: ComponentChildren) => ({ class: cls }: IconProps) => (
  <svg
    class={cls}
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    stroke-width="2.2"
    stroke-linecap="round"
    stroke-linejoin="round"
    aria-hidden="true"
  >
    {path}
  </svg>
)

/** The tab bar's strokes are finer, as the boards draw them. */
const thin = (path: ComponentChildren) => ({ class: cls }: IconProps) => (
  <svg
    class={cls}
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    stroke-width="1.8"
    stroke-linecap="round"
    stroke-linejoin="round"
    aria-hidden="true"
  >
    {path}
  </svg>
)

export const PlayIcon = solid(<path d="M7 4.9v14.2a1 1 0 0 0 1.52.85l11.3-7.1a1 1 0 0 0 0-1.7L8.52 4.05A1 1 0 0 0 7 4.9z" />)

export const PauseIcon = solid(
  <>
    <rect x="5.5" y="4" width="4.5" height="16" rx="1.2" />
    <rect x="14" y="4" width="4.5" height="16" rx="1.2" />
  </>,
)

export const NextIcon = solid(
  <path d="M2.5 6.2v11.6a.8.8 0 0 0 1.25.66L12 13v4.8a.8.8 0 0 0 1.25.66l8.5-5.8a.8.8 0 0 0 0-1.32l-8.5-5.8A.8.8 0 0 0 12 6.2V11L3.75 5.54a.8.8 0 0 0-1.25.66z" />,
)

export const PreviousIcon = solid(
  <path d="M21.5 6.2v11.6a.8.8 0 0 1-1.25.66L12 13v4.8a.8.8 0 0 1-1.25.66l-8.5-5.8a.8.8 0 0 1 0-1.32l8.5-5.8A.8.8 0 0 1 12 6.2V11l8.25-5.46a.8.8 0 0 1 1.25.66z" />,
)

export const ShuffleIcon = line(
  <>
    <path d="M3 7h3.5c4 0 6 10 10 10H20" />
    <path d="M3 17h3.5c1.6 0 2.8-1.6 3.9-3.6" />
    <path d="M13.6 10.6C14.7 8.6 15 7 16.5 7H20" />
    <path d="M17.5 4.5 20 7l-2.5 2.5" />
    <path d="M17.5 14.5 20 17l-2.5 2.5" />
  </>,
)

export const ChevronDownIcon = line(<path d="M6 9.5l6 6 6-6" />)

export const ChevronLeftIcon = line(<path d="M15 5l-7 7 7 7" />)

export const AirPlayIcon = line(
  <>
    <path d="M6.5 17.5H4.5a2 2 0 0 1-2-2v-10a2 2 0 0 1 2-2h15a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2h-2" />
    <path d="M12 14.5l4.5 6h-9z" fill="currentColor" />
  </>,
)

/** Three dots in a row - "more": Now Playing's menu, as the board draws it. */
export const MoreIcon = solid(
  <>
    <circle cx="5" cy="12" r="2" />
    <circle cx="12" cy="12" r="2" />
    <circle cx="19" cy="12" r="2" />
  </>,
)

/* Now Playing's look button (2.0.0-player.11), as the boards draw it: a record on the cover,
   a square - the cover - on the turntable. */
export const RecordIcon = thin(
  <>
    <circle cx="12" cy="12" r="8.5" />
    <circle cx="12" cy="12" r="2.5" />
  </>,
)

export const SquareIcon = thin(<rect x="4.5" y="4.5" width="15" height="15" rx="2" />)

/* ===== the tab bar's five, as the canvas boards draw them ===== */

export const HomeIcon = thin(<path d="M3.5 10.5 12 3.5l8.5 7V20a1 1 0 0 1-1 1H15v-6H9v6H4.5a1 1 0 0 1-1-1z" />)

/** Two spines and a leaning one - albums on a shelf. */
export const LibraryIcon = thin(<path d="M5 4v16M10 4v16M15 4.5l4.5 15" />)

export const SearchIcon = thin(
  <>
    <circle cx="11" cy="11" r="6.5" />
    <path d="m20 20-4.2-4.2" />
  </>,
)

/** An arrow down into a tray - what's coming. */
export const RequestsIcon = thin(
  <>
    <path d="M12 4v11m0 0-4.5-4.5M12 15l4.5-4.5" />
    <path d="M4.5 16.5V19a1.5 1.5 0 0 0 1.5 1.5h12a1.5 1.5 0 0 0 1.5-1.5v-2.5" />
  </>,
)

/** An arrow down onto a line - "Get the album", as Request.dc.html draws it. */
export const GetIcon = line(<path d="M12 4v11m0 0-4.5-4.5M12 15l4.5-4.5M5 19.5h14" />)

export const YouIcon = thin(
  <>
    <circle cx="12" cy="8.5" r="3.8" />
    <path d="M4.5 20.5c1.2-3.8 4-5.8 7.5-5.8s6.3 2 7.5 5.8" />
  </>,
)

/** A cross - cancel a download, as the Requests board draws it (its stroke a little heavier). */
export function CloseIcon({ class: cls }: IconProps) {
  return (
    <svg class={cls} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" aria-hidden="true">
      <path d="M6 6l12 12M18 6 6 18" />
    </svg>
  )
}

/** A row's "goes somewhere" mark. */
export const ChevronRightIcon = line(<path d="m9 6 6 6-6 6" />)

/** The tick beside the chosen row of a list, as iOS's settings draw it. */
export const CheckIcon = line(<path d="M4.5 12.5l5 5L19.5 6.5" />)

/** Three bars that rise and fall - the "this is the one playing" mark in a track list. */
export function PlayingBars({ paused }: { paused: boolean }) {
  return (
    <span class={`pl-bars${paused ? ' is-paused' : ''}`} aria-label={paused ? 'paused' : 'playing'}>
      <i />
      <i />
      <i />
    </span>
  )
}
