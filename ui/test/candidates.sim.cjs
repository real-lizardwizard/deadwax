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
  minSignals: C.noSignalMinimums(), ...fields,
});

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

console.log(failures ? `\n${failures} FAILED` : '\nall passed');
process.exit(failures ? 1 : 0);
