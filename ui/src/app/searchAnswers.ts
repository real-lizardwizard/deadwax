/**
 * Search's kept MusicBrainz answers (2.0.0-player.55, "search like Apple Music"): the last SEARCH_ANSWERS_KEPT
 * search answers - albums, artists and songs - by the exact address asked (api/musicbrainz.ts's paths), successes
 * only, for the page's life (as app/pressingLists.ts keeps pressings). A module, so a text searched before - cut
 * back from "portishead third" to "portishead", Back, a chip there and back - is answered with no request at all.
 *
 * What it adds over the answers deadwax keeps on disk (2.0.0-player.54): those answer a repeated search at once
 * too, but only once it is ASKED - MUSICBRAINZ_SETTLE_MS (700 ms) after typing stops, and a round trip after that.
 * A kept answer is in hand synchronously as the library settles (~0.3 s), so the list is drawn whole at the
 * library's moment, never as Top results first and the sections a moment later. Library answers are never kept
 * across texts (they're cheap, and stars change).
 */

/** How many search answers are kept. */
export const SEARCH_ANSWERS_KEPT = 24

const answers = new Map<string, unknown>()

/** The answer kept for this address - null when none is. */
export function keptAnswer<T>(path: string): T | null {
  return answers.has(path) ? (answers.get(path) as T) : null
}

/** Keep a success, as the newest; the oldest goes past SEARCH_ANSWERS_KEPT. */
export function keepAnswer(path: string, answer: unknown): void {
  answers.delete(path)
  answers.set(path, answer)
  while (answers.size > SEARCH_ANSWERS_KEPT) {
    const [oldest] = answers.keys()
    if (oldest === undefined) break
    answers.delete(oldest)
  }
}

/** The kept answer for this address, else asked - and kept when it answers. A failure is never kept. */
export async function keptOr<T>(path: string, ask: () => Promise<T>): Promise<{ answer: T; kept: boolean }> {
  const kept = keptAnswer<T>(path)
  if (kept !== null) return { answer: kept, kept: true }
  const answer = await ask()
  keepAnswer(path, answer)
  return { answer, kept: false }
}

/** Forget every kept answer (the sims, between checks). */
export function forgetAnswers(): void {
  answers.clear()
}
