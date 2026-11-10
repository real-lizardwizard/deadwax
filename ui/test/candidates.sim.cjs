/**
 * The Soulseek candidates' logic (ui/src/lib/candidates.ts), ported from main.js in v0.9.10 for the main
 * page's candidates panel, and the app's Sources' since (that panel's own words - its rows' quality, format
 * and speed text, its badges - went with the main page in 2.0.0-player.66).
 *
 * The cases here are the ones a wrong answer would hide: a filter that lets through what it should
 * refuse (an unjudgeable signal passing a minimum), a Re-search that silently narrows a search to one
 * name, and the advertised speed going back to reading like a promise.
 *
 * And for the app's Sources sheet (2.0.0-player.15) - its cards' words (lib/candidates.ts) and You >
 * Getting albums (lib/getSettings.ts): the Lossless chip (unknown never passes); Speed - measured
 * ("what you got from them", green), the peer's own average (never the download speed), or none -
 * and its bar against 3 MB/s; Starts ("now", "3 ahead"); Quality and Tracks; the amber "Missing …"
 * line; what the sheet says while asking and under the cards; when a pick must leave the choice to
 * you, and the line saying why; the quality floor as chips pressed (320 kbps's only while it is the
 * floor) and as the filters a pick goes by; what a first read seeds from the main page's settings.
 * After review: Tracks counted against the release's AUDIO tracks (a CD+DVD shared whole is "14 of
 * 14", agreeing with the missing line); no pick without a tracklist or a release id (the album as a
 * whole scores on edition, format and peer alone); the one line the sheet says to VoiceOver for
 * each outcome; a seed that carries over only what differs from the defaults; `seeded` read.
 *
 * And for Get, as the main page had it (2.0.0-player.41): Format in You's words and the server's
 * values, Prefer lossless the default; a server answer's Format and `unseeded` read safely; the seed
 * carrying the main page's Format over (only when it isn't the default) and only the keys left to
 * carry over; and a card's reasons - the score's signals as chips (word, value, band; an unjudged
 * one left out, in the panel's order) and the edition words found in the folder's name, coloured.
 *
 * And for the search extras (2.0.0-player.50): Complete albums only as the card counts Tracks (every
 * AUDIO track present - the whole CD of a CD+DVD passes, which the main page's completeOnly, left as it
 * is, refuses), agreeing with the card's own Tracks and Missing words; and the desktop's sample-rate
 * floors - Any, 44.1, 48, 88.2, 96 kHz and up - by the folder's worst file, unreported never passing,
 * each set floor counted as one more filter pressed.
 *
 * Run it with:  node ui/test/candidates.sim.cjs
 */

const { execFileSync } = require('child_process');
const fs = require('fs'), os = require('os'), path = require('path');

const UI = path.resolve(__dirname, '..');
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-candidates-'));

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/candidates.ts', 'src/lib/getSettings.ts', '--outDir', OUT, '--module', 'commonjs', '--target', 'es2022',
  '--skipLibCheck', '--moduleResolution', 'node',
], { cwd: UI, stdio: 'inherit' });

const C = require(path.join(OUT, 'lib/candidates.js'));
const G = require(path.join(OUT, 'lib/getSettings.js'));

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
check('score colour bands', [C.scoreClass(75), C.scoreClass(40), C.scoreClass(39)], ['good', 'mid', 'bad']);

console.log('\nthe Lossless chip (2.0.0-player.15): every file lossless, and unknown never passes');
{
  const lossless = (fields) => filters({ lossless: true, ...fields });
  check('a folder of FLACs passes, of MP3s doesn\'t', [C.passesFilters(flac(), lossless()), C.passesFilters(mp3([320]), lossless())], [true, false]);
  check('...one MP3 among the FLACs is not a lossless folder', C.passesFilters(candidate({ formats: ['flac', 'mp3'] }), lossless()), false);
  check('...every lossless format counts (ALAC, APE, WAV, AIFF, WavPack)', ['alac', 'ape', 'wav', 'aiff', 'wv'].map((f) => C.passesFilters(candidate({ formats: [f] }), lossless())), [true, true, true, true, true]);
  check('a folder whose formats nobody could tell never passes', C.passesFilters(candidate({ formats: [] }), lossless()), false);
  check('off, it lets everything through as before', C.passesFilters(mp3([128]), filters({ lossless: false })), true);
}

