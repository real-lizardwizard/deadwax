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

/** Up Next (2.0.0-player.57): lines of a list, the last one short beside a small play triangle - what plays next. */
export const QueueIcon = line(
  <>
    <path d="M4 6.5h16M4 12h16M4 17.5h9" />
    <path d="M16.5 15v5.5l4.5-2.75z" fill="currentColor" />
  </>,
)

/** Repeat (2.0.0-player.57): two arrows chasing each other round a loop, as ShuffleIcon's line. */
export const RepeatIcon = line(
  <>
    <path d="M17 3.5 20 6.5l-3 3" />
    <path d="M4 11.5V10a3.5 3.5 0 0 1 3.5-3.5H20" />
    <path d="M7 20.5 4 17.5l3-3" />
    <path d="M20 12.5V14a3.5 3.5 0 0 1-3.5 3.5H4" />
  </>,
)

/** Repeat One: the same loop, and a "1" inside it. */
export const RepeatOneIcon = line(
  <>
    <path d="M17 3.5 20 6.5l-3 3" />
    <path d="M4 11.5V10a3.5 3.5 0 0 1 3.5-3.5H20" />
    <path d="M7 20.5 4 17.5l3-3" />
    <path d="M20 12.5V14a3.5 3.5 0 0 1-3.5 3.5H4" />
    <path d="M11.2 10.6l1.3-.9v4.6" stroke-width="1.8" />
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

/** (2.1.6) Lyrics: a speech bubble holding a quote mark, as Apple Music's button has it - in the set's own line, its
 *  tail at the bottom left; the quote mark's two commas filled, their tails a finer stroke, as RepeatOneIcon's one. */
export const LyricsIcon = line(
  <>
    <path d="M6 4h12a2.5 2.5 0 0 1 2.5 2.5V14a2.5 2.5 0 0 1-2.5 2.5h-7L7 20v-3.5H6A2.5 2.5 0 0 1 3.5 14V6.5A2.5 2.5 0 0 1 6 4z" />
    <circle cx="9.6" cy="11.6" r="1.35" fill="currentColor" stroke="none" />
    <circle cx="14.6" cy="11.6" r="1.35" fill="currentColor" stroke="none" />
    <path d="M8.3 11.4c0-1.5.6-2.5 1.9-3.2M13.3 11.4c0-1.5.6-2.5 1.9-3.2" stroke-width="1.6" />
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

/** (2.1.35) Settings - the fifth tab, You until then, as the iPhone app names it: a gear of eight teeth round its hub,
 *  in the tab bar's finer line as its four neighbours are. (YouIcon, the head and shoulders it replaced, went.) */
export const SettingsIcon = thin(
  <>
    <path d="M10.43 5.18L10.69 2.69A9.4 9.4 0 0 1 13.31 2.69L13.57 5.18A7 7 0 0 1 15.71 6.06L17.66 4.49A9.4 9.4 0 0 1 19.51 6.34L17.94 8.29A7 7 0 0 1 18.82 10.43L21.31 10.69A9.4 9.4 0 0 1 21.31 13.31L18.82 13.57A7 7 0 0 1 17.94 15.71L19.51 17.66A9.4 9.4 0 0 1 17.66 19.51L15.71 17.94A7 7 0 0 1 13.57 18.82L13.31 21.31A9.4 9.4 0 0 1 10.69 21.31L10.43 18.82A7 7 0 0 1 8.29 17.94L6.34 19.51A9.4 9.4 0 0 1 4.49 17.66L6.06 15.71A7 7 0 0 1 5.18 13.57L2.69 13.31A9.4 9.4 0 0 1 2.69 10.69L5.18 10.43A7 7 0 0 1 6.06 8.29L4.49 6.34A9.4 9.4 0 0 1 6.34 4.49L8.29 6.06A7 7 0 0 1 10.43 5.18z" />
    <circle cx="12" cy="12" r="3" />
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

/** An "i" in a circle - the desktop player bar's Info, as DesktopLibrary.dc.html draws it. */
export const InfoIcon = thin(
  <>
    <circle cx="12" cy="12" r="8.5" />
    <path d="M12 11v5.5M12 7.8v.2" />
  </>,
)

/** Five bars of a spectrum - the desktop player bar's full-screen visualizer (2.0.0-player.20), as
 *  DesktopLibrary.dc.html draws it. */
export const VisualizerIcon = thin(<path d="M4 14v-4M8 18V6M12 15V9M16 20V4M20 14v-4" />)

/** Four corners turned in - the visualizer's "Leave full screen", as DesktopVisualizer.dc.html draws it. */
export const LeaveFullScreenIcon = line(<path d="M9 3.5V9H3.5M15 3.5V9h5.5M9 20.5V15H3.5M15 20.5V15h5.5" />)

/** A row's "goes somewhere" mark. */
export const ChevronRightIcon = line(<path d="m9 6 6 6-6 6" />)

/** Up a place - Home's Edit, beside the drag. */
export const ChevronUpIcon = line(<path d="M6 14.5l6-6 6 6" />)

/**
 * A pin (2.0.0-player.18), as Album.dc.html and Artist.dc.html draw it: its head and its point. The
 * head is filled once the thing is pinned - by CSS on `.app-pin-head`, so one glyph serves both.
 */
export function PinIcon({ class: cls }: IconProps) {
  return (
    <svg class={cls} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
      <path class="app-pin-head" d="M9 3.5h6l-1 6.5 3.5 3.5h-11L10 10z" />
      <path d="M12 13.5v7" />
    </svg>
  )
}

/** (2.0.0-player.58) a playlist: three lines of a list and a note beside them - the line set's style */
export const PlaylistIcon = line(
  <>
    <path d="M4 6.5h10M4 11.5h10M4 16.5h6" />
    <path d="M17.5 17.5V8.5l3-1" />
    <circle cx="15.8" cy="17.6" r="1.8" />
  </>,
)

/** (2.0.10) the Library's other rows, in the playlist glyph's line style (James: "a record for albums and a silhouette
 *  for artists"). An album: a record - its edge, the label round the spindle hole, and one groove catching the light */
export const AlbumIcon = line(
  <>
    <circle cx="12" cy="12" r="8.5" />
    <circle cx="12" cy="12" r="2.6" />
    <path d="M7.4 9.6a5.2 5.2 0 0 1 2.2-2.2" />
  </>,
)

/** ...an artist: a head and shoulders */
export const ArtistIcon = line(
  <>
    <circle cx="12" cy="8.3" r="3.6" />
    <path d="M5 20c.9-3.9 3.6-6.1 7-6.1s6.1 2.2 7 6.1" />
  </>,
)

/** ...a song: one note, the playlist glyph's own */
export const SongIcon = line(
  <>
    <path d="M14 17.5V5.5l4 1.2" />
    <circle cx="11.9" cy="17.6" r="2.1" />
  </>,
)

/** ...and adding to one: the list with a plus */
export const PlaylistAddIcon = line(<path d="M4 6.5h11M4 11.5h11M4 16.5h7M17.5 13.5v7M14 17h7" />)

/* (2.1.35) the desktop sidebar's other rows, in the same line set - app/Sidebar.tsx draws every row's glyph at one
   weight (app-desktop.css's --app-desk-side-stroke), so these and the tab bar's finer two sit together */

/** Recently added: a clock, its hands at a little past four */
export const ClockIcon = line(
  <>
    <circle cx="12" cy="12" r="8.5" />
    <path d="M12 7.5V12l3.2 1.9" />
  </>,
)

/** Needs a look: a flag on its pole - something marked to come back to */
export const FlagIcon = line(<path d="M6 20.5V4M6 4.5h10.5l-2.6 4.25 2.6 4.25H6" />)

/** Library care: a first-aid kit - its case, its handle and the cross on it */
export const CareIcon = line(
  <>
    <rect x="3.5" y="7" width="17" height="12.5" rx="2" />
    <path d="M9 7V5.5A1.5 1.5 0 0 1 10.5 4h3A1.5 1.5 0 0 1 15 5.5V7M12 10.5v5.5M9.25 13.25h5.5" />
  </>,
)

/** People: one head and shoulders, and another behind it - ArtistIcon's, two of them */
export const PeopleIcon = line(
  <>
    <circle cx="9" cy="8.6" r="3.3" />
    <path d="M3 19.5c.8-3.5 3.1-5.4 6-5.4s5.2 1.9 6 5.4M15.4 5.5a3.2 3.2 0 0 1 0 6.2M17.4 14.4c1.9.6 3.1 2.3 3.6 5.1" />
  </>,
)

/** Server settings: a server - two units in a rack, a light on each */
export const ServerIcon = line(
  <>
    <rect x="3.5" y="4" width="17" height="7" rx="1.5" />
    <rect x="3.5" y="13" width="17" height="7" rx="1.5" />
    <path d="M7.25 7.5h.01M7.25 16.5h.01" />
  </>,
)

/** Event log: a page with its corner turned and lines written on it */
export const LogIcon = line(
  <>
    <path d="M14.5 3.5H7.5a1 1 0 0 0-1 1v15a1 1 0 0 0 1 1h9a1 1 0 0 0 1-1v-13zM14.5 3.5v3h3" />
    <path d="M9.5 11h5M9.5 14h5M9.5 17h3" />
  </>,
)

/** Three lines - what a row in Home's Edit is dragged by. */
export const GripIcon = thin(<path d="M5 8h14M5 12h14M5 16h14" />)

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
