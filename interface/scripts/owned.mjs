/**
 * Which search results are already in the library.
 *
 * Asked for by James: "a way to see which editions are already in my library when I'm
 * searching for new ones". The server hands over every album's identity (/library/owned) and
 * this decides what matches what. Pure and DOM-free, `.mjs` so ui/test/owned.sim.cjs can
 * import it - the same arrangement as sort.mjs and tracklistDiff.mjs.
 *
 * THREE ways an album on disk can match, from surest to least:
 *
 *   1. By RELEASE id - this exact pressing. What marks a row in the release grid.
 *   2. By RELEASE-GROUP id - some pressing of this album. What marks a search card, and works
 *      before its releases have even been fetched.
 *   3. By NAME, and only for a folder with no MusicBrainz ids at all - a library that predates
 *      deadwax. Said as "maybe": the name can't say which edition, or even for certain that it
 *      is the same album, and a folder that IS tagged has already answered the question by id -
 *      a tagged album from another group must not be claimed by a name that happens to match.
 */

/**
 * A name as it should be COMPARED. Bracketed asides go ("Dummy (Deluxe Edition)" is Dummy),
 * as do accents, a leading "The", and the difference between "&" and "and" - folders are
 * named by hand and MusicBrainz names things properly, and neither is wrong.
 */
export function foldName(name) {
  return String(name || '')
    .normalize('NFKD')
    .replace(/\p{M}/gu, '')
    .toLowerCase()
    .replace(/\s*[([][^)\]]*[)\]]/g, ' ')
    .replace(/[’‘`´]/g, "'")
    .replace(/&/g, ' and ')
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .trim()
    .replace(/^the /, '');
}

function nameKey(artist, album) {
  return `${foldName(artist)}\n${foldName(album)}`;
}

function add(map, key, album) {
  if (!key) return;
  if (!map.has(key)) map.set(key, []);
  map.get(key).push(album);
}

/** Every album on disk, indexed the three ways above. */
export function buildOwnedIndex(albums) {
  const byRelease = new Map();
  const byGroup = new Map();
  const byName = new Map();

  for (const album of albums || []) {
    add(byRelease, album.release_mbid, album);
    add(byGroup, album.release_group_mbid, album);
    if (!album.release_mbid && !album.release_group_mbid) {
      add(byName, nameKey(album.artist, album.album), album);
    }
  }

  return { byRelease, byGroup, byName, total: (albums || []).length };
}

/** The folders holding exactly this pressing. */
export function ownedForRelease(index, releaseId) {
  return (index && releaseId && index.byRelease.get(releaseId)) || [];
}

/**
 * What the library holds of one release group: `held` matched by id, `guessed` by name.
 *
 * `releaseIds` are the group's pressings as far as the page knows them - they catch a folder
 * tagged with a release id but not a group id (easy MP4 couldn't write one). `artists` are
 * every name the group could be filed under: the credit and the artist's current name, since
 * an old folder is called whatever the sleeve said. `guessed` is only looked for when nothing
 * was held by id.
 */
export function ownedForGroup(index, { groupId, releaseIds = [], title = '', artists = [] }) {
  if (!index) return { held: [], guessed: [] };

  const held = new Map();
  for (const album of index.byGroup.get(groupId) || []) held.set(album.path, album);
  for (const id of releaseIds) {
    for (const album of index.byRelease.get(id) || []) held.set(album.path, album);
  }

  const guessed = new Map();
  if (!held.size) {
    for (const artist of new Set(artists.filter(Boolean))) {
      for (const album of index.byName.get(nameKey(artist, title)) || []) guessed.set(album.path, album);
    }
  }

  return { held: [...held.values()], guessed: [...guessed.values()] };
}

/**
 * One line per folder, for a tooltip: where it lives, its format, and its edition when the
 * folder name doesn't already say it - which it does for every edition deadwax filed.
 */
export function describeFolders(albums) {
  return albums.map((album) => {
    const edition = album.edition && !album.path.includes(album.edition) ? album.edition : '';
    const what = [edition, (album.formats || []).join('/').toUpperCase()].filter(Boolean).join(', ');
    return what ? `${album.path} (${what})` : album.path;
  }).join('\n');
}

/**
 * The chip a release-group card carries, or null: `{ kind: 'held' | 'maybe', label, title }`.
 */
export function describeGroupOwnership({ held, guessed }) {
  if (held.length) {
    return {
      kind: 'held',
      label: held.length === 1 ? 'In your library' : `In your library · ${held.length} editions`,
      title: `Already in your library:\n${describeFolders(held)}`,
    };
  }
  if (guessed.length) {
    return {
      kind: 'maybe',
      label: 'Maybe in your library',
      title: `A folder with this name, not tagged with MusicBrainz ids - so which edition it is `
        + `(or whether it is this album at all) can't be told:\n${describeFolders(guessed)}\n`
        + 'Matching its release in the metadata editor would settle it.',
    };
  }
  return null;
}