console.log('\na source card\'s Speed: measured, their own average, or none - and never a promise');
{
  const MB = 1024 * 1024;
  check('measured from them before: green, and says so', C.speedFact(candidate({ measured_speed: 2.1 * MB, measured_samples: 1, upload_speed: 9 * MB })),
    { kind: 'measured', text: '2.1 MB/s', note: 'what you got from them', percent: 70 });
  check('...an average of several transfers is hedged', C.speedFact(candidate({ measured_speed: 900 * 1024, measured_samples: 3 })).text, '~900 KB/s');
  check('otherwise the peer\'s own average, said to be theirs - never "you\'ll get"', C.speedFact(candidate({ upload_speed: 1.2 * MB })),
    { kind: 'advertised', text: '1.2 MB/s', note: 'their usual speed', percent: 40 });
  check('neither: unknown, and an empty bar', C.speedFact(candidate({ upload_speed: 0 })), { kind: 'unknown', text: 'Unknown', note: 'no speed reported yet', percent: 0 });
  check('the bar is the speed against 3 MB/s, full past it', [C.SPEED_BAR_FULL, C.speedFact(candidate({ upload_speed: 9 * MB })).percent, C.speedFact(candidate({ upload_speed: 0.3 * MB })).percent], [3 * MB, 100, 10]);
}

console.log('\nStarts, Quality, Tracks, and what is missing');
{
  check('a free slot starts now; a queue says how many ahead; no slot and nobody ahead is next',
    [C.startsFact(candidate({ has_free_slot: true, queue_length: 4 })), C.startsFact(candidate({ has_free_slot: false, queue_length: 3 })), C.startsFact(candidate({ has_free_slot: false, queue_length: 0 }))],
    [{ text: 'now', waits: false }, { text: 'after 3 others', waits: true }, { text: 'soon', waits: true }]);
  check('(2.0.6) one ahead is one other', C.startsFact(candidate({ has_free_slot: false, queue_length: 1 })).text, 'after 1 other');
  check('quality: depth/rate for lossless, ranges for a mixed folder, only what was reported',
    [C.qualityText(flac({ bit_depths: [16], sample_rates: [44100] })), C.qualityText(flac({ bit_depths: [24], sample_rates: [96000] })),
     C.qualityText(flac({ bit_depths: [16, 24], sample_rates: [44100, 96000] })), C.qualityText(flac({ bit_depths: [24] })), C.qualityText(flac({ sample_rates: [48000] })), C.qualityText(flac())],
    ['FLAC 16/44.1', 'FLAC 24/96', 'FLAC 16-24/44.1-96', 'FLAC 24-bit', 'FLAC 48 kHz', 'FLAC']);
  check('...a bitrate for lossy, VBR said, and unknown when there is no format at all',
    [C.qualityText(mp3([320])), C.qualityText(mp3([192, 320])), C.qualityText(mp3([245], { variable_bitrate: true })), C.qualityText(mp3([])), C.qualityText(candidate({ formats: [] }))],
    ['MP3 320k', 'MP3 192-320k', 'MP3 VBR 245k', 'MP3', 'Unknown']);
  check('tracks: "11 of 11" against a tracklist, files without', [C.tracksText(candidate({ matched_tracks: 10 })), C.tracksText(candidate({ expected_tracks: 0, audio_file_count: 1 }))], ['10 of 11', '1 file']);
  //? a CD+DVD (the fixture's HAARP: 34 tracks, 20 of them the DVD's): what a folder of audio can hold
  //? is the 14, and the missing line - which leaves video out - agrees with the count (review)
  const haarp = (fields) => candidate({ expected_tracks: 34, audio_expected: 14, matched_tracks: 14, missing_tracks: [], missing_count: 0, ...fields });
  check('a CD+DVD shared whole is 14 of 14 - never "14 of 34" with nothing said missing', [C.tracksText(haarp()), C.missingLine(haarp())], ['14 of 14', null]);
  check('...one track short is 13 of 14, and the line names it',
    [C.tracksText(haarp({ matched_tracks: 13, missing_tracks: [{ position: 3, disc: 1, title: 'Map of the Problematique' }], missing_count: 1 })),
     C.missingLine(haarp({ missing_tracks: [{ position: 3, disc: 1, title: 'Map of the Problematique' }], missing_count: 1 }))],
    ['13 of 14', 'Missing “Map of the Problematique”']);
  check('...the DVD\'s audio ripped too counts no higher than the CD\'s 14', C.tracksText(haarp({ matched_tracks: 34 })), '14 of 14');
  check('an answer from before audio_expected counts as the old panel did', C.tracksText(candidate({ matched_tracks: 10, audio_expected: undefined })), '10 of 11');
  const missing = (titles, count = titles.length) => candidate({ missing_tracks: titles.map((title, n) => ({ position: n + 1, disc: 1, title })), missing_count: count });
  check('nothing missing, no line', [C.missingLine(candidate()), C.missingLine(missing([]))], [null, null]);
  check('one missing, named in the board\'s quotes', C.missingLine(missing(['Threads'])), 'Missing “Threads”');
  check('two, and three', [C.missingLine(missing(['Threads', 'Small'])), C.missingLine(missing(['Silence', 'Hunter', 'Small']))],
    ['Missing “Threads” and “Small”', 'Missing “Silence”, “Hunter” and “Small”']);
  check('more than three: three named, the rest counted - the server names five of however many',
    C.missingLine(missing(['Silence', 'Hunter', 'Nylon Smile', 'The Rip', 'Plastic'], 8)), 'Missing “Silence”, “Hunter”, “Nylon Smile” and 5 more');
  check('...an untitled track by its number', C.missingLine(candidate({ missing_tracks: [{ position: 7, disc: 1, title: '' }], missing_count: 1 })), 'Missing “track 7”');
}

