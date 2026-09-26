/**
 * One tracklist for a release group, and what each pressing changes about it.
 *
 * Asked for by James: "instead of having a tracklist for each release, just having a base
 * tracklist ... and then each release shows the changes it would make to that tracklist".
 * Twenty pressings of Dummy are twenty copies of nearly the same ten or eleven songs, and the
 * one thing worth knowing - which of them has "It's a Fire", which has the bonus disc - was
 * only findable by opening each one and reading it against the others.
 *
 * THE BASE IS THE MOST COMMON TRACKLIST, not the first release (James's choice, after trying
 * both in a preview). The first release is whatever MusicBrainz or the sort put on top, and on
 * Dummy that was a vinyl whose lengths MusicBrainz lists ~10s short of every CD - so every CD
 * read as ten changes. The most common tracklist is what "the album" means to most copies.
 *
 * Pure and DOM-free, and `.mjs` for the same reason sort.mjs is: so ui/test/tracklist.sim.cjs
 * can import it straight into Node.
 */

/** Differences in length up to this many seconds are MusicBrainz rounding, not a change. */
export const LENGTH_TOLERANCE_S = 2;

/**
 * Past this a track isn't rounding, it's a different recording of the song - a single mix, an
 * edit, a live take. The Slow Rush has two digital releases whose tracklists are identical by
 * title and differ only in "Borderline" being 37s longer; that is the case this exists for.
 */
export const OTHER_VERSION_S = 15;
export const OTHER_VERSION_SHARE = 0.08;

/**
 * A title as it should be COMPARED. Curly and straight apostrophes are the same apostrophe -
 * MusicBrainz has both "It's a Fire" and "It’s a Fire" among Dummy's pressings, and treating
 * those as a rename would flag half of them for nothing.
 */
