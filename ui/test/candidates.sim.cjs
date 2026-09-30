/**
 * The Soulseek candidates panel's logic (ui/src/lib/candidates.ts), ported from main.js in v0.9.10.
 *
 * The cases here are the ones a wrong answer would hide: a filter that lets through what it should
 * refuse (an unjudgeable signal passing a minimum), a Re-search that silently narrows a search to one
 * name, and the advertised speed going back to reading like a promise.
 *
 * Run it with:  node ui/test/candidates.sim.cjs
 */

const { execFileSync } = require('child_process');
const fs = require('fs'), os = require('os'), path = require('path');

const UI = path.resolve(__dirname, '..');
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-candidates-'));

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/candidates.ts', '--outDir', OUT, '--module', 'commonjs', '--target', 'es2022',
  '--skipLibCheck', '--moduleResolution', 'node',
], { cwd: UI, stdio: 'inherit' });

const C = require(path.join(OUT, 'lib/candidates.js'));

let failures = 0;
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  if (!ok) failures++;
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`));
}

const candidate = (fields = {}) => ({
  username: 'bob', directory: 'share\\Dummy', directory_name: 'Dummy', score: 0.8,
  signals: { title_match: 1, track_count: 1, duration_match: null, edition: 0.5, format: 1, peer: 0.2 },
  matched_tracks: 11, expected_tracks: 11, audio_file_count: 11, detected_edition_tags: [],
  formats: ['flac'], upload_speed: 1048576, queue_length: 0, has_free_slot: true,
  total_size: 300 * 1024 * 1024, bitrates: [1000], files: [], ...fields,
});

const filters = (fields = {}) => ({
  freeSlotOnly: false, completeOnly: false, minScore: 0, formats: new Set(),
  minSignals: C.noSignalMinimums(), quality: { ...C.NO_QUALITY_FILTERS }, ...fields,
});
const quality = (fields) => filters({ quality: { ...C.NO_QUALITY_FILTERS, ...fields } });

console.log('filters');
check('nothing set lets everything through', C.passesFilters(candidate(), filters()), true);
check('free slot only refuses a busy peer', C.passesFilters(candidate({ has_free_slot: false }), filters({ freeSlotOnly: true })), false);
check('min score is against the percentage', [79, 80, 81].map((m) => C.passesFilters(candidate(), filters({ minScore: m }))), [true, true, false]);
check('complete only refuses a folder missing tracks', C.passesFilters(candidate({ matched_tracks: 10 }), filters({ completeOnly: true })), false);
check('...but not one with no tracklist to be complete against', C.passesFilters(candidate({ expected_tracks: 0, matched_tracks: 0 }), filters({ completeOnly: true })), true);
check('a format chip keeps folders offering that format', C.passesFilters(candidate({ formats: ['mp3'] }), filters({ formats: new Set(['flac']) })), false);
check('a signal minimum is a minimum', C.passesFilters(candidate(), filters({ minSignals: { ...C.noSignalMinimums(), peer: 25 } })), false);
check('an UNJUDGED signal cannot satisfy a minimum', C.passesFilters(candidate(), filters({ minSignals: { ...C.noSignalMinimums(), duration_match: 5 } })), false);
check('the badge counts the minimums set', C.activeSignalCount(filters({ minSignals: { ...C.noSignalMinimums(), peer: 10, edition: 5 } })), 2);

console.log('\nquality (v0.9.11)');
const mp3 = (bitrates, extra = {}) => candidate({ formats: ['mp3'], bitrates, bit_depths: [], sample_rates: [], ...extra });
const flac = (extra = {}) => candidate({ formats: ['flac'], bitrates: [], bit_depths: [], sample_rates: [], ...extra });
check('a bitrate floor is judged by the WORST file', [mp3([320]), mp3([128, 320])].map((c) => C.passesFilters(c, quality({ minBitrate: 320 }))), [true, false]);
check('a lossy folder that reported no bitrate fails a floor', C.passesFilters(mp3([]), quality({ minBitrate: 192 })), false);
check('...but a lossless one passes it - lossless is above any lossy bitrate', C.passesFilters(flac(), quality({ minBitrate: 320 })), true);
check('a bit-depth floor', [flac({ bit_depths: [24] }), flac({ bit_depths: [16, 24] })].map((c) => C.passesFilters(c, quality({ minBitDepth: 24 }))), [true, false]);
check('an UNREPORTED depth never passes "24-bit"', C.passesFilters(flac(), quality({ minBitDepth: 24 })), false);
check('a sample-rate floor', [flac({ sample_rates: [96000] }), flac({ sample_rates: [44100] })].map((c) => C.passesFilters(c, quality({ minSampleRate: 88200 }))), [true, false]);
const mb = 1024 * 1024;
check('album size range', [100, 300, 900].map((m) => C.passesFilters(candidate({ total_size: m * mb }), quality({ minSizeMb: 200, maxSizeMb: 800 }))), [false, true, false]);
check('the badge counts what is on', C.activeQualityCount({ ...C.NO_QUALITY_FILTERS, minBitDepth: 24, maxSizeMb: 800 }), 2);

console.log('\nsorting');
const pool = [
  mp3([320], { username: 'lossy320', total_size: 90 * mb }),
  flac({ username: 'cd', bit_depths: [16], sample_rates: [44100], total_size: 300 * mb }),
  flac({ username: 'hires', bit_depths: [24], sample_rates: [96000], total_size: 900 * mb }),
  flac({ username: 'silent', total_size: 280 * mb }),
];
check('best match keeps the server order', C.sortCandidates(pool, 'score').map((c) => c.username), ['lossy320', 'cd', 'hires', 'silent']);
check('highest quality: lossless first, then depth and rate; unreported sorts below reported', C.sortCandidates(pool, 'quality').map((c) => c.username), ['hires', 'cd', 'silent', 'lossy320']);
check('largest and smallest', [C.sortCandidates(pool, 'size_desc')[0].username, C.sortCandidates(pool, 'size_asc')[0].username], ['hires', 'lossy320']);
check('sorting copies - the result is never reordered in place', pool[0].username, 'lossy320');

console.log('\nwhat a row says about quality');
check('depth and rate as reported', C.depthRateText(flac({ bit_depths: [24], sample_rates: [96000] })), ' 24-bit 96kHz');
check('mixed folders as ranges', C.depthRateText(flac({ bit_depths: [16, 24], sample_rates: [44100, 96000] })), ' 16-24-bit 44.1-96kHz');
check('nothing reported, nothing said', C.depthRateText(flac()), '');
check('VBR is said', C.bitrateText([245], true), ' VBR 245kbps');

console.log('\nauto-grab (v0.9.16)');
{
  const strong = candidate({ username: 'strong', score: 0.9, has_free_slot: false });
  const weak = candidate({ username: 'weak', score: 0.6 });
  check('the top candidate, when it scores 75 or more', C.autoGrabPick([strong, weak], filters(), 'score').pick.username, 'strong');
  check('...its runners-up are the rest of the shown list', C.autoGrabPick([strong, weak], filters(), 'score').list.map((c) => c.username), ['strong', 'weak']);
  check('nothing when the best match is weak', C.autoGrabPick([weak], filters(), 'score'), null);
  check('through the default filters - a filtered-out strong one is never grabbed',
    C.autoGrabPick([strong, weak], filters({ freeSlotOnly: true }), 'score'), null);
  check('nothing from an empty result', C.autoGrabPick([], filters(), 'score'), null);
}

console.log('\nre-search');
check('an unedited box is not an override - it would drop every other name', C.queryOverride('Ye Donda', 'Ye Donda'), '');
check('an edited one is, trimmed', C.queryOverride('  Ye Donda 2021 ', 'Ye Donda'), 'Ye Donda 2021');
check('an emptied one is not', C.queryOverride('   ', 'Ye Donda'), '');

console.log('\nthe row');
check('formats of a result, sorted and once each', C.resultFormats([candidate({ formats: ['mp3', 'flac'] }), candidate()]), ['flac', 'mp3']);
check('bitrate range', [C.bitrateText([320]), C.bitrateText([256, 320, 192]), C.bitrateText([])], [' 320kbps', ' 192-320kbps', '']);
check('tracks against a tracklist, files without', [C.trackSummary(candidate()), C.trackSummary(candidate({ expected_tracks: 0 }))], ['11/11 tracks', '11 files']);
check('score colour bands', [C.scoreClass(75), C.scoreClass(40), C.scoreClass(39)], ['good', 'mid', 'bad']);
check('the advertised speed says whose average it is', C.peerSpeedLabel(1048576), 'peer avg 1.0 MB/s');
check('...and never reads as a broken string', C.peerSpeedLabel(0), 'peer avg unknown');
check('no measurement renders as nothing', C.measuredSpeed(candidate()), null);
check('one transfer is not hedged', C.measuredSpeed(candidate({ measured_speed: 800 * 1024, measured_samples: 1 })).text, 'you got 800 KB/s');
check('an average is', C.measuredSpeed(candidate({ measured_speed: 800 * 1024, measured_samples: 4 })).text, 'you got ~800 KB/s');

console.log('\nalready in the store (step 2)');
{
  const held = (fields = {}) => ({
    path: 'Portishead/Dummy (1994)', paths: ['Portishead/Dummy (1994)'], artist: 'Portishead', album: 'Dummy',
    edition: '', track_count: 10, expected_tracks: 10, formats: ['flac'], complete: true,
    fills_gaps: false, filed_to: null, ...fields,
  });
  const answer = (fields = {}) => ({ query: '', queries: [], response_count: 0, candidates: [], ...fields });

  check('held complete stands in for the results, folder, count and formats',
    C.storeStatus(answer({ held: held() })),
    { kind: 'held', title: 'Already in your library', lines: ['Portishead/Dummy (1994)', '10 of 10 tracks · FLAC'] });
  check('...every folder of a set stored one per disc, and every format',
    C.storeStatus(answer({ held: held({ paths: ['A/B (Disc 1)', 'A/B (Disc 2)'], track_count: 20, expected_tracks: 20, formats: ['flac', 'mp3'] }) })).lines,
    ['A/B (Disc 1)', 'A/B (Disc 2)', '20 of 20 tracks · FLAC, MP3']);
  check('...with no tracklist to count against, just the count',
    C.storeStatus(answer({ held: held({ expected_tracks: 0, track_count: 1 }) })).lines[1], '1 track · FLAC');
  check('held in part is NOT a status - the search ran', C.storeStatus(answer({ held: held({ track_count: 9, complete: false }) })), null);
  const part = (fields = {}) => held({ track_count: 9, complete: false, ...fields });
  check('...a note: held where filing would go, a download files only what that folder lacks',
    C.storeNotes(answer({ held: part({ fills_gaps: true, filed_to: 'Portishead/Dummy (1994)' }) })),
    ["You have 9 of 10 tracks of this pressing, in Portishead/Dummy (1994). Downloading it files only the tracks that folder doesn't have yet."]);
  check('...held somewhere filing would NOT go, it says the copy is separate and where',
    C.storeNotes(answer({ held: part({ path: 'Portishead/Dummy', paths: ['Portishead/Dummy'], filed_to: 'Portishead/Dummy (1994)' }) })),
    ['You have 9 of 10 tracks of this pressing, in Portishead/Dummy. A download would be filed separately, in Portishead/Dummy (1994), rather than fill in that folder.']);
  check('...and when where it would go is unknown, only that it may be separate',
    C.storeNotes(answer({ held: part() })),
    ['You have 9 of 10 tracks of this pressing, in Portishead/Dummy (1994). A download may be filed separately rather than fill in that folder.']);
  check('...a set in two folders names which one fills',
    C.storeNotes(answer({ held: part({ paths: ['A/B (1997)', 'A/B (Disc 2)'], fills_gaps: true, filed_to: 'A/B (1997)' }) })),
    ["You have 9 of 10 tracks of this pressing, in A/B (1997) and A/B (Disc 2). Downloading it files only the tracks A/B (1997) doesn't have yet."]);
  check('...never the promise that it fills in the missing ones - a download brings only what its folder has',
    [part({ fills_gaps: true, filed_to: 'Portishead/Dummy (1994)' }), part()].some((h) => C.storeNotes(answer({ held: h }))[0].includes('fills in the missing')),
    false);

  const downloading = (fields = {}) => ({ job_id: 4, status: 'downloading', username: 'bob', files: 10, done_files: 4, ...fields });
  check('downloading names the peer and how far it has got, and where to cancel it',
    C.storeStatus(answer({ downloading: downloading() })),
    { kind: 'downloading', title: 'Already downloading', lines: ['From bob · 4 of 10 files', 'Open Downloads to cancel it if you want another peer.'] });
  check('each state in a few words',
    ['queued', 'downloading', 'organizing', 'complete'].map((status) => C.downloadProgressText(downloading({ status }))),
    ['queued', '4 of 10 files', 'being filed into your library now', 'being filed into your library now']);
  check('being filed: downloaded, and no line about cancelling for another peer',
    ['organizing', 'complete'].map((status) => C.storeStatus(answer({ downloading: downloading({ status }) }))),
    [0, 1].map(() => ({ kind: 'downloading', title: 'Already downloaded', lines: ['From bob · being filed into your library now'] })));
  check('...and a download slskd said nothing about is just downloading',
    C.downloadProgressText(downloading({ done_files: undefined })), 'downloading');
  check('downloading wins over held, as the server checks it first',
    C.storeStatus(answer({ downloading: downloading(), held: held() })).kind, 'downloading');
  check('a download of PART of it is a note, not a status - the search ran',
    [C.storeStatus(answer({ downloading_part: downloading({ files: 5, done_files: 2 }) })),
     C.storeNotes(answer({ downloading_part: downloading({ files: 5, done_files: 2 }) }))],
    [null, ['A download of part of this pressing is already running: 5 files from bob · 2 of 5 files.']]);
  check('...one file, queued, beside a part held (the running download first)',
    C.storeNotes(answer({ downloading_part: downloading({ files: 1, status: 'queued' }), held: part({ fills_gaps: true, filed_to: 'Portishead/Dummy (1994)' }) })),
    ['A download of part of this pressing is already running: 1 file from bob · queued.',
     "You have 9 of 10 tracks of this pressing, in Portishead/Dummy (1994). Downloading it files only the tracks that folder doesn't have yet."]);

  const pressing = (fields = {}) => ({ path: 'Portishead/Dummy (1994) [2014 vinyl]', release_mbid: 'x', edition: '2014 vinyl', year: '2014', track_count: 11, formats: ['flac'], ...fields });
  check('another pressing, by its edition',
    C.storeNotes(answer({ other_pressings: [pressing()] })),
    ['You also have another pressing: 2014 vinyl · FLAC · Portishead/Dummy (1994) [2014 vinyl]']);
  check('...or its year when the folder has no edition, one line each',
    C.storeNotes(answer({ other_pressings: [pressing({ edition: '', path: 'Portishead/Dummy (1994)', year: '1994' }), pressing({ formats: [] })] })),
    ['You also have another pressing: 1994 · FLAC · Portishead/Dummy (1994)',
     'You also have another pressing: 2014 vinyl · Portishead/Dummy (1994) [2014 vinyl]']);
  check('other pressings are noted beside a status too', C.storeNotes(answer({ held: held(), other_pressings: [pressing()] })).length, 1);
  check('an ordinary result says nothing', [C.storeStatus(answer()), C.storeNotes(answer())], [null, []]);
}

console.log(failures ? `\n${failures} FAILED` : '\nall passed');
process.exit(failures ? 1 : 0);
