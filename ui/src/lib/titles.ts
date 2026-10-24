/**
 * A large title's size (2.0.9, the type review's fix 5). An album's name at the top of its page is drawn at
 * the title size and balanced over its lines (`text-wrap: balance`), in Noto Sans SemiCondensed; one longer
 * than LONG_TITLE letters is drawn a step smaller as well (`.pl-hero-title.is-long`, --dw-text-title-long),
 * so Fiona Apple's 23-word title is four lines on a phone, not five. Letters are counted as code points, so
 * an accented or a Japanese name counts each letter once.
 *
 * Pinned by ui/test/titles.sim.cjs.
 */

/** The most letters a title has before it is drawn a step smaller - the review's "about 60". */
export const LONG_TITLE = 60

/** Whether a title is long enough to be drawn a step smaller. */
export function isLongTitle(title: string | null | undefined): boolean {
  return [...(title ?? '').trim()].length > LONG_TITLE
}

/** The hero title's class: `pl-hero-title`, with `is-long` for a long one. */
export function heroTitleClass(title: string | null | undefined): string {
  return isLongTitle(title) ? 'pl-hero-title is-long' : 'pl-hero-title'
}