export function foldTitle(title) {
  return String(title || '')
    .toLowerCase()
    .replace(/[’‘`´]/g, "'")
    .replace(/[^\p{L}\p{N}']+/gu, ' ')
    .trim();
}

/**
 * A release's tracks in running order, as this pressing prints them: its own title (which can
 * differ from the recording's), its own length in seconds (null when MusicBrainz has none),
 * and its own numbering (A1, B5...).
 */
export function releaseTracks(release) {
  const tracks = [];
  for (const medium of release?.media || []) {
    for (const track of medium.tracks || []) {
      const ms = track.length ?? track.recording?.length;
      tracks.push({
        title: track.title || track.recording?.title || '',
        length: Number.isFinite(ms) ? Math.round(ms / 1000) : null,
        number: track.number ?? String(track.position ?? ''),
        disc: medium.position ?? 1,
      });
    }
  }
  return tracks;
}

/** What makes two tracklists "the same" for choosing the base: the titles, in order. */
export function tracklistKey(tracks) {
  return tracks.map((track) => foldTitle(track.title)).join('\n');
}

/**
 * The base: the most common tracklist among releases that list any tracks.
 *
 * `index` is the release that stands for it - the first holding that tracklist, in the order
 * given - and its lengths and numbering are the ones shown. Ties go to whichever tracklist
 * appears first. Null when fewer than two releases have tracks, since one tracklist has
 * nothing to be compared with.
 */
export function chooseBase(releases) {
  const counts = new Map();
  const first = new Map();

  releases.forEach((release, index) => {
    const tracks = releaseTracks(release);
    if (!tracks.length) return;
    const key = tracklistKey(tracks);
    counts.set(key, (counts.get(key) || 0) + 1);
    if (!first.has(key)) first.set(key, index);
  });

  const withTracks = [...counts.values()].reduce((sum, n) => sum + n, 0);
  if (withTracks < 2) return null;

  let bestKey = null;
  for (const [key, count] of counts) {
    if (bestKey === null || count > counts.get(bestKey)) bestKey = key;
  }

  const index = first.get(bestKey);
  return {
    index,
    tracks: releaseTracks(releases[index]),
    count: counts.get(bestKey),
    total: withTracks,
  };
}

/** Whether a difference in length is another version of the song rather than rounding. */
export function isOtherVersion(deltaSeconds, baseSeconds) {
  return Math.abs(deltaSeconds) >= Math.max(OTHER_VERSION_S, (baseSeconds || 0) * OTHER_VERSION_SHARE);
}

/**
 * What `tracks` changes about `base`.
 *
 * Tracks are paired by title along the longest common run, so an inserted bonus track shifts
 * nothing after it - "It's a Fire" at 6 is one added track, not six changed ones. Of what is
 * left, an added and a removed track of about the same length are one RENAMED track. Paired
 * tracks are compared by length: over the tolerance is a length change, and far enough over
 * is another version of the song.
 *
 * Positions are running positions in THIS release (1-based), so they read against its own
 * tracklist; `after` names the track an added one follows, which reads against the base.
 */
export function diffTracklists(base, tracks, tolerance = LENGTH_TOLERANCE_S) {
  const a = base.map((t) => foldTitle(t.title));
  const b = tracks.map((t) => foldTitle(t.title));
  const n = a.length;
  const m = b.length;

  const lcs = Array.from({ length: n + 1 }, () => new Array(m + 1).fill(0));
  for (let i = n - 1; i >= 0; i--) {
    for (let j = m - 1; j >= 0; j--) {
      lcs[i][j] = a[i] === b[j] ? lcs[i + 1][j + 1] + 1 : Math.max(lcs[i + 1][j], lcs[i][j + 1]);
    }
  }

  let added = [];
  let removed = [];
  const versions = [];
  const lengths = [];
  let same = 0;

  let i = 0;
  let j = 0;
  while (i < n || j < m) {
    if (i < n && j < m && a[i] === b[j]) {
      const from = base[i].length;
      const to = tracks[j].length;
      if (from !== null && to !== null && Math.abs(to - from) > tolerance) {
        const change = { position: j + 1, title: tracks[j].title, from, to, delta: to - from };
        (isOtherVersion(to - from, from) ? versions : lengths).push(change);
      }
      else {
        same++;
      }
      i++;
      j++;
    }
    else if (j < m && (i >= n || lcs[i][j + 1] >= lcs[i + 1][j])) {
      added.push({
        position: j + 1,
        title: tracks[j].title,
        length: tracks[j].length,
        after: j > 0 ? tracks[j - 1].title : null,
      });
      j++;
    }
    else {
      removed.push({ position: i + 1, title: base[i].title, length: base[i].length });
      i++;
    }
  }

  const renamed = [];
  for (const add of added) {
    const match = removed.find((rem) => !rem.paired
      && (add.length === null || rem.length === null || Math.abs(add.length - rem.length) <= Math.max(tolerance, 5)));
    if (match) {
      match.paired = add.paired = true;
      renamed.push({ position: add.position, from: match.title, to: add.title });
    }
  }
  added = added.filter((x) => !x.paired);
  removed = removed.filter((x) => !x.paired).map(({ paired, ...rest }) => rest);

  return { added: added.map(({ paired, ...rest }) => rest), removed, renamed, versions, lengths, same };
}

/** Nothing added, removed, renamed or re-timed beyond the tolerance. */
export function isSameTracklist(diff) {
  return !diff.added.length && !diff.removed.length && !diff.renamed.length
    && !diff.versions.length && !diff.lengths.length;
}

/**
 * The chips a release's row carries, most telling first: `{ kind, label }`.
 * One quiet "Same tracklist" chip when there is nothing to say.
 */
export function summarizeDiff(diff) {
  if (isSameTracklist(diff)) return [{ kind: 'same', label: 'Same tracklist' }];

  const plural = (count, word) => `${count} ${word}${count === 1 ? '' : 's'}`;
  const chips = [];
  if (diff.added.length) chips.push({ kind: 'added', label: `+${plural(diff.added.length, 'track')}` });
  if (diff.removed.length) chips.push({ kind: 'removed', label: `−${plural(diff.removed.length, 'track')}` });
  if (diff.renamed.length) chips.push({ kind: 'renamed', label: `${diff.renamed.length} renamed` });
  if (diff.versions.length) chips.push({ kind: 'version', label: plural(diff.versions.length, 'other version') });
  if (diff.lengths.length) chips.push({ kind: 'lengths', label: plural(diff.lengths.length, 'length') });
  return chips;
}

/** `257` -> `4:17`; null stays blank. */
export function formatSeconds(seconds) {
  if (seconds === null || seconds === undefined) return '';
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`;
}
