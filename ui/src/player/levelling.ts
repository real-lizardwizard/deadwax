/**
 * The player's Normalization at the tap (2.0.0-player.62): the songs about to be queued, at the level the
 * setting gives them - queued as an album, or as songs (lib/loudness.ts levelFor() has the table). The one
 * impure line of it: the setting is read from this device's storage, synchronously, so it sits in the tap
 * with nothing awaited before the player is called (the gesture rule - see "The one app" in CLAUDE.md).
 *
 * Every call site that queues songs passes them through this (ui/test/app-rules.sim.cjs pins it): one that
 * didn't would queue them with no level, and they would play as under Off - never at a wrong level. A change
 * of setting applies from the next thing played: what is queued keeps the level it was queued at.
 */

import { levelled, type LevelledTrack, type QueuedAs } from '../lib/loudness'
import type { QueueTrack } from '../lib/playQueue'
import { isFlac } from '../lib/streamWrap'
import { readPlayerNormalization } from '../state/persisted'
import { warmLevels, type AlbumWithSongs } from './api'

export function queued<T extends QueueTrack>(tracks: T[], as: QueuedAs): Array<T & LevelledTrack> {
  return levelled(tracks, readPlayerNormalization(), as)
}

/**
 * (2.0.0-player.65, the 2.0.0 release review) An album about to be played, warmed - its album page as it opens, and
 * a play from Search, Requests or an artist's Play right after its tap's playTracks (never before it, and nothing
 * awaited: the tap is the player's). Not under Off, and not for an album with no FLAC song, which nothing levels.
 * The setting is read as queued() reads it: a storage read, synchronous.
 */
export function warmAlbum(album: Pick<AlbumWithSongs, 'id' | 'song'>): void {
  if (readPlayerNormalization() === 'off') return
  if ((album.song ?? []).some((song) => isFlac({ suffix: song.suffix ?? null, contentType: song.contentType ?? null }))) {
    warmLevels(album.id)
  }
}
