import { Cover } from './Library'
import { NextIcon, PauseIcon, PlayIcon } from './icons'
import { usePosition, type Player } from './usePlayer'

/** The hairline along the bottom - its own component, so only it re-renders as the song plays. */
function Progress({ player }: { player: Player }) {
  const position = usePosition(player)
  const done = player.duration ? Math.min(position / player.duration, 1) : 0
  return <span class="pl-mini-progress" style={{ transform: `scaleX(${done})` }} />
}

/** What's playing, kept at the bottom of every screen. Tapping it opens the full player. */
export function MiniPlayer({ player, onOpen }: { player: Player; onOpen: () => void }) {
  const track = player.track
  if (!track) return null

  return (
    <div class="pl-mini">
      <button type="button" class="pl-mini-open" onClick={onOpen} aria-label="Open now playing">
        <Cover id={track.coverArt} size={120} class="pl-mini-cover" />
        <span class="pl-mini-text">
          <span class="pl-mini-title">{track.title}</span>
          <span class="pl-mini-artist">{player.error ?? track.artist}</span>
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
