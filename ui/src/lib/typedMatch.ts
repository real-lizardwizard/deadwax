/**
 * Typing to narrow a list of folders (2.0.0-player.42) - pure, pinned by ui/test/care.sim.cjs: Library
 * care's runs narrowed to a few typed words (lib/libraryCare.ts narrowAlbums) and the Edit panel's
 * "Choose the folder" (lib/albumEdit.ts folderChoices) match the same way. Every word typed must be
 * somewhere in what is searched, accents and case aside - so "sigur ros 2002" finds
 * "Sigur Rós/( ) (2002)". Nothing typed matches everything.
 */

/** A name or a path as typing is matched against it: accents and case aside. */
export function searchFold(text: string | null | undefined): string {
  return String(text || '').normalize('NFKD').replace(/\p{M}/gu, '').toLowerCase()
}

/** Whether every word typed is somewhere in `haystack` (nothing typed matches everything). */
export function matchesTyped(haystack: string, typed: string): boolean {
  const words = searchFold(typed).split(/\s+/).filter(Boolean)
  if (!words.length) return true
  const hay = searchFold(haystack)
  return words.every((word) => hay.includes(word))
}