console.log('\nwhat the sheet says while asking, and under the cards');
{
  check('asking: the album and every name it is asked for under, once each',
    [C.searchingLine({ artist: 'Portishead', album_artist: 'Portishead', album: 'Third' }), C.searchingLine({ artist: 'Kanye West', album_artist: 'Ye', album: 'Donda' }),
     C.searchingLine({ artist: 'N/A', album_artist: '', album: 'Untitled' })],
    ['Looking for “Third” by Portishead…', 'Looking for “Donda” by Kanye West or Ye…', 'Looking for “Untitled”…']);
  const result = (n, queries = ['Portishead Third']) => ({ query: queries[0], queries, response_count: 9, candidates: Array.from({ length: n }, () => candidate()) });
  check('under the cards: what was searched, how many folders, how many pass',
    [C.searchedLine(result(41), 4), C.searchedLine(result(3), 3), C.searchedLine(result(1), 1), C.searchedLine(result(2, ['Kanye West Donda', 'Ye Donda']), 1)],
    ['Searched for “Portishead Third” · 41 sources, 4 match your filters', 'Searched for “Portishead Third” · 3 sources, all match your filters',
     'Searched for “Portishead Third” · 1 source, it matches your filters', 'Searched for “Kanye West Donda” and “Ye Donda” · 2 sources, 1 matches your filters']);
}

console.log('\nwhen "Pick the best source for me" leaves the choice to you, and says why');
{
  const answer = (fields = {}) => ({ query: 'q', queries: ['q'], response_count: 1, candidates: [], held: null, downloading: null, downloading_part: null, other_pressings: [], ...fields });
  const job = { job_id: 1, status: 'queued', username: 'bob', files: 11 };
  const keep = { path: 'P/T', paths: ['P/T'], artist: 'P', album: 'T', edition: '', track_count: 11, expected_tracks: 11, formats: ['flac'], fills_gaps: false, filed_to: null };
  check('downloading, held whole, part downloading, part held - each its reason',
    [C.autoPickBlocked(answer({ downloading: job })), C.autoPickBlocked(answer({ held: { ...keep, complete: true } })),
     C.autoPickBlocked(answer({ downloading_part: { ...job, files: 5 } })), C.autoPickBlocked(answer({ held: { ...keep, track_count: 9, complete: false } }))],
    ["It's already downloading", "It's already in your library", 'Part of it is already downloading', 'You already have part of it']);
  check('another pressing held, or nothing at all, doesn\'t stop a pick', [C.autoPickBlocked(answer({ other_pressings: [{ path: 'x' }] })), C.autoPickBlocked(answer()), C.autoPickBlocked(null)], [null, null, null]);
  check('the line saying why, or that nothing scored well enough - (2.0.6) and what to do', [G.notPickedLine('You already have part of it', 3), G.notPickedLine(null, 41)],
    ['You already have part of it - choose a source yourself.', 'No close match that passes your filters - choose a source yourself.']);
  //? (2.0.6) with nothing found there is nothing to choose - the empty state says so, and no line asks anyone to
  check('...no line at all when no source was found, blocked or not', [G.notPickedLine(null, 0), G.notPickedLine('This pressing has no tracklist to check the sources against', 0)], [null, null]);
  //? the album as a whole - MusicBrainz couldn't list its pressings - scores on edition, format and
  //? peer alone, so a two-track FLAC folder reaches 100: 75 means nothing there (review)
  const whole = { release_mbid: null, tracks: [] };
  const pressing = { release_mbid: 'rel', tracks: [{ position: 1 }] };
  check('no tracklist, or no release id: no pick, and why - the store\'s reasons first',
    [C.autoPickBlocked(answer(), whole), C.autoPickBlocked(answer(), { release_mbid: 'rel', tracks: [] }), C.autoPickBlocked(answer(), { release_mbid: null, tracks: [{ position: 1 }] }),
     C.autoPickBlocked(answer(), pressing), C.autoPickBlocked(answer({ downloading: job }), whole)],
    ['This pressing has no tracklist to check the sources against', 'This pressing has no tracklist to check the sources against',
     "It can't be told whether you already have this pressing", null, "It's already downloading"]);
  check('...said whole', G.notPickedLine(C.autoPickBlocked(answer(), whole), 2),
    'This pressing has no tracklist to check the sources against - choose a source yourself.');
  check('in the app, a download in flight is cancelled in Requests', C.storeStatus(answer({ downloading: { ...job, status: 'downloading', done_files: 4 } }), 'Requests').lines,
    ['From bob · 4 of 11 files', 'To get it from another source, cancel it in Requests first.']);
}

