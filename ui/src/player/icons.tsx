/**
 * The player's glyphs, drawn here rather than borrowed: SF Symbols can't be used on the web, and
 * a font of icons would be a download for eight shapes. All take their colour from the text.
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
