import { Cover } from './Cover'
import { NextIcon, PauseIcon, PlayIcon } from './icons'
import { usePosition, type Player } from './usePlayer'

/** The hairline along the bottom - its own component, so only it re-renders as the song plays. */
function Progress({ player }: { player: Player }) {
  const position = usePosition(player)
  const done = player.duration ? Math.min(position / player.duration, 1) : 0
  return <span class="pl-mini-progress" style={{ transform: `scaleX(${done})` }} />
}

/**
 * The mini player's name to a screen reader (2.0.7, UX batch 4): what it shows, then what a tap does - "Now
 * playing: Roads, Portishead - open". It was "Open now playing", which hid the song: a name given with
 * aria-label is all VoiceOver reads of the button. The second part is the line under the title - the artist, or
 * the notice shown in its place ("Skipped …"), so a listener hears what a sighted one reads.
 */
export function miniPlayerLabel(title: string, line: string | null | undefined): string {
  return `Now playing: ${title}${line ? `, ${line}` : ''} - open`
}

/**
 * What's playing, kept at the bottom of every screen. Tapping it opens the full player - and the
 * tap's own event goes with it, so App can have the button focus itself and give focus back to it
 * when the sheet closes (app/useSheet.ts's takeOpener).
 */
export function MiniPlayer({ player, onOpen }: { player: Player; onOpen: (event: MouseEvent) => void }) {
  const track = player.track
  if (!track) return null

  return (
    <div class="pl-mini">
      <button type="button" class="pl-mini-open" onClick={onOpen} aria-label={miniPlayerLabel(track.title, player.error ?? track.artist)}>
        <Cover id={track.coverArt} size={120} class="pl-mini-cover" />
        <span class="pl-mini-text">
          <span class="pl-mini-title" dir="auto">{track.title}</span>
          <span class="pl-mini-artist" dir="auto">{player.error ?? track.artist}</span>
        </span>
      </button>
      <button
        type="button"
        class={`pl-icon-button${player.buffering ? ' is-busy' : ''}`}
        onClick={player.toggle}
        aria-label={player.playing ? 'Pause' : 'Play'}
      >
        {player.playing ? <PauseIcon class="pl-icon" /> : <PlayIcon class="pl-icon" />}
      </button>
      <button type="button" class="pl-icon-button" onClick={player.next} aria-label="Next">
        <NextIcon class="pl-icon" />
      </button>
      <Progress player={player} />
    </div>
  )
}