console.log('\nthe quality floor (You > Getting albums): the chips it starts as, the filters a pick goes by');
{
  check('the floors and the modes, as You words them', [G.QUALITY_FLOORS.map((f) => [f.value, f.label]), G.GET_MODES.map((m) => [m.value, m.label])],
    [[['any', 'Any'], ['320', '320 kbps'], ['lossless', 'Lossless'], ['24bit', '24-bit']], [['sources', 'Show me the sources'], ['pick', 'Pick the best source for me']]]);
  check('the default shows the sources, at any quality (and, since 2.0.0-player.41, prefers lossless)', G.GET_SETTINGS_DEFAULT, { get_mode: 'sources', quality_floor: 'any', format_preference: 'prefer_lossless' });
  check('each floor is a chip pressed: Lossless, 24-bit, 320 kbps - Any none',
    ['any', '320', 'lossless', '24bit'].map((floor) => G.floorFilters(floor)),
    [{ lossless: false, bit24: false, freeSlot: false, kbps320: false, complete: false }, { lossless: false, bit24: false, freeSlot: false, kbps320: true, complete: false },
     { lossless: true, bit24: false, freeSlot: false, kbps320: false, complete: false }, { lossless: false, bit24: true, freeSlot: false, kbps320: false, complete: false }]);
  const labels = (floor, filters) => G.sourceChips(floor, filters).map((chip) => `${chip.label}${chip.on ? '*' : ''}`);
  check('the chips: Lossless, 24-bit, Starts now (2.0.6, was Free slot), Complete albums only (2.0.0-player.50, never pressed by a floor) - and 320 kbps only while it is the floor (never a filter on out of sight)',
    [labels('lossless', G.floorFilters('lossless')), labels('320', G.floorFilters('320')), labels('320', G.NO_SOURCE_FILTERS), labels('any', G.NO_SOURCE_FILTERS)],
    [['Lossless*', '24-bit', 'Starts now', 'Complete albums only'], ['Lossless', '24-bit', '320 kbps*', 'Starts now', 'Complete albums only'],
     ['Lossless', '24-bit', '320 kbps', 'Starts now', 'Complete albums only'], ['Lossless', '24-bit', 'Starts now', 'Complete albums only']]);
  const pool = [mp3([320], { username: 'mp3' }), flac({ username: 'cd', bit_depths: [16] }), flac({ username: 'hires', bit_depths: [24], sample_rates: [96000] }), mp3([128], { username: 'thin' })];
  const passing = (sourceFilters) => pool.filter((c) => C.passesFilters(c, G.candidateFilters(sourceFilters))).map((c) => c.username);
  check('as filters: Any keeps all, 320 drops the thin MP3 (lossless passes a bitrate floor), Lossless the MP3s, 24-bit all but the hi-res',
    ['any', '320', 'lossless', '24bit'].map((floor) => passing(G.floorFilters(floor))),
    [['mp3', 'cd', 'hires', 'thin'], ['mp3', 'cd', 'hires'], ['cd', 'hires'], ['hires']]);
  check('Free slot is a slot', passing({ ...G.NO_SOURCE_FILTERS, freeSlot: true }).length, 4);
  check('a pick under a 24-bit floor takes the 24/96 only at 75 or more',
    [C.autoGrabPick([pool[1], { ...pool[2], score: 0.8 }], G.candidateFilters(G.floorFilters('24bit')), G.PICK_SORT)?.pick.username,
     C.autoGrabPick([pool[1], { ...pool[2], score: 0.7 }], G.candidateFilters(G.floorFilters('24bit')), G.PICK_SORT)],
    ['hires', null]);
  check('pressed chips are counted, so Clear filters shows only with some', [G.pressedCount(G.NO_SOURCE_FILTERS), G.pressedCount({ ...G.floorFilters('lossless'), freeSlot: true })], [0, 2]);
  check('a server answer read safely: what it doesn\'t know is the default',
    [G.readGetSettings({ get_mode: 'pick', quality_floor: 'flac', stored: ['get_mode'], seeded: true, can_save: true }), G.readGetSettings(null)],
    [{ get_mode: 'pick', quality_floor: 'any', format_preference: 'prefer_lossless', stored: ['get_mode'], seeded: true, unseeded: [], can_save: true },
     { get_mode: 'sources', quality_floor: 'any', format_preference: 'prefer_lossless', stored: [], seeded: false, unseeded: ['get_mode', 'quality_floor', 'format_preference'], can_save: true }]);
  check('...seeded as the server says, and always when something is stored',
    [G.readGetSettings({ stored: [], seeded: true }).seeded, G.readGetSettings({ stored: ['quality_floor'] }).seeded, G.readGetSettings({ stored: [], seeded: false }).seeded], [true, true, false]);
  check('a first read carries the floor over from the main page\'s settings: 24-bit, 16-bit (lossless only), 320 - only what differs from the defaults, and never picks for you',
    [{ candidateMinBitrate: 0, candidateMinBitDepth: 24 }, { candidateMinBitrate: 320, candidateMinBitDepth: 16 }, { candidateMinBitrate: 320, candidateMinBitDepth: 0 }, { candidateMinBitrate: 256, candidateMinBitDepth: 0 }]
      .map((preferences) => G.seedFromPreferences(preferences)),
    [{ quality_floor: '24bit' }, { quality_floor: 'lossless' }, { quality_floor: '320' }, {}]);
}

