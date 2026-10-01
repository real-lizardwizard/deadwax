/**
 * One base tracklist per release group, and what each pressing changes about it - BOTH copies of
 * the rules, held to one answer.
 *
 * interface/scripts/tracklistDiff.mjs draws the main page's release grid; ui/src/lib/tracklistDiff.ts
 * (2.0.0-player.13) draws the app's album-you-don't-have page and picks its default pressing. The
 * image's UI stage copies only ui/, so the app can't import the .mjs, and the two live side by side
 * until the main page retires. Every check below runs against each copy.
 *
 * Two kinds of case. Hand-made tracklists for the rules one at a time - vinyl lengths that disagree
 * with the CDs, curly and straight apostrophes in one title, a bonus track in the middle, a single
 * mix 37 seconds longer. And real MusicBrainz groups - The Slow Rush, Dummy, Third - as MusicBrainz
 * answered them, in tests/fixtures/pressings/*.json, with what the .mjs answered recorded beside
 * them: the base, the pressing that stands for the album, and every pressing's differences. A copy
 * that picks another pressing or calls another track a bonus fails there, by release.
 *
 * Run it with:  node ui/test/tracklist.sim.cjs   (TMPDIR somewhere writable inside a sandbox)
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')
const { pathToFileURL } = require('url')

const UI = path.resolve(__dirname, '..')
const FIXTURES = path.resolve(__dirname, '../../tests/fixtures/pressings')
const MJS = pathToFileURL(path.resolve(__dirname, '../../interface/scripts/tracklistDiff.mjs')).href
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-tracklist-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/tracklistDiff.ts', '--outDir', OUT, '--module', 'commonjs', '--target', 'es2022',
  '--skipLibCheck', '--moduleResolution', 'node',
], { cwd: UI, stdio: 'inherit' })

const GROUPS = ['slow-rush', 'dummy', 'third'].map((name) => [name, JSON.parse(fs.readFileSync(path.join(FIXTURES, `${name}.json`), 'utf8'))])

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

/** The rules one at a time, through one copy. */
function suite(T) {
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
  const renamedAt = (seconds) => T.diffTracklists(T.releaseTracks(release('b', DUMMY_10)),
    T.releaseTracks(release('r', [['Mysterons', 306], ['Sour Times (Nobody Loves Me)', 253 + seconds], ...DUMMY_10.slice(2)])));
  check('a rename is a new title within 5 seconds of the old one; past that, one added and one removed',
    [5, 6].map((seconds) => [renamedAt(seconds).renamed.length, renamedAt(seconds).added.length]), [[1, 0], [0, 1]]);
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
  const tie = (extra) => dummyGroup.filter((r) => r.id === 'uk-cd').map((r) => ({ ...r, ...extra }));
  check('a year-only date sorts after a full date in the same year',
    T.representativeRelease([...tie({ id: 'year-only', date: '1994' }), ...tie({})]).id, 'uk-cd');
  check('an undated pressing sorts after every dated one',
    T.representativeRelease([...tie({ id: 'undated', date: undefined }), ...tie({ date: '2020-01-01' })]).id, 'uk-cd');
  check('no disambiguation beats a disambiguated pressing, whatever the dates',
    T.representativeRelease([...tie({ id: 'club', date: '1990-01-01', disambiguation: 'club edition' }), ...tie({})]).id, 'uk-cd');
  const twins = [...tie({ id: 'b-twin' }), ...tie({ id: 'a-twin' })];
  check('a full tie falls to the release id, in either order',
    [T.representativeRelease(twins).id, T.representativeRelease([...twins].reverse()).id], ['a-twin', 'a-twin']);
  check('a lone pressing with tracks is chosen', T.representativeRelease([release('only', DUMMY_10)]).id, 'only');
  check('no tracks anywhere: nothing to stand for the album', T.representativeRelease([{ id: 'x', media: [] }, cd]), null);
  check('an empty group: nothing', T.representativeRelease([]), null);

  //? the two rules the real groups never test (review): a tie for the most common tracklist, and a
  //? plain format against no disambiguation - a copy that drifts on either picks another pressing
  //? than the main page's card Find downloads, with every real-group check still green
  console.log('\nties, and format against disambiguation');
  const ten = release('ten', DUMMY_10), eleven = release('eleven', withFire("'"));
  check('a tie for the most common tracklist goes to the one given first, either way round',
    [T.chooseBase([ten, eleven]).index, T.chooseBase([eleven, ten]).index, T.releaseTracks(ten).length === T.chooseBase([ten, eleven]).tracks.length], [0, 0, true]);
  check('...and so does the pressing that stands for the album',
    [T.representativeRelease([{ ...ten, status: 'Official' }, { ...eleven, status: 'Official' }]).id,
      T.representativeRelease([{ ...eleven, status: 'Official' }, { ...ten, status: 'Official' }]).id], ['ten', 'eleven']);
  const asFormat = (r, format, extra) => ({ ...r, ...extra, media: r.media.map((m) => ({ ...m, format })) });
  check('a CD with a disambiguation beats a vinyl without one: the format is asked first',
    T.representativeRelease([
      asFormat(release('vinyl-plain', DUMMY_10), '12" Vinyl', { status: 'Official', date: '1994-01-01' }),
      asFormat(release('cd-remaster', DUMMY_10), 'CD', { status: 'Official', date: '2014-01-01', disambiguation: 'remaster' }),
    ]).id, 'cd-remaster');
}

