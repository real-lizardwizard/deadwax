/**
 * What an album's own Get cover, Get CD art and Get lyrics came to, said as a line under the button (2.0.8, UX batch
 * 5) - pure, pinned by ui/test/getresults.sim.cjs. Until then the result was only in the button's tooltip, which a
 * phone never shows: on a phone the button just turned into "Retry cover" or "No CD art found", with no reason, and a
 * failed cover went only to the console.
 *
 * The words are the route's own where they are fit for the reader (src/routes/library.py: "the Cover Art Archive has
 * no front cover for that release", "no CD art on the Cover Art Archive for this release - a fanart.tv key in Server
 * settings adds another source", "...couldn't be reached - try again"), made a sentence; anything else goes through
 * lib/errorWords.ts like every other error - a sentence for anyone, its own words in brackets for whoever runs deadwax.
 */

import type { LyricsSummary } from '../api/types'
import { asSentence, errorWords, said } from './errorWords'
import { describeLyrics } from './lyrics'

/** What each button says while it works, in place of a bare spinner. */
export const GETTING = {
  cover: 'Getting the cover…',
  disc: 'Getting CD art…',
  lyrics: 'Getting lyrics…',
} as const

/** What a failed Get said when it had nothing better to say. */
export const GET_FAILED = {
  cover: "Couldn't get the cover.",
  disc: "Couldn't get CD art.",
  lyrics: "Couldn't get lyrics.",
} as const

/** A Get that didn't work, as the line under its button says it: the route's words as a sentence (a 404's too - "the
 *  Cover Art Archive has no front cover for that release"), else errorWords' sentence with `failed` for its lead. */
export function getProblem(error: unknown, kind: keyof typeof GET_FAILED, admin: boolean): string {
  const words = errorWords(error, { admin, failed: GET_FAILED[kind], retry: true })
  const line = said({ text: asSentence(words.text), advice: words.advice })
  return words.detail ? `${line} (${words.detail})` : line
}

/** What a Get lyrics that answered did, as the line under its button: the summary as a sentence. Nothing more - the
 *  one press asks for every track without lyrics, so pressing again helps only the ones that failed, and the summary
 *  says those itself ("1 failed - try again"); it said "Press it again to look for the rest" for tracks LRCLIB had
 *  just said it hasn't got (2.0.8 review). */
export function lyricsResult(summary: LyricsSummary): string {
  return asSentence(describeLyrics(summary))
}