console.log('\nComplete albums only and the sample-rate floor (2.0.0-player.50)');
{
  //? a folder of the whole CD of a CD+DVD: the card says "14 of 14" (audio_expected) - the main page's
  //? completeOnly counts the film's tracks too, and refuses it; the app's chip doesn't
  const cdDvd = flac({ username: 'cddvd', expected_tracks: 34, matched_tracks: 14, audio_expected: 14, missing_count: 0, missing_tracks: [] });
  const short = flac({ username: 'short', expected_tracks: 11, matched_tracks: 10, audio_expected: 11, missing_count: 1, missing_tracks: [{ position: 3, disc: 1, title: 'Threads' }] });
  const whole = flac({ username: 'whole', expected_tracks: 11, matched_tracks: 11, audio_expected: 11, missing_count: 0, missing_tracks: [] });
  const older = flac({ username: 'older', expected_tracks: 11, matched_tracks: 10 });
  const loose = flac({ username: 'loose', expected_tracks: 0, matched_tracks: 0, audio_file_count: 12 });
  const named = flac({ username: 'named', expected_tracks: 11, matched_tracks: 11, audio_expected: 11, missing_tracks: [{ position: 3, disc: 1, title: 'Threads' }] });
  check('every track present, as the card counts Tracks: the whole CD of a CD+DVD and a whole folder pass; one missing a track, by count or by name, doesn\'t',
    [cdDvd, short, whole, named].map((c) => C.everyTrackPresent(c)), [true, false, true, false]);
  check('...an answer without audio_expected counts matched against expected, as the main page does; no tracklist, nothing to be complete against',
    [C.everyTrackPresent(older), C.everyTrackPresent(loose)], [false, true]);
  check('...and agrees with the card\'s own words: complete exactly when Tracks reads N of N and there is no Missing line',
    [cdDvd, short, whole].map((c) => [C.tracksText(c), C.missingLine(c), C.everyTrackPresent(c)]),
    [['14 of 14', null, true], ['10 of 11', 'Missing “Threads”', false], ['11 of 11', null, true]]);
  const pool = [cdDvd, short, whole, older, loose];
  const passing = (sourceFilters, minSampleRate) => pool.filter((c) => C.passesFilters(c, G.candidateFilters(sourceFilters, undefined, minSampleRate))).map((c) => c.username);
  check('the chip filters by it - the app\'s rule, never the main page\'s completeOnly', [passing({ ...G.NO_SOURCE_FILTERS, complete: true }), G.candidateFilters({ ...G.NO_SOURCE_FILTERS, complete: true }).completeOnly],
    [['cddvd', 'whole', 'loose'], false]);
  check('...off, it keeps them all', passing(G.NO_SOURCE_FILTERS).length, 5);
  check('the main page\'s completeOnly is as it was: the CD+DVD\'s whole CD refused there', C.passesFilters(cdDvd, filters({ completeOnly: true })), false);
  check('the sample-rate floors, as the desktop\'s chip offers them: Any, 44.1, 48, 88.2 and 96 kHz and up',
    G.SAMPLE_RATE_FLOORS.map((floor) => [floor.value, floor.label, floor.chip]),
    [[0, 'Any sample rate', 'Sample rate'], [44100, '44.1 kHz or more', '44.1 kHz+'], [48000, '48 kHz or more', '48 kHz+'], [88200, '88.2 kHz or more', '88.2 kHz+'], [96000, '96 kHz or more', '96 kHz+']]);
  check('...the chip says the floor, "Sample rate" for any (or one it doesn\'t know)', [0, 48000, 96000, 12345].map((rate) => G.sampleRateChip(rate)), ['Sample rate', '48 kHz+', '96 kHz+', 'Sample rate']);
  const rates = [flac({ username: '44', sample_rates: [44100] }), flac({ username: '48', sample_rates: [48000] }), flac({ username: 'mixed', sample_rates: [96000, 44100] }),
    flac({ username: '96', sample_rates: [96000] }), flac({ username: '88', sample_rates: [88200, 96000] }), flac({ username: 'unsaid', sample_rates: [] })];
  const floor = (rate) => rates.filter((c) => C.passesFilters(c, G.candidateFilters(G.NO_SOURCE_FILTERS, undefined, rate))).map((c) => c.username);
  check('by the folder\'s WORST file, a folder that reported none passing no floor: Any, 44.1, 48, 88.2, 96',
    [0, 44100, 48000, 88200, 96000].map(floor),
    [['44', '48', 'mixed', '96', '88', 'unsaid'], ['44', '48', 'mixed', '96', '88'], ['48', '96', '88'], ['96', '88'], ['96']]);
  check('a floor set is counted as one more pressed, so Clear filters shows; none set counts nothing',
    [G.pressedCount(G.NO_SOURCE_FILTERS, undefined, 48000), G.pressedCount(G.NO_SOURCE_FILTERS, undefined, 0), G.pressedCount({ ...G.NO_SOURCE_FILTERS, complete: true })], [1, 0, 1]);
}