/** Real groups as MusicBrainz answered them, through one copy, against what the .mjs answered. */
function real(T) {
  for (const [name, { releases, expected }] of GROUPS) {
    console.log(`\n${name} (${releases.length} pressings, as MusicBrainz has them)`);
    const base = T.chooseBase(releases);
    check('the base: the most common tracklist, and who stands for it',
      { index: base.index, id: releases[base.index].id, count: base.count, total: base.total }, expected.base);
    check('the pressing that stands for the album', T.representativeRelease(releases).id, expected.representative);
    const differing = releases.filter((release) => {
      const diff = T.diffTracklists(base.tracks, T.releaseTracks(release));
      return JSON.stringify({ chips: T.summarizeDiff(diff).map((c) => c.label), ...diff }) !== JSON.stringify(expected.diffs[release.id]);
    }).map((release) => release.id);
    check('every pressing\'s differences, chips and all', differing, []);
  }

  console.log('\nwhat the real groups say, in words a person checked');
  const [, slowRush] = GROUPS[0];
  const diffs = slowRush.expected.diffs;
  const named = (prefix) => diffs[slowRush.releases.find((release) => release.id.startsWith(prefix)).id];
  check('The Slow Rush: nine of ten share the usual tracklist', [slowRush.expected.base.count, slowRush.expected.base.total], [9, 10]);
  check('...the Japanese CD adds "Patience" after "One More Hour"', named('452ccdb4').added.map((x) => [x.title, x.length, x.after]), [['Patience', 293, 'One More Hour']]);
  check('...the single-mix digital release has "Borderline" at 4:34, against 3:58',
    named('3a12923d').versions.map((v) => [v.title, T.formatSeconds(v.from), T.formatSeconds(v.to)]), [['Borderline', '3:58', '4:34']]);
  const [, dummy] = GROUPS[1];
  check('Dummy: twelve of twenty, a ten-track CD without "It’s a Fire"',
    [dummy.expected.base.count, dummy.expected.base.total, dummy.expected.diffs[dummy.releases.find((r) => r.id.startsWith('87888070')).id].removed.map((x) => x.title)],
    [12, 20, ['It’s a Fire']]);
  const [, third] = GROUPS[2];
  check('Third: thirteen of seventeen alike', [third.expected.base.count, third.expected.base.total], [13, 17]);
}

(async () => {
  const copies = [['tracklistDiff.mjs', await import(MJS)], ['tracklistDiff.ts', require(path.join(OUT, 'tracklistDiff.js'))]];
  for (const [name, T] of copies) {
    console.log(`\n======== ${name}`);
    suite(T);
    real(T);
  }

  console.log('\n======== the two copies');
  const exported = (T) => Object.keys(T).filter((key) => typeof T[key] === 'function').sort();
  check('export the same functions', exported(copies[1][1]), exported(copies[0][1]));
  check('...and the same thresholds', ['LENGTH_TOLERANCE_S', 'OTHER_VERSION_S', 'OTHER_VERSION_SHARE'].map((key) => copies[1][1][key]),
    ['LENGTH_TOLERANCE_S', 'OTHER_VERSION_S', 'OTHER_VERSION_SHARE'].map((key) => copies[0][1][key]));
  //? every pair of pressings in every group, both ways round - not only against the base
  let pairs = 0, disagree = 0;
  for (const [, { releases }] of GROUPS) {
    for (const one of releases) for (const other of releases) {
      pairs++;
      const answer = (T) => JSON.stringify(T.diffTracklists(T.releaseTracks(one), T.releaseTracks(other)));
      if (answer(copies[0][1]) !== answer(copies[1][1])) disagree++;
    }
  }
  check(`the two diff every pair of real pressings alike (${pairs} pairs)`, disagree, 0);
  //? and pick alike: the base and the pressing that stands for the album, with every pressing of every
  //? real group put first in turn - the default pressing the app opens on is the one Find downloads
  let orders = 0, pickDiffer = 0;
  for (const [, { releases }] of GROUPS) {
    for (const first of releases) {
      orders++;
      const order = [first, ...releases.filter((other) => other !== first)];
      const pick = (T) => JSON.stringify([T.chooseBase(order).index, T.representativeRelease(order).id]);
      if (pick(copies[0][1]) !== pick(copies[1][1])) pickDiffer++;
    }
  }
  check(`...and pick the same base and pressing whichever comes first (${orders} orders)`, pickDiffer, 0);

  console.log(failures ? `\n${failures} FAILED` : '\nall passed');
  process.exit(failures ? 1 : 0);
})();
