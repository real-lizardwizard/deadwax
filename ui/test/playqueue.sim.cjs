/**
 * The player's queue: what "previous" does, what shuffle plays first, when a song counts as
 * played and when it counts again, what happens when a song won't play, and which file a song
 * is asked for as.
 *
 * A script for the same reason as the other sims: there is no JS test runner here. What it pins
 * is behaviour a person notices only after living with it - a "previous" that never restarts,
 * a shuffle that ignores the song you tapped, a play counted for skipping to the end, a week of
 * listening on a locked phone that counted nothing, a favourite heard twice and counted once, an
 * album in a pocket stopped dead by one missing file, or a setting on Navidrome's Players page
 * quietly turning every song into a transcode Safari can't seek in. And which address a hi-res song
 * gets under the "Maximum quality" setting, from what Navidrome says of it.
 *
 * Run it with:  node ui/test/playqueue.sim.cjs
 */

const { execFileSync } = require('child_process');
const fs = require('fs'), os = require('os'), path = require('path');

const UI = path.resolve(__dirname, '..');
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-playqueue-'));

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/playQueue.ts', 'src/player/api.ts', '--rootDir', 'src', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
], { cwd: UI, stdio: 'inherit' });

const {
  startQueue, current, nextIndex, previousAction, countsAsPlayed, listenedStep, EMPTY_QUEUE,
  LISTEN_SLACK_SECONDS, NEW_LISTEN, listenStarted, listenHeard, afterFailure, LOAD_RETRY_DELAY_MS,
  MEDIA_ERR_ABORTED, MEDIA_ERR_NETWORK, MEDIA_ERR_DECODE, MEDIA_ERR_SRC_NOT_SUPPORTED,
} = require(path.join(OUT, 'lib/playQueue.js'));
const { playableType, streamUrl, fragmentedUrl, toQueueTrack } = require(path.join(OUT, 'player/api.js'));

