import { useEffect, useMemo, useRef, useState } from 'preact/hooks'

import { getDescription } from '../api/describe'
import {
  describeKey, descriptionOf, inBlock, keepDescription, keptDescription, pageKeyOf, placeOf, rememberPageKey,
  type DescribeIds, type DescribeKind, type DescribePlace, type Description,
} from '../lib/describe'
import { latestOnly } from '../lib/latest'

//? the questions out, by key: a page left and come back to while its question is still out waits for that one
//? answer rather than asking again
const asking = new Map<string, Promise<Description | null>>()

/**
 * One question to deadwax, shared by every page asking it, and its answer kept (lib/describe.ts) WHEN IT COMES - even
 * after the page that asked has gone. It is never called off: a page left before its description came (an album
 * tapped a second after the artist page opened) finds it kept on Back, and draws its rows on the first frame. What
 * isn't the whole story - deadwax said a source couldn't be asked, or deadwax couldn't be asked - is kept only a
 * moment. Nothing drawn of a failure, and no error line for a listener: the browser's console says it, at info.
 */
export function askDescription(key: string): Promise<Description | null> {
  const out = asking.get(key)
  if (out) return out
  const question = getDescription(key).then(
    (said) => {
      const found = descriptionOf(said)
      keepDescription(key, found, said?.unavailable === true)
      return found
    },
    (reason: unknown) => {
      console.info('no description just now:', reason)
      keepDescription(key, null, true)
      return null
    },
  ).finally(() => asking.delete(key))
  asking.set(key, question)
  return question
}

/**
 * (2.0.13) A page's description - the artist's, the album's - asked of deadwax (askDescription) through the page's own
 * latestOnly(), so only the newest question's answer is ever drawn; kept for the session (lib/describe.ts), so a page
 * come back to draws it on its first frame. The page never waits for it: it fills in.
 *
 * `ids` null: who it is isn't settled yet (the artist page's MusicBrainz id still coming, the album page's bridge
 * still out) - nothing is asked; but a page come back to draws what it was answered last time it asked, when that is
 * kept, settled from its first frame (lib/describe.ts rememberPageKey). Settled with no id to ask by: there is no
 * description.
 *
 * Answers `description` (null while there is none), `settled` (deadwax has answered - or failed - for what was
 * asked, or there was nothing to ask: what a page holds its rows back for) and `at`, where the page's block goes -
 * lib/describe.ts placeOf, judged once by whether `belowDrawn` (what lies under the top place is on screen) when the
 * block (lib/describe.ts inBlock) first has something, and kept for the page - `page`, the page's own id: a page drawn
 * again for another artist or album places its description afresh.
 *
 * WHILE THE QUESTION CHANGES - the ids going unsettled a moment (the artist page's library asked again, About's Try
 * again), or a new question (Navidrome's artist found later, an Edit that gave the album another release group) - the
 * description drawn for this page stays drawn until the new question's answer replaces it: it never goes and comes
 * back, moving what is under it twice.
 */
export function useDescription(kind: DescribeKind, ids: DescribeIds | null, belowDrawn: boolean, page: string): {
  description: Description | null
  settled: boolean
  at: DescribePlace | null
} {
  const key = ids ? describeKey(kind, ids) : null
  const [answer, setAnswer] = useState<{ key: string; found: Description | null } | null>(null)
  const requests = useMemo(latestOnly, [])

  useEffect(() => {
    if (!key || keptDescription(key) !== undefined) {
      requests.supersede()
      return
    }
    const request = requests.begin()
    void askDescription(key).then((found) => {
      if (request.current()) setAnswer({ key, found })
    })
    return () => requests.supersede()
  }, [key, requests])

  //? with the ids still being settled, the question this page asked last time - its answer, when kept, drawn now
  const pageKey = `${kind}:${page}`
  if (key) rememberPageKey(pageKey, key)
  const asked = key ?? (ids === null ? pageKeyOf(pageKey) : null)
  const fromKept = asked ? keptDescription(asked) : undefined
  const mine = answer && answer.key === key ? answer : null
  const answered = fromKept !== undefined || mine !== null
  const settled = answered || (ids !== null && key === null)

  //? what this page last drew, standing while its question changes
  const shown = useRef<{ page: string; description: Description | null }>({ page, description: null })
  if (shown.current.page !== page) shown.current = { page, description: null }
  if (answered) shown.current.description = fromKept !== undefined ? fromKept : mine!.found
  else if (settled) shown.current.description = null
  const description = shown.current.description

  const place = useRef<{ page: string; at: DescribePlace | null }>({ page, at: null })
  place.current = {
    page,
    at: placeOf(place.current.page === page ? place.current.at : null, inBlock(kind, description) !== null, belowDrawn),
  }

  return { description, settled, at: inBlock(kind, description) ? place.current.at : null }
}
