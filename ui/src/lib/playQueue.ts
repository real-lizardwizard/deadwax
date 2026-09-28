/**
 * The player's queue, and the judgements a player makes that are easy to get subtly wrong: what
 * "previous" means, when a song counts as played - which rests on how much of it was actually
 * heard, measured update by update in listenedStep(), and counted per listen - and what to do
 * when a song won't play.
 *
 * Pure, like the rest of lib/, so ui/test/playqueue.sim.cjs can hold it to the answers without a
 * browser - the audio element and the lock screen live in player/usePlayer.ts and only ask this.
 */

/** One song as the queue needs it: enough to play it, label it and show its cover. */
export interface QueueTrack {
  id: string
  title: string
  artist: string
  album: string
  albumId: string | null
  coverArt: string | null
  /** seconds, from Navidrome's tags; 0 when it doesn't know */
  duration: number
  /** e.g. audio/flac - checked against what the browser can play before asking for a transcode */
  contentType: string | null
  /** the file's extension, e.g. opus - what tells an Opus file from a Vorbis one, since Navidrome
   *  gives both the same audio/ogg (see streamUrl in player/api.ts) */
  suffix: string | null
}

export interface PlayQueue {
  tracks: QueueTrack[]
  /** the song playing, or -1 for nothing */
  index: number
}

export const EMPTY_QUEUE: PlayQueue = { tracks: [], index: -1 }

/**
 * How far into a song "previous" restarts it instead of going back one. Three seconds is what
 * Apple Music and most players do: press it mid-song and you hear the song again from the top,
 * press it twice and you get the one before.
 */
export const RESTART_AFTER_SECONDS = 3

export function current(queue: PlayQueue): QueueTrack | null {
  return queue.tracks[queue.index] ?? null
}

/**
 * A queue of these tracks, starting at `start`. Shuffled, it plays everything once in a random
 * order - starting from the song asked for, if one was, so tapping a song with shuffle on still
 * plays THAT song first. `start` null asks for no song in particular (the Shuffle button), and
 * then the first song is as random as the rest: it was always the album's opener until 1.0.3.
 */
export function startQueue(
  tracks: QueueTrack[],
  start: number | null,
  shuffle = false,
  random: () => number = Math.random,
): PlayQueue {
  if (!tracks.length) return EMPTY_QUEUE
  const index = Math.min(Math.max(start ?? 0, 0), tracks.length - 1)
  if (!shuffle) return { tracks: [...tracks], index }

  const rest = start === null ? [...tracks] : tracks.filter((_, i) => i !== index)
  for (let i = rest.length - 1; i > 0; i--) {
    const j = Math.floor(random() * (i + 1))
    ;[rest[i], rest[j]] = [rest[j]!, rest[i]!]
  }
  return { tracks: start === null ? rest : [tracks[index]!, ...rest], index: 0 }
}

/** The song after this one, or null at the end of the queue - which is where playing stops. */
export function nextIndex(queue: PlayQueue): number | null {
  const next = queue.index + 1
  return next < queue.tracks.length ? next : null
}

export type PreviousAction = { kind: 'restart' } | { kind: 'go'; index: number }

/** What "previous" does at this position in the song. The first song only ever restarts. */
export function previousAction(queue: PlayQueue, position: number): PreviousAction {
  if (position > RESTART_AFTER_SECONDS || queue.index <= 0) return { kind: 'restart' }
  return { kind: 'go', index: queue.index - 1 }
}

/**
 * Whether this much LISTENING makes a song a play - Last.fm's rule, which Navidrome passes plays
 * on to: longer than 30 seconds, and heard for half its length or four minutes, whichever comes
 * first. `listened` is time actually heard, not the position: seeking to the last second is not
 * listening to a song.
 */
export function countsAsPlayed(listened: number, duration: number): boolean {
  if (!(duration > 30)) return false
  return listened >= Math.min(duration / 2, 240)
}

/**
 * How far past the wall clock a step may run and still count in full, in seconds. The position and
 * the clock are read a moment apart, so a step of playback can come out slightly longer than the
 * time measured for it.
 */
export const LISTEN_SLACK_SECONDS = 0.5

/** Two readings of the element's position, and what happened between them. */
export interface PositionUpdate {
  /** the position at the last update, and now - seconds into the song */
  previous: number
  now: number
  /** wall-clock seconds between the two readings */
  elapsed: number
  /** the element's playbackRate - how many seconds of song a second of listening covers */
  rate: number
  /** whether the element sought in between - its `seeking` event fired */
  seeked: boolean
}