let failures = 0;
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  if (!ok) failures++;
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`));
}

const track = (id, fields = {}) => ({
  id, title: `song ${id}`, artist: 'a', album: 'b', albumId: 'al', coverArt: null,
  duration: 200, contentType: 'audio/flac', suffix: 'flac', ...fields,
});
const album = ['1', '2', '3', '4', '5'].map(track);
const ids = (queue) => queue.tracks.map((t) => t.id);

/* a deterministic "random", so a shuffle can be checked */
function seeded(seed) {
  return () => {
    seed = (seed * 16807) % 2147483647;
    return (seed - 1) / 2147483646;
  };
}

/* ========================================================================== */
console.log('\nstarting a queue');

check('tapping the third song plays the third song', current(startQueue(album, 2)).id, '3');
check('the whole album is queued, in order', ids(startQueue(album, 2)), ['1', '2', '3', '4', '5']);
check('an empty album is an empty queue', startQueue([], 0), EMPTY_QUEUE);
check('a start past the end plays the last song', current(startQueue(album, 99)).id, '5');

{
  const shuffled = startQueue(album, 3, true, seeded(7));
  check('shuffle still plays the tapped song first', current(shuffled).id, '4');
  check('shuffle plays every song exactly once', [...ids(shuffled)].sort(), ['1', '2', '3', '4', '5']);
  check('shuffle actually shuffles', ids(shuffled).join('') !== '41235', true);
  //? the Shuffle button asks for no song in particular: the opener must not always come first
  const openers = new Set([7, 11, 13, 17, 23].map((seed) => current(startQueue(album, null, true, seeded(seed))).id));
  check('the Shuffle button starts on a random song, not always the first', openers.size > 1, true);
  check('the Shuffle button still queues every song once', [...ids(startQueue(album, null, true, seeded(7)))].sort(), ['1', '2', '3', '4', '5']);
  check('no song in particular, unshuffled, starts at the top', current(startQueue(album, null)).id, '1');
}

/* ========================================================================== */
console.log('\nnext, and the end of the queue');

check('next is the one after', nextIndex({ tracks: album, index: 1 }), 2);
check('the last song has no next - playing stops', nextIndex({ tracks: album, index: 4 }), null);

/* ========================================================================== */
console.log('\nprevious');

check('early in a song, previous goes back one',
  previousAction({ tracks: album, index: 2 }, 1.5), { kind: 'go', index: 1 });
check('past three seconds, previous restarts the song',
  previousAction({ tracks: album, index: 2 }, 40), { kind: 'restart' });
check('the first song only ever restarts',
  previousAction({ tracks: album, index: 0 }, 0.5), { kind: 'restart' });

/* ========================================================================== */
console.log('\nwhat counts as a play');

check('half of a 200s song counts', countsAsPlayed(100, 200), true);
check('just short of half does not', countsAsPlayed(99, 200), false);
check('four minutes of a long song is enough', countsAsPlayed(240, 1200), true);
check('a 30s song never counts', countsAsPlayed(30, 30), false);
check('an unknown length never counts', countsAsPlayed(500, 0), false);

/* one position update: `step` seconds of song in `elapsed` seconds of wall clock */
const update = (previous, now, fields = {}) =>
  listenedStep({ previous, now, elapsed: now - previous, rate: 1, seeked: false, ...fields });

/*
 * A song played through the way the element reports it: an update every `every` seconds of wall
 * clock at playback rate `rate`, with a seek to `seekTo` (if any) when the position passes
 * `seekAt`. Returns the seconds counted as heard.
 */
function play({ length = 200, every = 0.25, rate = 1, seekAt = null, seekTo = null }) {
  let listened = 0, position = 0, seeked = false;
  while (position < length) {
    if (seekAt !== null && position >= seekAt && !seeked) {
      position = seekTo;
      seeked = true;
      listened += listenedStep({ previous: seekAt, now: position, elapsed: 0.05, rate, seeked: true });
      continue;
    }
    const now = Math.min(position + every * rate, length);
    listened += listenedStep({ previous: position, now, elapsed: every, rate, seeked: false });
    position = now;
  }
  return listened;
}

check('a quarter-second tick is listening', update(10, 10.25), 0.25);
check('a step a moment ahead of the clock still counts in full',
  update(20, 20.5, { elapsed: 0.25 }), 0.5);
check('a seek forward is not listening', update(10, 150, { elapsed: 0.05, seeked: true }), 0);
check('a seek back is not listening', update(150, 10, { elapsed: 0.05 }), 0);
check('a jump the seek flag missed counts no more than the time that passed',
  update(10, 150, { elapsed: 0.25 }), 0.25 + LISTEN_SLACK_SECONDS);
check('a clock that stood still allows only the slack', update(10, 12, { elapsed: 0 }), LISTEN_SLACK_SECONDS);

check('a song heard through counts every second of it', play({}), 200);
check('updates only every 5s - a locked phone - still count as listening',
  update(40, 45, { elapsed: 5 }), 5);
check('a song heard through on a locked phone, 5s between updates, is a play',
  countsAsPlayed(play({ every: 5 }), 200), true);
check('a seek forward adds nothing: 0-50 heard, then 150-200', play({ seekAt: 50, seekTo: 150 }), 100);
check('a 4x step in a second of wall clock counts 4s of song at 4x',
  update(20, 24, { elapsed: 1, rate: 4 }), 4);
check('the same step at 1x is capped at the second that passed, plus the slack',
  update(20, 24, { elapsed: 1, rate: 1 }), 1 + LISTEN_SLACK_SECONDS);
check('a song played through at 4x counts every second of it', play({ rate: 4 }), 200);
check('a rate the element never set counts as 1x', update(20, 24, { elapsed: 1, rate: 0 }), 1 + LISTEN_SLACK_SECONDS);

{
  //? Seeking to the end of a song and letting the last second play must not count it.
  const listened = play({ seekAt: 0.5, seekTo: 199 });
  check('skipping to the end and hearing it out is not a play', countsAsPlayed(listened, 200), false);
}

/* ========================================================================== */
console.log('\na listen, and hearing a song again');

/* `seconds` heard in steps of `every`, reporting each step that made it a play */
function hear(listen, seconds, { duration = 200, every = 0.25 } = {}) {
  const submits = [];
  for (let heard = 0; heard < seconds; heard += every) {
    const result = listenHeard(listen, every, duration);
    listen = result.listen;
    if (result.submit) submits.push(listen.heard);
  }
  return { listen, submits };
}

{
  const HOUR = 3600 * 1000;
  //? "next" pressed while paused at 9:00 loads a song that starts playing at 11:00
  const loadedAt = 9 * HOUR, playingAt = 11 * HOUR;
  const loaded = NEW_LISTEN;
  check('a song only loaded has not started', loaded.startedAt, 0);
  const started = listenStarted(loaded, playingAt);
  check('the first time it plays is when the listen started - not when it loaded',
    started.listen.startedAt === playingAt && started.listen.startedAt !== loadedAt, true);
  check('and is when Navidrome hears what is playing', started.nowPlaying, true);
  const again = listenStarted(started.listen, playingAt + 60_000);
  check('playing again after a pause or a stall is the same listen', again.listen.startedAt, playingAt);
  check('and does not tell Navidrome again', again.nowPlaying, false);
}

{
  const first = hear(listenStarted(NEW_LISTEN, 1).listen, 200);
  check('a song heard through is reported once, at half way', first.submits, [100]);
  check('hearing on past half does not report it again', first.listen.submitted, true);
  const paused = hear(hear(NEW_LISTEN, 60).listen, 60);
  check('pausing at a minute and carrying on is one listen, reported once', paused.submits, [100]);

  //? "previous" past three seconds, or play once it has ended: the song again, from the top
  const second = hear(NEW_LISTEN, 200);
  check('heard a second time, it is reported a second time', second.submits, [100]);
  check('a new listen has heard nothing and started nowhere',
    [NEW_LISTEN.heard, NEW_LISTEN.startedAt, NEW_LISTEN.submitted], [0, 0, false]);
  check('a second listen is only a play once enough of IT is heard',
    hear(NEW_LISTEN, 99).listen.submitted, false);
  check('a listen of a 30s song is never reported', hear(NEW_LISTEN, 30, { duration: 30 }).submits, []);
}

/* ========================================================================== */
console.log('\na song that will not play');

{
  const failure = (fields) => afterFailure({
    queue: { tracks: album, index: 2 }, code: MEDIA_ERR_SRC_NOT_SUPPORTED, intendsToPlay: true,
    retried: false, ...fields,
  });

  check('a song that fails to load is asked for once more', failure({}), { kind: 'retry' });
  check('so is one whose connection dropped', failure({ code: MEDIA_ERR_NETWORK }), { kind: 'retry' });
  check('failing again, the next song plays', failure({ retried: true }), { kind: 'skip', index: 3 });
  check('a file that cannot be decoded is passed over at once', failure({ code: MEDIA_ERR_DECODE }),
    { kind: 'skip', index: 3 });
  check('a failure the element named no code for is passed over', failure({ code: 0 }),
    { kind: 'skip', index: 3 });
  check('nobody meant it to play: it stops and shows why', failure({ intendsToPlay: false }), { kind: 'stop' });
  check('nor is it asked for again', failure({ intendsToPlay: false, code: MEDIA_ERR_NETWORK }), { kind: 'stop' });
  check('the browser told to stop is left at that', failure({ code: MEDIA_ERR_ABORTED }), { kind: 'stop' });

  const last = { tracks: album, index: 4 };
  check('the last song is still asked for again', failure({ queue: last }), { kind: 'retry' });
  check('and failing again, playing stops - there is nothing after it',
    failure({ queue: last, retried: true }), { kind: 'stop' });
  check('the wait before asking again is a hiccup, not a stop',
    LOAD_RETRY_DELAY_MS >= 1000 && LOAD_RETRY_DELAY_MS <= 3000, true);
}

{
  //? The reported case, walked through: One, Two, a song Navidrome can't send, Three. Two ends
  //? into the broken song; it is asked for again, fails again, and Three plays - with nobody
  //? touching the phone.
  const queue = { tracks: ['One', 'Two', 'Broken', 'Three'].map((id) => track(id)), index: 2 };
  let retried = false, action, steps = [];
  for (;;) {
    action = afterFailure({ queue, code: MEDIA_ERR_SRC_NOT_SUPPORTED, intendsToPlay: true, retried });
    steps.push(action.kind);
    if (action.kind !== 'retry') break;
    retried = true;
  }
  check('a broken song in the middle of an album: tried again, then passed over', steps, ['retry', 'skip']);
  check('and the song after it plays', current({ ...queue, index: action.index }).id, 'Three');
}

/* ========================================================================== */
console.log('\nwhich file a song is asked for as');

/* what an iPhone's Safari answers: no Opus in Ogg, no Vorbis, no WMA */
const iphone = (type) => ['audio/flac', 'audio/mpeg', 'audio/mp4'].includes(type);

check('a FLAC is asked for as it is, by name',
  streamUrl(track('s1'), iphone), '/deadwax/navidrome/stream/s1?format=raw');
check('an Ogg the browser cannot play is asked for as MP3',
  streamUrl(track('s2', { contentType: 'audio/ogg', suffix: 'ogg' }), iphone),
  '/deadwax/navidrome/stream/s2?format=mp3');
check('a song nobody named a type for is asked for as it is',
  streamUrl(track('s3', { contentType: null, suffix: null }), iphone),
  '/deadwax/navidrome/stream/s3?format=raw');
check('the id is escaped', streamUrl(track('a/b c'), iphone),
  '/deadwax/navidrome/stream/a%2Fb%20c?format=raw');

check('an .opus file is asked about as Opus in Ogg',
  playableType({ contentType: 'audio/ogg', suffix: 'opus' }), 'audio/ogg; codecs="opus"');
check('an .ogg file is asked about as Vorbis in Ogg',
  playableType({ contentType: 'audio/ogg', suffix: 'ogg' }), 'audio/ogg; codecs="vorbis"');
check('an .oga file too', playableType({ contentType: 'audio/ogg', suffix: 'OGA' }), 'audio/ogg; codecs="vorbis"');
check('anything else by its content type', playableType({ contentType: 'audio/flac', suffix: 'flac' }), 'audio/flac');
check('no type and no suffix is nothing to ask', playableType({ contentType: null, suffix: null }), null);

{
  //? A browser that plays Vorbis but not Opus gets the Vorbis file as it is, and the Opus one
  //? as MP3 - which a bare audio/ogg, the same for both, could never tell apart.
  const vorbisOnly = (type) => type === 'audio/ogg; codecs="vorbis"';
  check('Vorbis plays as it is where Vorbis plays',
    streamUrl(track('v', { contentType: 'audio/ogg', suffix: 'ogg' }), vorbisOnly),
    '/deadwax/navidrome/stream/v?format=raw');
  check('Opus is transcoded there',
    streamUrl(track('o', { contentType: 'audio/ogg', suffix: 'opus' }), vorbisOnly),
    '/deadwax/navidrome/stream/o?format=mp3');
}

/* ========================================================================== */
console.log('\nhi-res songs, and the "Maximum quality" setting');

{
  const hires = track('h', { sampleRate: 192000, bitDepth: 24, channels: 2 });
  const chromium = () => true;
  check('no setting given: every address as it was before it existed',
    [streamUrl(hires, iphone), streamUrl(hires, iphone, true), fragmentedUrl(hires)],
    ['/deadwax/navidrome/stream/h?format=raw', '/deadwax/navidrome/stream/h?format=raw&wrap=mp4', '/deadwax/navidrome/stream/h?format=raw&wrap=fmp4']);
  check('"Original": the same', [streamUrl(hires, iphone, true, 'original'), fragmentedUrl(hires, 'original')],
    ['/deadwax/navidrome/stream/h?format=raw&wrap=mp4', '/deadwax/navidrome/stream/h?format=raw&wrap=fmp4']);
  check('48 kHz, Safari: resampled, in an MP4', streamUrl(hires, iphone, true, '48000'), '/deadwax/navidrome/stream/h?format=raw&wrap=mp4&max_rate=48000');
  check('48 kHz, Chromium: in an MP4 too - deadwax only sends a resampled song repackaged',
    streamUrl(hires, chromium, false, '48000'), '/deadwax/navidrome/stream/h?format=raw&wrap=mp4&max_rate=48000');
  check('...and the stream\'s fragmented MP4', fragmentedUrl(hires, '48000'), '/deadwax/navidrome/stream/h?format=raw&wrap=fmp4&max_rate=48000');
  check('a CD FLAC at 48 kHz: untouched, in either browser',
    [streamUrl(track('c', { sampleRate: 44100, bitDepth: 16 }), chromium, false, '48000'), streamUrl(track('c', { sampleRate: 44100 }), iphone, true, '48000'), fragmentedUrl(track('c', { sampleRate: 48000 }), '48000')],
    ['/deadwax/navidrome/stream/c?format=raw', '/deadwax/navidrome/stream/c?format=raw&wrap=mp4', '/deadwax/navidrome/stream/c?format=raw&wrap=fmp4']);
  check('a rate Navidrome didn\'t give: as it always was', streamUrl(track('u'), chromium, false, '48000'), '/deadwax/navidrome/stream/u?format=raw');
  check('a browser that can\'t play FLAC gets a transcode, never resampled',
    streamUrl(hires, (type) => type === 'audio/mpeg', true, '48000'), '/deadwax/navidrome/stream/h?format=mp3');
  check('a 24/96 FLAC of 20 bits: sent as it is (the server can\'t read it)',
    streamUrl(track('t', { sampleRate: 96000, bitDepth: 20 }), chromium, false, '48000'), '/deadwax/navidrome/stream/t?format=raw');
}

{
  const album = { id: 'al', name: 'The Album', artist: 'Them', coverArt: 'cv' };
  const song = { id: 's', title: 'One', samplingRate: 192000, bitDepth: 24, channelCount: 2 };
  const got = toQueueTrack(song, album);
  check('Navidrome\'s samplingRate, bitDepth and channelCount carried into the queue',
    [got.sampleRate, got.bitDepth, got.channels], [192000, 24, 2]);
  const bare = toQueueTrack({ id: 's', title: 'One' }, album);
  check('...0 for each when it didn\'t say', [bare.sampleRate, bare.bitDepth, bare.channels], [0, 0, 0]);
  check('...beside what was always there', [bare.album, bare.artist, bare.albumId, bare.coverArt], ['The Album', 'Them', 'al', 'cv']);
}

console.log(failures ? `\n${failures} FAILED` : '\nall passed');
process.exit(failures ? 1 : 0);
