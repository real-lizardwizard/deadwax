/**
 * The disc headings on the app's album page, from Navidrome's own answer (2.0.0-player.9).
 *
 * James: "make sure the disc titles get picked up from navidrome". deadwax writes each disc's
 * MusicBrainz medium title into the files as `discsubtitle` (see "Disc titles" in CLAUDE.md),
 * Navidrome reads it, and its getAlbum answer carries them as OpenSubsonic `discTitles`:
 * `[{disc: 4, title: "Live at Wembley..."}]`, only for discs that have one. deadwax's route passes
 * that answer through untouched, so the page reads it as it comes.
 *
 * The rules, pinned by ui/test/discs.sim.cjs:
 *  - A heading reads "Disc 4 · <title>" when that disc has a title, "Disc 4" when it has none.
 *  - Headings show when the album has more than one disc, OR when any of its discs has a title -
 *    a one-disc album with no title is drawn exactly as before, with no heading at all.
 *  - A song with no disc number is on disc 1, as every player treats it.
 *  - A title for a disc the album has no songs on is ignored, and so is a blank one.
 */

export interface DiscTitleEntry {
  disc?: number | string | null
  title?: string | null
}

/** A song's disc, as a heading counts it. */
const discOf = (song: { discNumber?: number | null }): number => song.discNumber || 1

/** Each disc's title, by its number - blank titles and unreadable numbers left out. */
export function discTitleMap(titles: readonly DiscTitleEntry[] | null | undefined): Map<number, string> {
  const map = new Map<number, string>()
  for (const entry of titles ?? []) {
    const disc = Number(entry?.disc)
    const title = typeof entry?.title === 'string' ? entry.title.trim() : ''
    if (Number.isInteger(disc) && disc > 0 && title && !map.has(disc)) map.set(disc, title)
  }
  return map
}

/** What a disc's heading says. */
export function discHeading(disc: number, titles: ReadonlyMap<number, string>): string {
  const title = titles.get(disc)
  return title ? `Disc ${disc} · ${title}` : `Disc ${disc}`
}

/**
 * For each song, the heading to draw ABOVE it, or null: the first song of each disc gets one,
 * whenever the album shows headings at all.
 */
export function discHeadings(
  songs: readonly { discNumber?: number | null }[],
  titles: readonly DiscTitleEntry[] | null | undefined,
): (string | null)[] {
  const byDisc = discTitleMap(titles)
  const discs = new Set(songs.map(discOf))
  const titled = [...discs].some((disc) => byDisc.has(disc))
  const show = discs.size > 1 || titled
  return songs.map((song, index) => {
    const disc = discOf(song)
    const first = index === 0 || discOf(songs[index - 1]!) !== disc
    return show && first ? discHeading(disc, byDisc) : null
  })
}