/**
 * How much listening one position update adds, in seconds of the song.
 *
 * A step forward is playback however long it is, so long as no seek happened since the last
 * update - which is the seek's own flag, not a guess from the size of the step. That matters on a
 * locked iPhone: iOS may send `timeupdate` far less often there, and a rule that took any step
 * of 1.5s or more for a seek - the first cut of this - would count nothing heard while the
 * phone was locked, however long the song played. A step is still capped at what the wall clock
 * allows at this playback rate, plus a little slack, so a jump the seek flag somehow missed adds
 * no more than the time that actually passed. A step back, or across a seek, adds nothing:
 * seeking to the last second is not listening to a song.
 */
export function listenedStep({ previous, now, elapsed, rate, seeked }: PositionUpdate): number {
  const step = now - previous
  if (seeked || !(step > 0)) return 0
  const pace = rate > 0 ? rate : 1
  const allowed = Math.max(0, elapsed) * pace + LISTEN_SLACK_SECONDS
  return Math.min(step, allowed)
}

/**
 * One hearing of a song, from a load or a restart to the next of either. Hearing a song again -
 * "previous" restarting it, or play pressed once it has ended - is a NEW listen and counts again;
 * pausing and carrying on is the same one. Until 1.0.3 a song counted once per load, so a second
 * listen of it never reached Navidrome.
 */
export interface Listen {
  /** seconds actually heard - listenedStep()'s steps, summed */
  heard: number
  /** when it began playing, in ms since the epoch; 0 until it has. What a play is reported as
   *  having happened at - which is not when the song was loaded: "next" pressed while paused
   *  loads a song that may not start playing for hours */
  startedAt: number
  /** whether Navidrome has been told it was played */
  submitted: boolean
}

export const NEW_LISTEN: Listen = { heard: 0, startedAt: 0, submitted: false }

/**
 * The song began playing - the element's `playing` event, or a restart while it plays. The first
 * time in a listen is when the listen started, and when Navidrome is told what's playing; after
 * that - carrying on from a pause, or from waiting on the network - it is the same listen, and
 * says nothing new.
 */
export function listenStarted(listen: Listen, now: number): { listen: Listen; nowPlaying: boolean } {
  if (listen.startedAt) return { listen, nowPlaying: false }
  return { listen: { ...listen, startedAt: now }, nowPlaying: true }
}

/**
 * Some more of the song heard. `submit` says this is the step that made it a play - once per
 * listen, which is when Navidrome is told.
 */
export function listenHeard(listen: Listen, seconds: number, duration: number): { listen: Listen; submit: boolean } {
  const heard = listen.heard + seconds
  const submit = !listen.submitted && countsAsPlayed(heard, duration)
  return { listen: { ...listen, heard, submitted: listen.submitted || submit }, submit }
}

/** MediaError's codes, which a failure on the audio element carries. */
export const MEDIA_ERR_ABORTED = 1
export const MEDIA_ERR_NETWORK = 2
export const MEDIA_ERR_DECODE = 3
export const MEDIA_ERR_SRC_NOT_SUPPORTED = 4

/**
 * How long to wait before asking again for a song that failed to load: long enough for a
 * connection that dropped at a change of song - a phone's tunnel moving between Wi-Fi and mobile
 * data - to come back, and short enough to read as a hiccup rather than as the music stopping.
 */
export const LOAD_RETRY_DELAY_MS = 1500

export type FailureAction = { kind: 'retry' } | { kind: 'skip'; index: number } | { kind: 'stop' }

export interface Failure {
  queue: PlayQueue
  /** the element's MediaError code; 0 when it gave none */
  code: number
  /** whether the listener means the music to be playing - see usePlayer */
  intendsToPlay: boolean
  /** whether this song has already been asked for a second time since it was loaded */
  retried: boolean
}

/**
 * What to do when the song won't play.
 *
 * Nothing, if nobody meant it to be playing: the error is shown and waits for a tap. Otherwise a
 * failure to LOAD - the connection dropping, or a request that failed, which from inside the page
 * looks exactly like audio this browser can't play (MEDIA_ERR_SRC_NOT_SUPPORTED) - is tried once
 * more. A song that fails again, or can't be decoded, is passed over for the next one, the way a
 * song ending moves on: one bad file must not stop an album playing in a pocket, where the lock
 * screen's "next" would otherwise be needed and then "play" as well. At the end of the queue
 * there is nothing to move on to, and playing stops. An abort is the browser having been told to
 * stop, and is left at that.
 */
export function afterFailure({ queue, code, intendsToPlay, retried }: Failure): FailureAction {
  if (!intendsToPlay || code === MEDIA_ERR_ABORTED) return { kind: 'stop' }
  const loadFailure = code === MEDIA_ERR_NETWORK || code === MEDIA_ERR_SRC_NOT_SUPPORTED
  if (loadFailure && !retried) return { kind: 'retry' }
  const next = nextIndex(queue)
  return next === null ? { kind: 'stop' } : { kind: 'skip', index: next }
}
