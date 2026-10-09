import { Cover } from './Cover'
import { SpeedChip } from './SpeedChip'
import { AirPlayIcon, InfoIcon, NextIcon, PauseIcon, PlayIcon, PreviousIcon, VisualizerIcon } from './icons'
import { Scrubber } from './NowPlaying'
import type { Player } from './usePlayer'

/**
 * The desktop's player (2.0.0-player.19), a bar along the bottom of every screen as
 * DesktopLibrary.dc.html draws it - where the phone has the mini player and Now Playing's sheet:
 *
 *  - at the left, the song: its cover, its title, and "Artist — Album", which goes to the album on
 *    the tab showing (App's Go to album), as Now Playing's line does - or the song's failure, in its
 *    place, as the mini player says it;
 *  - in the middle, previous, a round play or pause, next, and under them the scrubber - Now
 *    Playing's own (it seeks as the pointer lets go or a key steps, never on the way), its two
 *    clocks at its ends;
 *  - at the right, AirPlay when there is a speaker to send to, Info, which opens Info as the side
 *    panel (and closes it), and - since 2.0.0-player.20, at the end of the row as DesktopLibrary.dc.html
 *    draws it - the full-screen visualizer (player/Visualizer.tsx), which App opens from its click:
 *    the click is the gesture its audio context and full screen need. There is no turntable on a
 *    desktop (James: "I don't think it makes a lot of sense on desktop") - the visualizer is the
 *    desktop's. And before them all, the speed's chip (2.0.0-player.39, player/SpeedChip.tsx): "1.25x"
 *    wherever the speed isn't 1x - set on the phone's turntable, an iPad turned on its side would
 *    otherwise play it with nothing here saying so - and a tap on it back to 1x. The tools sit at the
 *    row's right end, so the chip coming and going moves none of them.
 *
 * Its transport calls the player straight from the click - nothing awaited, the gesture rule
 * (ui/test/app-rules.sim.cjs allows this file toggle, next, previous and showAirPlay). With nothing
 * playing it keeps its place and says so: a bar that came and went would move the page above it.
 */
export function PlayerBar({
  player,
  onAlbum,
  onInfo,
  infoOpen,
  onVisualizer,
}: {
  player: Player
  /** "Artist — Album": the song's album, on the tab showing; null when the song names none */
  onAlbum: (() => void) | null
  /** Info's click - the event, so App can take the button as what the panel gives focus back to */
  onInfo: (event: MouseEvent) => void
  /** the Info panel is showing */
  infoOpen: boolean
  /** the visualizer's click - the event, so App can take the button as what focus goes back to */
  onVisualizer: (event: MouseEvent) => void
}) {
  const track = player.track
  if (!track) {
    return (
      <section class="app-playbar" aria-label="Player">
        <p class="app-playbar-idle">Nothing playing</p>
      </section>
    )
  }

  //? "Artist — Album", as Now Playing has it; either alone when the other isn't known
  const byline = [track.artist, track.album].filter(Boolean).join(' — ')

  return (
    <section class="app-playbar" aria-label="Player">
      <div class="app-playbar-now">
        <Cover id={track.coverArt} size={120} class="app-playbar-cover" />
        <span class="app-playbar-text">
          <span class="app-playbar-title">{track.title}</span>
          {player.error ? (
            <span class="app-playbar-byline is-error">{player.error}</span>
          ) : onAlbum ? (
            <button type="button" class="app-playbar-byline is-link" onClick={onAlbum} aria-label={`Go to the album: ${byline}`}>
              {byline}
            </button>
          ) : (
            <span class="app-playbar-byline">{byline}</span>
          )}
        </span>
      </div>

      <div class="app-playbar-middle">
        <div class="app-playbar-transport">
          <button type="button" class="app-playbar-button" onClick={() => player.previous()} aria-label="Previous">
            <PreviousIcon class="app-playbar-icon" />
          </button>
          <button
            type="button"
            class={`app-playbar-play${player.buffering ? ' is-busy' : ''}`}
            onClick={() => player.toggle()}
            aria-label={player.playing ? 'Pause' : 'Play'}
          >
            {player.playing ? <PauseIcon class="app-playbar-play-icon" /> : <PlayIcon class="app-playbar-play-icon" />}
          </button>
          <button type="button" class="app-playbar-button" onClick={() => player.next()} aria-label="Next">
            <NextIcon class="app-playbar-icon" />
          </button>
        </div>
        <Scrubber player={player} />
      </div>

      <div class="app-playbar-tools">
        <SpeedChip player={player} />
        {player.airplay && (
          <button type="button" class="app-playbar-button" onClick={() => player.showAirPlay()} aria-label="AirPlay">
            <AirPlayIcon class="app-playbar-icon" />
          </button>
        )}
        <button
          type="button"
          class={`app-playbar-button${infoOpen ? ' is-on' : ''}`}
          onClick={onInfo}
          aria-label="Info"
          aria-expanded={infoOpen}
        >
          <InfoIcon class="app-playbar-icon" />
        </button>
        <button type="button" class="app-playbar-button" onClick={onVisualizer} aria-label="Full-screen visualizer">
          <VisualizerIcon class="app-playbar-icon" />
        </button>
      </div>
    </section>
  )
}
