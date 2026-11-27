/**
 * A short description on the artist page, the album page and the album you don't have (2.0.13) - James
 * (2026-10-24): "I want to have the little descriptions for the artists and albums displayed on their respective
 * pages". The words are deadwax's answer from GET /deadwax/describe/<kind> (src/routes/describe.py): a PARAGRAPH -
 * Navidrome's own words first (its link Last.fm's page; James: "Last.fm FIRST, Wikipedia (via MusicBrainz) as the
 * fallback"), else Wikipedia's summary by the MusicBrainz id, else none - and a SUBTITLE, Wikidata's one-line
 * English description ("English band", "1994 studio album by Portishead"), whichever the paragraph is.
 *
 * The rules a page draws one by, pure (pinned by ui/test/describe.sim.cjs):
 *
 *  - WHAT IS ASKED: the MusicBrainz id (an artist's, an album's release group's) and/or Navidrome's id - nothing
 *    at all when neither is known (`describeKey` null), and then there is simply no description.
 *  - KEPT FOR THE SESSION: an answer - a description or "none" - is kept by what was asked (DESCRIPTIONS_KEPT of
 *    them, the oldest going), so a page come back to draws it, and what waits for it, on its first frame. An answer
 *    that isn't the whole story - deadwax said a source couldn't be asked (`unavailable`), or deadwax couldn't be
 *    asked at all - is kept only UNSURE_KEPT_MS: Back still draws at once, and a while later it is asked again, never
 *    a blip kept as "none" for the days a phone keeps the app open. The question each page asked is remembered too, so
 *    a page come back to while its ids are still being settled (the album page's bridge, asked again) draws its kept
 *    answer on its first frame.
 *  - WHERE THE PARAGRAPH GOES: ALWAYS UNDER THE NAME OR THE HERO, AND NOTHING JUMPS (2.1.52 - James: "sometimes the
 *    description is at the top and sometimes at the bottom. Let's make it consistently at the top."). Until then
 *    it was at the top only when in hand as what lies under that place was drawn, and at the page's foot when it
 *    came later; the rows under it waited for it a moment. Now the rows wait for nothing: while an answer is still
 *    to come the page HOLDS THE BLOCK'S ROOM (`holdsRoom`), and the words land in it. A kept answer is drawn at once
 *    with no room; a kept "none" holds none; an answer of none closes the room, once (app/Description.tsx).
 *  - WHERE THE SUBTITLE GOES (`inBlock`): an artist's under their name, in the hero, on one line - in a line the hero
 *    keeps for it above the name until it comes (app.css), so a hero that outgrew its 240px (a two-line name under an
 *    iPhone's status bar) doesn't grow again as it lands. An album's hero has no room kept (Play and the chips sit in
 *    it, drawn from the first frame so nothing moves), so an album's subtitle heads its paragraph's block instead,
 *    placed as it is.
 *  - THE WORDS: "From Wikipedia" (Wikipedia's CC BY-SA asks for the credit, so it is always drawn with them) and
 *    "More on Last.fm" for Navidrome's - whose words may be Deezer's or Last.fm's (Navidrome's agents: an artist's
 *    biography is Deezer's first), so the link names only where it goes, never who wrote them; no link when
 *    Navidrome gave none.
 */

export type DescribeKind = 'artist' | 'album'

export type DescribeSource = 'wikipedia' | 'lastfm'

/** deadwax's answer: every field null when there is no description. */
export interface DescribeAnswer {
  text: string | null
  source: DescribeSource | null
  url: string | null
  subtitle?: string | null
  /** a source couldn't be asked just now: what came is all there is for the moment */
  unavailable?: boolean
}

/** The paragraph to draw. */
export interface Paragraph {
  text: string
  source: DescribeSource
  url: string | null
}

/** A description to draw: its paragraph, its subtitle - at least one of them. */
export interface Description {
  paragraph: Paragraph | null
  subtitle: string | null
}

/** What a page knows its subject by: their MusicBrainz id and/or Navidrome's. */
export interface DescribeIds {
  mbid?: string | null
  navidromeId?: string | null
}

/** What a page remembers it asked when who it is was settled with nothing to ask by: there is no description, and
 *  none to hold room for when the page is come back to. */
export const NOTHING_TO_ASK = ''

/** How many answers the session keeps. */
export const DESCRIPTIONS_KEPT = 200

/** How long an answer that isn't the whole story is kept: long enough for Back, short enough to ask again soon. */
export const UNSURE_KEPT_MS = 60_000

/** The link's words, by whose words they are. */
export const SOURCE_WORDS: Record<DescribeSource, string> = {
  wikipedia: 'From Wikipedia',
  lastfm: 'More on Last.fm',
}

