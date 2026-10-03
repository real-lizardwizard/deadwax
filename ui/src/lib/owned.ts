/**
 * Which albums are already in the library - the TypeScript twin of interface/scripts/owned.mjs
 * (2.0.0-player.13), for the app's Search: a MusicBrainz album the library holds is left out of
 * "Not in your library yet", since the library half already shows it.
 *
 * A PORT, not a new answer: the image's UI stage copies only ui/, so the app can't import the .mjs
 * the main page's search marks come from. ui/test/owned.sim.cjs runs both against the same cases
 * (tests/fixtures/pressings/owned.json), so the two can never disagree about what is held.
 *
 * THREE ways an album on disk can match, surest first (the .mjs says why at length):
 *   1. by RELEASE id - this exact pressing;
 *   2. by RELEASE-GROUP id - some pressing of this album;
 *   3. by NAME, only for a folder with no MusicBrainz ids at all - said as "maybe", and never for a
 *      folder that IS tagged, which has already answered by id.
 */

/** One album as /deadwax/library/owned answers it (OWNED_FIELDS in src/routes/library.py). */
export interface OwnedAlbum {
  path: string
  artist?: string | null
  album?: string | null
  year?: string | number | null
  edition?: string | null
  release_mbid?: string | null
  release_group_mbid?: string | null
  formats?: string[] | null
  track_count?: number | null
  /** WHO the album is by, as MusicBrainz ids (2.0.0-player.17): one for one artist, several for a
   *  collaboration, none for a folder not tagged with any - absent from an older server */
  albumartist_mbids?: string[] | null
}

export interface OwnedIndex {
  byRelease: Map<string, OwnedAlbum[]>
  byGroup: Map<string, OwnedAlbum[]>
  byName: Map<string, OwnedAlbum[]>
  total: number
}

export interface GroupHolding {
  held: OwnedAlbum[]
  guessed: OwnedAlbum[]
}

/** A name as it should be COMPARED: bracketed asides, accents, a leading "The", & and "and" fold away. */
export function foldName(name: string | null | undefined): string {
  return String(name || '')
    .normalize('NFKD')
    .replace(/\p{M}/gu, '')
    .toLowerCase()
    .replace(/\s*[([][^)\]]*[)\]]/g, ' ')
    .replace(/[’‘`´]/g, "'")
    .replace(/&/g, ' and ')
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .trim()
    .replace(/^the /, '')
}

function nameKey(artist: string | null | undefined, album: string | null | undefined): string {
  return `${foldName(artist)}\n${foldName(album)}`
}

function add(map: Map<string, OwnedAlbum[]>, key: string | null | undefined, album: OwnedAlbum): void {
  if (!key) return
  const list = map.get(key)
  if (list) list.push(album)
  else map.set(key, [album])
}

/** Every album on disk, indexed the three ways above. */
export function buildOwnedIndex(albums: readonly OwnedAlbum[] | null | undefined): OwnedIndex {
  const byRelease = new Map<string, OwnedAlbum[]>()
  const byGroup = new Map<string, OwnedAlbum[]>()
  const byName = new Map<string, OwnedAlbum[]>()

  for (const album of albums || []) {
    add(byRelease, album.release_mbid, album)
    add(byGroup, album.release_group_mbid, album)
    if (!album.release_mbid && !album.release_group_mbid) {
      add(byName, nameKey(album.artist, album.album), album)
    }
  }

  return { byRelease, byGroup, byName, total: (albums || []).length }
}

/** The folders holding exactly this pressing. */
export function ownedForRelease(index: OwnedIndex | null | undefined, releaseId: string | null | undefined): OwnedAlbum[] {
  return (index && releaseId && index.byRelease.get(releaseId)) || []
}

/**
 * What the library holds of one release group: `held` by id, `guessed` by name (looked for only
 * when nothing was held by id). `releaseIds` catch a folder tagged with a release id but no group
 * id; `artists` are every name the group could be filed under - the credit and the current name.
 */
export function ownedForGroup(
  index: OwnedIndex | null | undefined,
  { groupId, releaseIds = [], title = '', artists = [] }: {
    groupId: string | null | undefined
    releaseIds?: readonly string[]
    title?: string
    artists?: readonly (string | null | undefined)[]
  },
): GroupHolding {
  if (!index) return { held: [], guessed: [] }

  const held = new Map<string, OwnedAlbum>()
  for (const album of (groupId && index.byGroup.get(groupId)) || []) held.set(album.path, album)
  for (const id of releaseIds) {
    for (const album of index.byRelease.get(id) || []) held.set(album.path, album)
  }

  const guessed = new Map<string, OwnedAlbum>()
  if (!held.size) {
    for (const artist of new Set(artists.filter(Boolean))) {
      for (const album of index.byName.get(nameKey(artist, title)) || []) guessed.set(album.path, album)
    }
  }

  return { held: [...held.values()], guessed: [...guessed.values()] }
}

/** One line per folder: where it lives, its format, and its edition when the name doesn't say it. */
export function describeFolders(albums: readonly OwnedAlbum[]): string {
  return albums.map((album) => {
    const edition = album.edition && !album.path.includes(album.edition) ? album.edition : ''
    const what = [edition, (album.formats || []).join('/').toUpperCase()].filter(Boolean).join(', ')
    return what ? `${album.path} (${what})` : album.path
  }).join('\n')
}

/** The chip a release group carries, or null. */
export function describeGroupOwnership({ held, guessed }: GroupHolding): { kind: 'held' | 'maybe'; label: string; title: string } | null {
  if (held.length) {
    return {
      kind: 'held',
      label: held.length === 1 ? 'In your library' : `In your library · ${held.length} editions`,
      title: `Already in your library:\n${describeFolders(held)}`,
    }
  }
  if (guessed.length) {
    return {
      kind: 'maybe',
      label: 'Maybe in your library',
      title: `A folder with this name, not tagged with MusicBrainz ids - so which edition it is `
        + `(or whether it is this album at all) can't be told:\n${describeFolders(guessed)}\n`
        + 'Matching its release in the metadata editor would settle it.',
    }
  }
  return null
}
