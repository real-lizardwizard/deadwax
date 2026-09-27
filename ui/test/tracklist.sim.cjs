/**
 * One base tracklist per release group, and what each pressing changes about it.
 *
 * Loads interface/scripts/tracklistDiff.mjs straight into Node, like sort.sim.cjs. The cases
 * are real MusicBrainz tracklists - Dummy's and The Slow Rush's - because the ways this goes
 * wrong are all things real data does: vinyl lengths that disagree with the CDs, curly and
 * straight apostrophes in the same title, a bonus track in the middle, a single mix that is
 * the same title 37 seconds longer.
 *
 * Run it with:  node ui/test/tracklist.sim.cjs
 */

const path = require('path');
const { pathToFileURL } = require('url');

const MODULE = pathToFileURL(
  path.resolve(__dirname, '../../interface/scripts/tracklistDiff.mjs')
).href;

let failures = 0;
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  if (!ok) failures++;
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`));
}

/** A release as MusicBrainz shapes it, from [title, seconds] pairs (and an optional disc). */
const release = (id, tracks) => {
  const media = new Map();
  tracks.forEach(([title, seconds, disc = 1], index) => {
    if (!media.has(disc)) media.set(disc, { position: disc, tracks: [] });
    media.get(disc).tracks.push({
      number: String(index + 1), title, length: seconds === null ? null : seconds * 1000,
    });
  });
  return { id, media: [...media.values()] };
};

const DUMMY_10 = [['Mysterons', 306], ['Sour Times', 253], ['Strangers', 238], ['It Could Be Sweet', 259],
  ['Wandering Star', 296], ['Numb', 237], ['Roads', 309], ['Pedestal', 221], ['Biscuit', 304], ['Glory Box', 306]];
const DUMMY_VINYL = [['Mysterons', 296], ['Sour Times', 245], ['Strangers', 229], ['It Could Be Sweet', 250],
  ['Wandering Star', 286], ['Numb', 223], ['Roads', 296], ['Pedestal', 210], ['Biscuit', 274], ['Glory Box', 289]];
const withFire = (apostrophe) => [...DUMMY_10.slice(0, 5), [`It${apostrophe}s a Fire`, 229], ...DUMMY_10.slice(5)];

const SLOW_RUSH = [['One More Year', 322], ['Instant Destiny', 193], ['Borderline', 237],
  ['Posthumous Forgiveness', 366], ['Breathe Deeper', 372], ['Tomorrow’s Dust', 326], ['On Track', 301],
  ['Lost in Yesterday', 249], ['Is It True', 238], ['It Might Be Time', 272], ['Glimmer', 128], ['One More Hour', 433]];

(async () => {
  const T = await import(MODULE);

  console.log('titles');
  check('a curly apostrophe is a straight one', T.foldTitle('It’s a Fire') === T.foldTitle("It's a Fire"), true);
  check('case and punctuation are not differences', T.foldTitle('Sour Times!') , T.foldTitle('sour  times'));

  console.log('\nthe base is the most common tracklist, not the first release');
  const dummy = [
    release('2017-vinyl', DUMMY_VINYL),
    release('2014-vinyl', DUMMY_VINYL),
    release('2012-cd', withFire("'")),
    release('2011-shm', withFire('’')),
    release('2009-cd', DUMMY_10),
    release('1995-gb', [...withFire('’'), ['Sour Sour Times / To Kill a Dead Man', 510]]),
    release('1994-us', withFire('’')),
    release('1994-jp', withFire("'")),
  ];
  const base = T.chooseBase(dummy);
  check('the eleven-track tracklist wins, whichever apostrophe it was typed with', [base.index, base.count, base.total], [2, 4, 8]);
  check('one release has nothing to be compared with', T.chooseBase([dummy[0]]), null);
  check('a release with no tracks is not a tracklist', T.chooseBase([dummy[0], { media: [] }]), null);

  console.log('\nwhat each pressing changes');
  const tenTrack = T.diffTracklists(base.tracks, T.releaseTracks(dummy[4]));
  check('the ten-track CD is missing It’s a Fire, and nothing else', [tenTrack.removed.map((x) => x.title), tenTrack.added.length, tenTrack.same], [["It's a Fire"], 0, 10]);
  const bonus = T.diffTracklists(base.tracks, T.releaseTracks(dummy[5]));
  check('a bonus track at the end is one added track, after Glory Box', bonus.added, [{ position: 12, title: 'Sour Sour Times / To Kill a Dead Man', length: 510, after: 'Glory Box' }]);
  check('the other apostrophe is the same tracklist', T.isSameTracklist(T.diffTracklists(base.tracks, T.releaseTracks(dummy[3]))), true);
  const vinyl = T.diffTracklists(base.tracks, T.releaseTracks(dummy[0]));
  //? MusicBrainz lists Dummy's vinyl ~10s short of the CDs on every track - and Biscuit 30s
  //? short, which is past the other-version line. That is what the data says, so it is shown.
  check('vinyl lengths ~10s short are length changes; Biscuit 30s short is another version',
    [vinyl.lengths.length, vinyl.versions.map((v) => [v.title, v.delta]), vinyl.removed.length], [9, [['Biscuit', -30]], 1]);
  check('its row says so in chips', T.summarizeDiff(vinyl).map((c) => c.label), ['−1 track', '1 other version', '9 lengths']);
  const fire = T.diffTracklists(T.releaseTracks(dummy[4]), T.releaseTracks(dummy[2]));
  check('an inserted track shifts nothing after it', [fire.added.map((x) => [x.position, x.after]), fire.same, fire.lengths.length], [[[6, 'Wandering Star']], 10, 0]);

  console.log('\nanother version of a song');
  const album = release('album', SLOW_RUSH);
  const single = release('single-mix', SLOW_RUSH.map(([t, s]) => [t, t === 'Borderline' ? 274 : s + 1]));
  const singleDiff = T.diffTracklists(T.releaseTracks(album), T.releaseTracks(single));
  check('Borderline 37s longer is another version; a second of rounding is nothing',
    [singleDiff.versions.map((v) => [v.title, v.delta]), singleDiff.lengths.length, singleDiff.same], [[['Borderline', 37]], 0, 11]);
  check('chip', T.summarizeDiff(singleDiff).map((c) => c.label), ['1 other version']);
  const japan = release('jp', [...SLOW_RUSH, ['Patience', 293]]);
  check('the Japanese bonus track', T.diffTracklists(T.releaseTracks(album), T.releaseTracks(japan)).added.map((x) => [x.title, x.after]), [['Patience', 'One More Hour']]);
  const vinylSides = release('2lp', SLOW_RUSH.map(([t, s], i) => [t, s, i < 6 ? 1 : 2]));
  check('a tracklist split over two discs is the same tracklist', T.isSameTracklist(T.diffTracklists(T.releaseTracks(album), T.releaseTracks(vinylSides))), true);

  console.log('\nrenames and missing lengths');
  const renamed = release('renamed', [['Mysterons', 306], ['Sour Times (Nobody Loves Me)', 254], ...DUMMY_10.slice(2)]);
  const renamedDiff = T.diffTracklists(T.releaseTracks(release('base', DUMMY_10)), T.releaseTracks(renamed));
  check('a new title at about the same length is a rename, not one added and one removed',
    [renamedDiff.renamed, renamedDiff.added.length, renamedDiff.removed.length],
    [[{ position: 2, from: 'Sour Times', to: 'Sour Times (Nobody Loves Me)' }], 0, 0]);
  const unknown = release('unknown', DUMMY_10.map(([t]) => [t, null]));
  check('a track with no length is never a length change', T.isSameTracklist(T.diffTracklists(T.releaseTracks(release('b', DUMMY_10)), T.releaseTracks(unknown))), true);
  check('formatSeconds', [T.formatSeconds(257), T.formatSeconds(null)], ['4:17', '']);

  console.log('\nthe pressing a card\'s Find downloads as (v1.0.1)');
  const pressed = (id, tracks, extra) => ({ ...release(id, tracks), ...extra });
  const cd = { status: 'Official', media: undefined };
  const dummyGroup = [
    pressed('2017-vinyl', DUMMY_10, { status: 'Official', date: '2017-01-01', format: '12" Vinyl' }),
    pressed('promo', DUMMY_10, { status: 'Promotion', date: '1994-06-01', format: 'CD' }),
    pressed('us-cd', withFire("'"), { status: 'Official', date: '1995-01-01', format: 'CD' }),
    pressed('uk-cd', DUMMY_10, { status: 'Official', date: '1994-08-22', format: 'CD' }),
    pressed('eu-cd', DUMMY_10, { status: 'Official', date: '1994-09-01', format: 'CD' }),
  ].map(({ format, ...r }) => ({ ...r, media: r.media.map((m) => ({ ...m, format })) }));
  check('the most common tracklist, Official, CD, earliest', T.representativeRelease(dummyGroup).id, 'uk-cd');
  check('an Official vinyl beats a CD promo when nothing plainer shares its tracklist',
    T.representativeRelease(dummyGroup.filter((r) => ['2017-vinyl', 'promo'].includes(r.id))).id, '2017-vinyl');
  check('a lone pressing with tracks is chosen', T.representativeRelease([release('only', DUMMY_10)]).id, 'only');
  check('no tracks anywhere: nothing to stand for the album', T.representativeRelease([{ id: 'x', media: [] }, cd]), null);
  check('an empty group: nothing', T.representativeRelease([]), null);

  console.log(failures ? `\n${failures} FAILED` : '\nall passed');
  process.exit(failures ? 1 : 0);
})();