/** "More" and "Less": the clamp's button. */
export const MORE = 'More'
export const LESS = 'Less'

/** What is asked, as one string - the session's key and the route's query - or null when nothing is known to ask by. */
export function describeKey(kind: DescribeKind, ids: DescribeIds): string | null {
  const params = new URLSearchParams()
  const mbid = (ids.mbid ?? '').trim().toLowerCase()
  const navidromeId = (ids.navidromeId ?? '').trim()
  if (mbid) params.set('mbid', mbid)
  if (navidromeId) params.set('navidrome_id', navidromeId)
  const query = params.toString()
  return query ? `/describe/${kind}?${query}` : null
}

/** One line of text, or null. */
function line(value: unknown): string | null {
  const text = typeof value === 'string' ? value.trim() : ''
  return text || null
}

/** deadwax's answer as something to draw, or null: no words and no subtitle. A paragraph needs a source this page
 *  knows; its link only goes where it says. */
export function descriptionOf(answer: DescribeAnswer | null | undefined): Description | null {
  const text = line(answer?.text)
  const source = answer?.source
  let paragraph: Paragraph | null = null
  if (text && (source === 'wikipedia' || source === 'lastfm')) {
    //? a link out only to the place it says: an https address of Wikipedia's or Last.fm's
    const url = typeof answer?.url === 'string' && linkFits(source, answer.url) ? answer.url : null
    paragraph = { text, source, url }
  }
  const subtitle = line(answer?.subtitle)
  return paragraph || subtitle ? { paragraph, subtitle } : null
}

function linkFits(source: DescribeSource, url: string): boolean {
  try {
    const parsed = new URL(url)
    const host = parsed.hostname.toLowerCase()
    if (parsed.protocol !== 'https:') return false
    return source === 'wikipedia' ? host === 'en.wikipedia.org' : host === 'last.fm' || host.endsWith('.last.fm')
  } catch {
    return false
  }
}

/** What of a description the page's block draws: an artist's paragraph (their subtitle is in the hero), an album's
 *  paragraph and subtitle both. Null when the block has nothing. */
export function inBlock(kind: DescribeKind, description: Description | null): Description | null {
  if (!description) return null
  const shown = kind === 'artist' ? { paragraph: description.paragraph, subtitle: null } : description
  return shown.paragraph || shown.subtitle ? shown : null
}

const kept = new Map<string, { found: Description | null; until: number | null }>()

/** The session's answer for `key`: a description, null for "none" - undefined when nothing is kept (or what was kept
 *  for a moment has had it). */
export function keptDescription(key: string, now: number = Date.now()): Description | null | undefined {
  const entry = kept.get(key)
  if (!entry) return undefined
  kept.delete(key)
  if (entry.until !== null && now >= entry.until) return undefined
  //? the most recently used last, so the oldest goes first
  kept.set(key, entry)
  return entry.found
}

/** An answer kept - for the session, or (`unsure`) for UNSURE_KEPT_MS. */
export function keepDescription(key: string, found: Description | null, unsure = false, now: number = Date.now()): void {
  kept.delete(key)
  kept.set(key, { found, until: unsure ? now + UNSURE_KEPT_MS : null })
  while (kept.size > DESCRIPTIONS_KEPT) kept.delete(kept.keys().next().value as string)
}

//? the question each page last asked, by `<kind>:<page id>` - so a page come back to, whose ids are still being
//? settled (the album page's bridge out again), draws the answer it had on its first frame
const pages = new Map<string, string>()

/** The question a page asks, remembered for the session (DESCRIPTIONS_KEPT pages, the oldest going). */
export function rememberPageKey(page: string, key: string): void {
  if (pages.get(page) === key) return
  pages.delete(page)
  pages.set(page, key)
  while (pages.size > DESCRIPTIONS_KEPT) pages.delete(pages.keys().next().value as string)
}

/** The question a page last asked this session, or null. */
export function pageKeyOf(page: string): string | null {
  return pages.get(page) ?? null
}

/** Every kept answer forgotten (the sims). */
export function forgetDescriptions(): void {
  kept.clear()
  pages.clear()
}

/**
 * (2.1.52) Whether the page holds the block's room: an answer is still to come (`settled` false), the block has
 * nothing to draw meanwhile (`block` - inBlock's), and the page hasn't already been answered "none" while it has been
 * up (`closed`): a room closed once stays closed while the question changes under it (the artist's library asked
 * again, an Edit) - words that come after all open it for themselves. A page whose answer is kept is settled on its
 * first frame, so it holds none: the words, or nothing.
 */
export function holdsRoom(settled: boolean, block: Description | null, closed: boolean): boolean {
  return !settled && block === null && !closed
}