console.log('\nFormat, kept for you on deadwax (2.0.0-player.41)');
{
  check('the default is Prefer lossless, as the main page\'s', G.GET_SETTINGS_DEFAULT.format_preference, 'prefer_lossless');
  check('You\'s words, in the main page\'s order', G.FORMATS.map((format) => [format.value, format.label]),
    [['any', 'Any'], ['prefer_lossless', 'Prefer lossless'], ['lossless_only', 'Lossless only']]);
  check('...the server\'s values, the default first', G.FORMAT_PREFERENCE_VALUES, ['prefer_lossless', 'any', 'lossless_only']);
  check('a server answer\'s Format read safely: a known one kept, anything else the default',
    ['lossless_only', 'any', 'flac', undefined, 'LOSSLESS_ONLY'].map((format) => G.readGetSettings({ format_preference: format }).format_preference),
    ['lossless_only', 'any', 'prefer_lossless', 'prefer_lossless', 'prefer_lossless']);
  check('...and `unseeded` as the server says - only keys there are, in their order; none said: every key before a first save, none after',
    [G.readGetSettings({ seeded: true, unseeded: ['format_preference', 'theme'] }).unseeded, G.readGetSettings({ seeded: true }).unseeded,
     G.readGetSettings({ seeded: false }).unseeded, G.readGetSettings({ seeded: true, unseeded: 'format_preference' }).unseeded],
    [['format_preference'], [], ['get_mode', 'quality_floor', 'format_preference'], []]);
  const main = (fields) => ({ candidateMinBitrate: 0, candidateMinBitDepth: 0, ...fields });
  check('the seed carries the main page\'s Format over - only when it isn\'t Prefer lossless, the default - beside the floor',
    [main({ formatPreference: 'lossless_only' }), main({ formatPreference: 'any', candidateMinBitDepth: 24 }), main({ formatPreference: 'prefer_lossless' }), main({ formatPreference: 'flac' }), main({})]
      .map((preferences) => G.seedFromPreferences(preferences)),
    [{ format_preference: 'lossless_only' }, { quality_floor: '24bit', format_preference: 'any' }, {}, {}, {}]);
  check('...and only the keys left to carry over: a user seeded before Format gets Format alone, never the floor again',
    [G.seedFromPreferences(main({ formatPreference: 'any', candidateMinBitDepth: 24 }), ['format_preference']),
     G.seedFromPreferences(main({ formatPreference: 'any', candidateMinBitDepth: 24 }), ['quality_floor']),
     G.seedFromPreferences(main({ formatPreference: 'any', candidateMinBitDepth: 24 }), [])],
    [{ format_preference: 'any' }, { quality_floor: '24bit' }, {}]);
}

console.log('\na card\'s reasons (2.0.0-player.41): the signals and the edition words, as the main page shows them');
{
  check('each judged signal a chip: its word, its value, its band - in the panel\'s order, the unjudged left out',
    C.signalChips(candidate({ signals: { peer: 0.2, format: 0.45, edition: 0.5, duration_match: null, track_count: 1, title_match: 0.745 } })),
    [{ signal: 'title_match', label: 'Track names', value: 75, band: 'good', meaning: C.SIGNAL_MEANINGS.title_match },
     { signal: 'track_count', label: 'Track count', value: 100, band: 'good', meaning: C.SIGNAL_MEANINGS.track_count },
     { signal: 'edition', label: 'Edition', value: 50, band: 'mid', meaning: C.SIGNAL_MEANINGS.edition },
     { signal: 'format', label: 'Format', value: 45, band: 'mid', meaning: C.SIGNAL_MEANINGS.format },
     { signal: 'peer', label: 'Availability', value: 20, band: 'bad', meaning: C.SIGNAL_MEANINGS.peer }]);
  check('...the words are SIGNAL_LABELS\'s, capitalised as the Signals chip names them; the bands scoreClass\'s (75 good, 40 mid)',
    [C.signalChips(candidate({ signals: { duration_match: 0.39 } })).map((chip) => [chip.label, chip.band]),
     C.signalChips(candidate({ signals: { duration_match: 0.4 } }))[0].band, C.signalChips(candidate({ signals: { duration_match: 0.744 } }))[0].band],
    [[['Track lengths', 'bad']], 'mid', 'mid']);
  check('...a signal the panel doesn\'t name keeps its own name, after the six; nothing judged, no chips',
    [C.signalChips(candidate({ signals: { peer: 1, tempo: 0.9 } })).map((chip) => chip.label), C.signalChips(candidate({ signals: { title_match: null } }))],
    [['Availability', 'Tempo'], []]);
  //? (2.0.6, UX batch 3) the six named in words a listener reads, each with what it measures - true to src/matching.py
  {
    const matching = fs.readFileSync(path.resolve(__dirname, '../../src/matching.py'), 'utf8')
    const weights = /WEIGHTS = \{([^}]*)\}/.exec(matching)[1].match(/"(\w+)":/g).map((key) => key.slice(1, -2))
    check('(2.0.6) a name and a meaning for every signal matching.py weighs, and none it doesn\'t', [Object.keys(C.SIGNAL_LABELS), Object.keys(C.SIGNAL_MEANINGS)], [weights, weights])
    check('(2.0.6) the names: never the code\'s titles, count, lengths or peer', Object.values(C.SIGNAL_LABELS), ['track names', 'track count', 'track lengths', 'edition', 'format', 'availability'])
    const tolerance = /DURATION_TOLERANCE_SEC = (\d+)/.exec(matching)[1]
    check(`(2.0.6) track lengths' meaning says matching.py's tolerance, ${tolerance} seconds`, C.SIGNAL_MEANINGS.duration_match.includes(`${tolerance} seconds`), true)
    //? score_edition only ever ADDS for the year (+0.25), so a plain pressing's folder with the wrong year still scores 1.0:
    //? the line may say the year helps, never that it has to agree (review: '1994 - Dummy' read Edition 100% beside "and year")
    check('(2.0.6) edition\'s meaning says its year helps, not that it must match', C.SIGNAL_MEANINGS.edition, 'whether its name says the same edition (deluxe, remaster…) - its year there helps')
    check('(2.0.6) availability is what score_peer weighs: a free slot, the queue, their speed', ['free slot', 'queue', 'speed'].every((word) => C.SIGNAL_MEANINGS.peer.includes(word)), true)
    check('(2.0.6) a signal deadwax doesn\'t name has no meaning to draw', C.signalChips(candidate({ signals: { tempo: 0.9 } }))[0].meaning, '')
  }
  check('the edition words found in the folder\'s name, each in its colour: yellow amber, red red, purple purple, green green, white plain',
    C.editionTags(candidate({ detected_edition_tags: ['ANNIVERSARY', 'BOX SET', 'DELUXE', 'LIMITED', 'REMASTER', 'SUPER DELUXE', 'SOMETHING NEW'] })),
    [{ tag: 'ANNIVERSARY', tone: 'plain' }, { tag: 'BOX SET', tone: 'green' }, { tag: 'DELUXE', tone: 'purple' }, { tag: 'LIMITED', tone: 'purple' },
     { tag: 'REMASTER', tone: 'amber' }, { tag: 'SUPER DELUXE', tone: 'red' }, { tag: 'SOMETHING NEW', tone: 'plain' }]);
  check('...none found, none drawn', C.editionTags(candidate()), []);
}

console.log('\nwhat the Sources sheet says to VoiceOver, one line for each outcome');
{
  const release = { artist: 'Portishead', album_artist: 'Portishead', album: 'Third' };
  const result = (n) => ({ query: 'Portishead Third', queries: ['Portishead Third'], candidates: Array.from({ length: n }, () => candidate()) });
  const said = (fields) => C.sourcesAnnouncement({ pending: false, release, error: null, status: null, result: null, shown: 0, notPicked: null, ...fields });
  check('asking, refused, held, nothing found, none passing, how many - and why none was picked',
    [said({ pending: true }), said({ error: "slskd isn't logged in to Soulseek" }), said({ status: { title: 'Already in your library' }, result: result(0) }),
     said({ result: result(0) }), said({ result: result(3), shown: 0 }), said({ result: result(1), shown: 0 }), said({ result: result(4), shown: 4 }), said({ result: result(1), shown: 1 }),
     said({ result: result(4), shown: 2, notPicked: 'You already have part of it - choose a source yourself.' })],
    ['Looking for “Third” by Portishead…', "slskd isn't logged in to Soulseek", 'Already in your library',
     'Nothing found for “Portishead Third”.', '3 sources found - none match your filters.', '1 source found - none matches your filters.', '4 sources.', '1 source.',
     '2 sources. You already have part of it - choose a source yourself.']);
  check('...and nothing before a search has begun', said({}), '');
  //? (review) Lossless only can leave nothing of an answer Soulseek gave: matching.py drops every folder
  //? with no lossless file then - "found nothing" would be false, and send you to the query
  const answered = (n, responses) => ({ ...result(n), response_count: responses });
  check('Lossless only, answers in, nothing left: nothing lossless, and the Format named - never "found nothing"',
    said({ result: answered(0, 3), format: 'lossless_only' }),
    'Nothing lossless found for “Portishead Third”. Some were found, but none with lossless files - your Format is Lossless only, which leaves the rest out. You can change it in You, under Getting albums.');
  check('...but no peer answering, another Format, or no Format known: found nothing, as ever',
    [said({ result: answered(0, 0), format: 'lossless_only' }), said({ result: answered(0, 3), format: 'prefer_lossless' }), said({ result: answered(0, 3), format: 'any' }), said({ result: answered(0, 3) })],
    Array(4).fill('Nothing found for “Portishead Third”.'));
  check('nothingLossless: only Lossless only, nothing left, and answers in',
    [C.nothingLossless(answered(0, 1), 'lossless_only'), C.nothingLossless(answered(1, 1), 'lossless_only'), C.nothingLossless(answered(0, 0), 'lossless_only'),
     C.nothingLossless(answered(0, 1), 'prefer_lossless'), C.nothingLossless(answered(0, 1), null)],
    [true, false, false, false, false]);
  check('...its line names every query searched', C.nothingLosslessLine({ query: 'Kanye West Donda', queries: ['Kanye West Donda', 'Ye Donda'] }),
    'Nothing lossless found for “Kanye West Donda” and “Ye Donda”.');
}

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
    ["You have 9 of 10 tracks of this pressing, in Portishead/Dummy (1994). Getting it adds only the tracks that folder doesn't have yet."]);
  check('...held somewhere filing would NOT go, it says the copy is separate and where',
    C.storeNotes(answer({ held: part({ path: 'Portishead/Dummy', paths: ['Portishead/Dummy'], filed_to: 'Portishead/Dummy (1994)' }) })),
    ['You have 9 of 10 tracks of this pressing, in Portishead/Dummy. Getting it would add a separate copy, in Portishead/Dummy (1994), rather than fill in that folder.']);
  check('...and when where it would go is unknown, only that it may be separate',
    C.storeNotes(answer({ held: part() })),
    ['You have 9 of 10 tracks of this pressing, in Portishead/Dummy (1994). Getting it may add a separate copy rather than fill in that folder.']);
  check('...a set in two folders names which one fills',
    C.storeNotes(answer({ held: part({ paths: ['A/B (1997)', 'A/B (Disc 2)'], fills_gaps: true, filed_to: 'A/B (1997)' }) })),
    ["You have 9 of 10 tracks of this pressing, in A/B (1997) and A/B (Disc 2). Getting it adds only the tracks A/B (1997) doesn't have yet."]);
  check('...never the promise that it fills in the missing ones - a download brings only what its folder has',
    [part({ fills_gaps: true, filed_to: 'Portishead/Dummy (1994)' }), part()].some((h) => C.storeNotes(answer({ held: h }))[0].includes('fills in the missing')),
    false);

  const downloading = (fields = {}) => ({ job_id: 4, status: 'downloading', username: 'bob', files: 10, done_files: 4, ...fields });
  check('downloading names the peer and how far it has got, and where to cancel it',
    C.storeStatus(answer({ downloading: downloading() })),
    { kind: 'downloading', title: 'Already downloading', lines: ['From bob · 4 of 10 files', 'To get it from another source, cancel it in Downloads first.'] });
  check('each state in a few words',
    ['queued', 'downloading', 'organizing', 'complete'].map((status) => C.downloadProgressText(downloading({ status }))),
    ['queued', '4 of 10 files', 'being added to your library now', 'being added to your library now']);
  check('being filed: downloaded, and no line about cancelling for another peer',
    ['organizing', 'complete'].map((status) => C.storeStatus(answer({ downloading: downloading({ status }) }))),
    [0, 1].map(() => ({ kind: 'downloading', title: 'Already downloaded', lines: ['From bob · being added to your library now'] })));
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
     "You have 9 of 10 tracks of this pressing, in Portishead/Dummy (1994). Getting it adds only the tracks that folder doesn't have yet."]);

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
