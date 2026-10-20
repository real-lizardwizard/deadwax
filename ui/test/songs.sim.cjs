/**
 * Song search (2.0.0-player.53): the songs a MusicBrainz recording search found and the albums each is on
 * (ui/src/lib/songs.ts), against real answers as MusicBrainz gave them on 2026-10-15 (tests/fixtures/songs/),
 * and the album opened from a song - its pressing and the song in its tracklist - against The Slow Rush's
 * real pressings, each track with its recording's id.
 *
 * What a wrong answer would hide: a dozen rows of one song told apart by a length (every take of "Roads" is
 * a recording of its own, all at score 100); the studio album buried among live tapes and compilations; a
 * bootleg listed before the official record; a remix merged into the song it remixes, or two bands of one
 * name merged; a later page's take adding a row rather than albums; a song nobody can get (on no release)
 * offered; an album you have unsaid, or one only the store has called yours; and on the album opened from a
 * song, the usual pressing shown when it lacks the song (the bonus-track case: Patience, only on The Slow
 * Rush's Japanese CD), another pressing forced when the usual one has it as another recording (Borderline's
 * single mix), or the song unmarked. After review: a pressing you hold WITHOUT the song said as the song held
 * (The Slow Rush's usual CD for Patience) - it is "a pressing in your library" now, and opens nothing of yours;
 * a song whose first takes were on no release coming back above rows already drawn; a live broadcast called a
 * live album in the fold's words; and rules the mutations didn't reach - the title tie-break, the first album
 * only the store has, the length from a later release, "&" and "and", a duet's artists in either order, a
 * track known by its recording's title. After the second review: a pressing you hold WITH the song as a
 * recording the page didn't bring (Dummy's 1994 CD, whose Roads only the second page of the real search
 * brings) said as a pressing without it - it is "a pressing in your library" unvouched, and the song held once
 * the library half's songs or the album's kept pressings vouch for it (SongEvidence), each piece of evidence
 * refused when it is another song, artist or album; an album's status upgraded by a later, better release, and
 * every one of the song's recordings on it kept; and accents folded mid-word ("Señor", "Mañana").
 *
 * Run it with:  node ui/test/songs.sim.cjs   (TMPDIR somewhere writable inside a sandbox)
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')
const FIXTURES = path.resolve(__dirname, '../../tests/fixtures/songs')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-songs-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/songs.ts', 'src/lib/pressings.ts', '--rootDir', 'src', '--outDir', OUT, '--module', 'commonjs', '--target', 'es2022',
  '--skipLibCheck', '--moduleResolution', 'node', '--lib', 'es2022,dom',
], { cwd: UI, stdio: 'inherit' })

const S = require(path.join(OUT, 'lib/songs.js'))
const P = require(path.join(OUT, 'lib/pressings.js'))
const { buildOwnedIndex } = require(path.join(OUT, 'lib/owned.js'))

let failures = 0
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`))
}

const load = (name) => JSON.parse(fs.readFileSync(path.join(FIXTURES, `${name}.json`), 'utf8'))
const roads = load('roads-portishead'), heyJude = load('hey-jude-beatles'), bohemian = load('bohemian-rhapsody-queen')
const misery = load('miss-misery-elliott-smith'), heyJudeFree = load('hey-jude-free'), roadsFree = load('roads-portishead-free')
const patience = load('patience-tame-impala'), rush = load('slow-rush-pressings')
const titles = (albums) => albums.map((album) => album.title)
const recordingIdOf = (prefix) => rush.releases.flatMap((r) => r.media.flatMap((m) => m.tracks)).find((t) => t.recording.id.startsWith(prefix)).recording.id

console.log('every take of one song is one song: its albums unioned, the studio album first')
{
  const songs = S.groupSongs(roads.recordings)
  check('Roads, fielded: twelve recordings (every one Portishead\'s Roads) are ONE song', [roads.recordings.length, songs.length, songs[0].title, songs[0].credit, songs[0].recordings.length],
    [12, 1, 'Roads', 'Portishead', 12])
  const { listed, folded } = S.songAlbumBands(songs[0])
  check('...Dummy listed, the only album; the live tapes and compilations behind the fold', [titles(listed), folded.length], [['Dummy'], 12])
  //? two of the twelve are live BROADCASTS (Roskilde 1998, Canal+'s Concert Privé) - named as their rows name them
  check('...the fold says what it holds', S.foldLabel(folded), 'On 12 compilations, live albums and broadcasts')
  check('...the row: the credit, the length on the album it names, and that album', S.songLine(songs[0], null), 'Portishead · 4:56 · Dummy')
  //? (2.0.0-player.55) the artists its credit names, by id - what Search's Top results pull in for a song (its sole artist)
  check('...the artists its credit names, by MusicBrainz id: Portishead alone', songs[0].artists, [{ id: '8f6bd1e4-fbe1-4f50-aa9b-94c450ec0f11', name: 'Portishead' }])
  const duo = S.groupSongs([{ id: 'd1', title: 'Under Pressure', 'artist-credit': [{ name: 'Queen', joinphrase: ' & ', artist: { id: 'Q' } }, { name: 'David Bowie', artist: { id: 'B' } }, { name: 'Queen', artist: { id: 'Q' } }],
    releases: [{ id: 'r1', 'release-group': { id: 'g1', title: 'Hot Space', 'primary-type': 'Album' } }] }, { id: 'd2', title: 'Nameless', 'artist-credit': [{ name: 'Nobody' }],
    releases: [{ id: 'r2', 'release-group': { id: 'g2', title: 'X', 'primary-type': 'Album' } }] }])
  check('...a duet two artists, each once (lowercase ids); a credit naming no id none', duo.map((song) => song.artists), [[{ id: 'q', name: 'Queen' }, { id: 'b', name: 'David Bowie' }], []])
  check('...Dummy\'s releases with the song kept (an .m4a filed holds a release id alone), and its recording',
    [listed[0].releases.length, listed[0].recordings], [5, ['ef37de8d-8fab-42ed-82da-fbfe25715989']])
  check('...its line: the kind and the year', S.songAlbumLine(listed[0], songs[0], null), 'Album · 1994')
  const roseland = folded.find((album) => album.title === 'Roseland NYC Live')
  const onlyWe = folded.find((album) => album.title === 'Only We')
  check('...a live tape\'s line says it is live, a bootleg, and another version\'s length', [S.songAlbumLine(roseland, songs[0], null), S.songAlbumLine(onlyWe, songs[0], null)],
    ['Live album · 2023 · 5:30', 'Live album · Bootleg · 1997 · 5:36'])
  const compilation = folded.find((album) => album.title === 'Dummy / Portishead')
  check('...the same take on a compilation: no length said (it is the same)', S.songAlbumLine(compilation, songs[0], null), 'Compilation · 2009')
}
{
  const [song] = S.groupSongs(bohemian.recordings)
  const { listed, folded } = S.songAlbumBands(song)
  check('Bohemian Rhapsody: the studio take\'s 353 releases in 133 groups and the live tapes, one song of 144 albums', [S.groupSongs(bohemian.recordings).length, song.albums.length], [1, 144])
  check('...A Night at the Opera first, then the singles by date', titles(listed), ['A Night at the Opera', 'Bohemian Rhapsody', 'Bohemian Rhapsody / These Are the Days of Our Lives', 'Under Pressure'])
  check('...a single credited to more than the song\'s artist says so', S.songAlbumLine(listed[3], song, null), 'Single · Queen & David Bowie · 1999')
  check('...140 behind the fold', S.foldLabel(folded), 'On 140 compilations, live albums and soundtracks')
  const ranks = folded.map((album) => ({ Official: 0, Promotion: 1, Bootleg: 2 }[album.status] ?? 3))
  check('...Official before Promotion before Bootleg before the rest, all the way down', ranks.every((rank, at) => at === 0 || ranks[at - 1] <= rank), true)
  const official = folded.filter((album) => album.status === 'Official').map((album) => `${album.date}~`)
  check('...and the earliest first within each', official.every((date, at) => at === 0 || official[at - 1] <= date), true)
  check('...the album a group\'s status is: its best release that has the song (Classic Queen: a Russian bootleg, and official pressings)',
    folded.find((album) => album.title === 'Classic Queen').status, 'Official')
}
{
  const songs = S.groupSongs(heyJude.recordings)
  check('Hey Jude by The Beatles: twelve takes - "HEY JUDE" among them - one song', [songs.length, songs[0].recordings.length], [1, 12])
}
{
  const songs = S.groupSongs(misery.recordings)
  const { listed, folded } = S.songAlbumBands(songs[0])
  check('Miss Misery: a song on no album or EP - nothing listed, all eleven behind the words', [songs.length, listed.length, folded.length, S.foldLabel(folded)],
    [1, 0, 11, 'On 11 compilations, live albums and soundtracks'])
  check('...a take on no release at all adds no album', songs[0].recordings.length, 12)
  check('...promotion releases before bootlegs: the soundtrack\'s promo is second (the earliest promo first)', titles(folded.slice(0, 2)),
    ['Screenadelica: Hot Sounds From Cool Movies', 'Music From the Miramax Motion Picture Good Will Hunting'])
}
{
  const songs = S.groupSongs(heyJudeFree.recordings)
  check('"hey jude" as words: covers - each artist its own song, the two takes of one artist one', [songs.length, songs.map((song) => song.recordings.length).filter((n) => n > 1)], [11, [2]])
  const zeze = songs.find((song) => song.recordings.length === 2)
  check('...that one\'s studio album listed, its live album folded', [titles(S.songAlbumBands(zeze).listed), titles(S.songAlbumBands(zeze).folded)], [['Diferente'], ['Duas horas de sucesso: Ao vivo']])
  check('"roads portishead" as words: titles - eleven songs, none of them Portishead\'s', [S.groupSongs(roadsFree.recordings).length, S.groupSongs(roadsFree.recordings).some((song) => song.credit === 'Portishead')], [11, false])
  check('...a song on no release left out (DJ Tripp\'s second take has none, its first one album)', S.groupSongs(roadsFree.recordings).find((song) => song.credit === 'DJ Tripp').albums.length, 1)
}

console.log('\nwhich song a recording is')
{
  const a = { id: 'x1', title: 'Sour Times', 'artist-credit': [{ name: 'Portishead', artist: { id: 'P' } }], releases: [{ id: 'r1', 'release-group': { id: 'g1', title: 'Dummy', 'primary-type': 'Album' } }] }
  const remix = { ...a, id: 'x2', title: 'Sour Times (Airbus Reconstruction)', releases: [{ id: 'r2', 'release-group': { id: 'g2', title: 'Glory Times', 'primary-type': 'EP' } }] }
  const shout = { ...a, id: 'x3', title: 'SOUR TIMES', releases: [{ id: 'r3', 'release-group': { id: 'g3', title: 'Live', 'primary-type': 'Album', 'secondary-types': ['Live'] } }] }
  const other = { ...a, id: 'x4', 'artist-credit': [{ name: 'Portishead', artist: { id: 'Q' } }] }
  const unnamed = { ...a, id: 'x5', 'artist-credit': [{ name: 'Portishead' }] }
  const nowhere = { ...a, id: 'x6', title: 'Nowhere', releases: [] }
  const songs = S.groupSongs([a, remix, shout, other, unnamed, nowhere])
  check('case and accents fold, the words in brackets don\'t: a remix stays its own song', songs.map((song) => [song.title, song.recordings]),
    [['Sour Times', ['x1', 'x3']], ['Sour Times (Airbus Reconstruction)', ['x2']], ['Sour Times', ['x4']], ['Sour Times', ['x5']]])
  check('...two bands of one name are two songs (by the artists\' ids), a credit with no ids by its words', [S.songKey(a) === S.songKey(other), S.songKey(unnamed)], [false, 'portishead\nsour times'])
  check('...and a song on no release isn\'t a song to show', songs.some((song) => song.title === 'Nowhere'), false)
  check('titleKey: punctuation, case and curly quotes folded; brackets kept', [S.titleKey('It’s a Fire!'), S.titleKey("IT'S A FIRE"), S.titleKey('Roads (Max Cooper remix)')],
    ["it's a fire", "it's a fire", 'roads (max cooper remix)'])
  //? (second review) an accent in the MIDDLE of a word - one at a word's end folds even without dropping the mark,
  //? since the mark left over is trimmed as the punctuation it then is
  const accent = (id, title) => ({ id, title, 'artist-credit': [{ name: 'Manu Chao', artist: { id: 'M' } }], releases: [{ id: `r-${id}`, 'release-group': { id: `g-${id}`, title: 'X', 'primary-type': 'Album' } }] })
  check('...accents folded mid-word: "Señor" is "Senor", and "Mañana" and "Manana" one song', [S.titleKey('Señor'), S.titleKey('Señor') === S.titleKey('Senor'),
    S.groupSongs([accent('n1', 'Mañana'), accent('n2', 'Manana')]).map((song) => song.recordings)], ['senor', true, [['n1', 'n2']]])
  check('...but an aside naming another take or a remaster dropped - as real answers title them beside the plain one',
    ['Roads (live)', 'Roads (Live UK 1998)', 'Hey Jude [Remastered 2015]', 'Hey Jude (2015 Remaster)', 'Wandering Star (mono)', 'Live Forever', 'Roads (Liverpool mix)', 'Roads (remix)'].map(S.titleKey),
    ['roads', 'roads', 'hey jude', 'hey jude', 'wandering star', 'live forever', 'roads (liverpool mix)', 'roads (remix)'])
  //? (review) "&" is "and"; and a duet credited the other way round is the same song
  const duet = (id, title, ...artists) => ({ id, title, 'artist-credit': artists.map((name) => ({ name, artist: { id: name } })), releases: [{ id: `r-${id}`, 'release-group': { id: `g-${id}`, title: 'X', 'primary-type': 'Album' } }] })
  check('"&" and "and" one title; a duet credited in either order one song', [S.titleKey('Rock & Roll') === S.titleKey('Rock and Roll'),
    S.groupSongs([duet('d1', 'Under Pressure', 'Queen', 'David Bowie'), duet('d2', 'Under Pressure', 'David Bowie', 'Queen')]).map((song) => song.recordings)],
    [true, [['d1', 'd2']]])
  //? (review) the song's length on an album from a later release of it, when the first one said none
  const unsaid = { id: 'l1', title: 'Roads', 'artist-credit': [{ name: 'Portishead', artist: { id: 'P' } }], releases: [
    { id: 'r1', 'release-group': { id: 'g1', title: 'Dummy', 'primary-type': 'Album' }, media: [{ track: [{ title: 'Roads' }] }] },
    { id: 'r2', 'release-group': { id: 'g1', title: 'Dummy', 'primary-type': 'Album' }, media: [{ track: [{ title: 'Roads', length: 302000 }] }] }] }
  check('...an album\'s length from a later release of it when the first says none', S.groupSongs([unsaid])[0].albums[0].length, 302000)
  const takes = S.groupSongs([{ ...a, id: 'y1', title: 'Roads (live)' }, { ...a, id: 'y2', title: 'Roads' }, { ...a, id: 'y3', title: 'Roads (Live UK 1998)' }, { ...a, id: 'y4', title: 'Roads (Max Cooper remix)' }])
  check('...so a take titled "(live)" is the song, said by its plain title once a take has one; a remix its own song', takes.map((song) => [song.title, song.recordings]),
    [['Roads', ['y1', 'y2', 'y3']], ['Roads (Max Cooper remix)', ['y4']]])
}

console.log('\nthe order an album is listed in')
{
  const album = (title, primary, secondary, status, date) => ({ id: title, title, primaryType: primary, secondaryTypes: secondary, kind: '', band: S.songBand(primary, secondary), status, date, credit: '', releases: [], recordings: [], length: null })
  check('the bands: Albums and EPs; Singles; the rest (a secondary type, a broadcast, nothing said)',
    [S.songBand('Album', []), S.songBand('EP', []), S.songBand('Single', []), S.songBand('Single', ['Compilation']), S.songBand('Album', ['Live']), S.songBand('Broadcast', []), S.songBand(null, [])],
    ['album', 'album', 'single', 'other', 'other', 'other', 'other'])
  const sorted = S.sortAlbums([
    album('single', 'Single', [], 'Official', '1990'), album('boot', 'Album', [], 'Bootleg', '1980'), album('promo', 'Album', [], 'Promotion', '1985'),
    album('later', 'Album', [], 'Official', '2001'), album('year', 'Album', [], 'Official', '1999'), album('full', 'Album', [], 'Official', '1999-03-01'),
    album('undated', 'Album', [], 'Official', ''), album('none', 'Album', [], '', '1970'), album('live', 'Album', ['Live'], 'Official', '1960'), album('ep', 'EP', [], 'Official', '1999-03-01'),
  ])
  check('...then Official, Promotion, Bootleg, anything else; the earliest first - a full date before its bare year, undated last; then by title', titles(sorted),
    ['ep', 'full', 'year', 'later', 'undated', 'promo', 'boot', 'none', 'single', 'live'])
  check('the fold\'s words, one of a kind and a mix', [S.foldLabel([album('a', 'Album', ['Compilation'], '', '')]), S.foldLabel([album('a', 'Album', ['Live'], '', '')]),
    S.foldLabel([album('a', 'Album', ['Soundtrack'], '', ''), album('b', 'Broadcast', [], '', '')]), S.foldLabel([album('a', 'Album', ['Remix'], '', '')])],
    ['On 1 compilation', 'On 1 live album', 'On 2 soundtracks and broadcasts', 'On 1 other record'])
  //? (review) a live record is a live ALBUM only when it is an album - as its row says ("Live broadcast", "Live ep")
  check('...a live album is an album: a live broadcast is a broadcast, a live EP or single another record, a live record of no type an album',
    [S.foldLabel([album('a', 'Broadcast', ['Live'], '', '')]), S.foldLabel([album('a', 'EP', ['Live'], '', '')]), S.foldLabel([album('a', 'Single', ['Live'], '', '')]),
      S.foldLabel([album('a', null, ['Live'], '', '')]), S.foldLabel([album('a', 'Album', ['Live'], '', ''), album('b', 'Broadcast', ['Live'], '', ''), album('c', 'EP', ['Live'], '', '')])],
    ['On 1 broadcast', 'On 1 other record', 'On 1 other record', 'On 1 live album', 'On 3 live albums, broadcasts and other records'])
  //? (second review) an album's status is its BEST release's, whatever order MusicBrainz lists them in - a bootleg and a
  //? promo listed before the official pressing - and every one of the song's recordings on it is kept (the album's
  //? address carries them: songPressing finds a pressing by any of them)
  const group = (id, title) => ({ id, title, 'primary-type': 'Album' })
  const live = group('g-first', 'Listed Bootleg First'), plain = group('g-plain', 'Plain Album')
  const take = (id, releases) => ({ id, title: 'Song', 'artist-credit': [{ name: 'Band', artist: { id: 'B' } }], releases })
  const [upgraded] = S.groupSongs([
    take('rec-a', [{ id: 'r-boot', status: 'Bootleg', date: '1990', 'release-group': live }, { id: 'r-promo', status: 'Promotion', date: '1991', 'release-group': live }]),
    take('rec-b', [{ id: 'r-plain', status: 'Official', date: '1992', 'release-group': plain }, { id: 'r-official', status: 'Official', date: '1995', 'release-group': live }]),
  ])
  const first = upgraded.albums.find((each) => each.id === 'g-first')
  check('an album listed first by a bootleg, then a promo, then an official pressing: Official - and among the Official albums by its earliest date (1990, before 1992)',
    [first.status, titles(upgraded.albums)], ['Official', ['Listed Bootleg First', 'Plain Album']])
  check('...and both of the song\'s recordings on it kept, in the order found', [first.recordings, first.releases], [['rec-a', 'rec-b'], ['r-boot', 'r-promo', 'r-official']])
  //? (review) the title tie-break - albums alike in band, status and date whose ids sort the other way from their titles
  check('...alike in band, status and date: by title, not by id', titles(S.sortAlbums([{ ...album('Zebra', 'Album', [], 'Official', '1999'), id: 'a' }, { ...album('Apple', 'Album', [], 'Official', '1999'), id: 'b' }])),
    ['Apple', 'Zebra'])
}

console.log('\nMore songs: a later page merged in')
{
  const first = roads.recordings.slice(0, 6), later = roads.recordings.slice(6)
  const before = S.groupSongs(first)
  const merged = S.appendSongs(first, later)
  check('a later page of the same song adds albums to it, not a row', [before.length, merged.songs.length, merged.added, merged.grown, merged.songs[0].albums.length - before[0].albums.length],
    [1, 1, 0, 6, 6])
  check('...every page\'s recordings kept, in order', merged.recordings.map((r) => r.id), roads.recordings.map((r) => r.id))
  const covers = S.appendSongs(heyJudeFree.recordings.slice(0, 5), heyJudeFree.recordings.slice(5))
  check('...new songs come after the ones drawn, which keep their places', [covers.added, covers.songs.slice(0, 4).map((song) => song.credit)],
    [7, S.groupSongs(heyJudeFree.recordings.slice(0, 5)).map((song) => song.credit)])
  //? (review) a song whose takes on the page drawn were on no release - so never drawn - and a later page brings one
  //? on a release: it comes after the rows drawn, never in its first take's place above them
  const take = (id, title, artist, group) => ({ id, title, 'artist-credit': [{ name: artist, artist: { id: artist } }],
    releases: group ? [{ id: `r-${id}`, 'release-group': { id: group, title: group, 'primary-type': 'Album' } }] : [] })
  const hiddenFirst = [take('b1', 'Breathe Roads', 'DJ Tripp', null), take('a1', 'Roads', 'Portishead', 'Dummy')]
  const back = S.appendSongs(hiddenFirst, [take('b2', 'Breathe Roads', 'DJ Tripp', 'Mashups'), take('c1', 'Sour Times', 'Portishead', 'Dummy')])
  check('a song whose first take was on no release, back on a later page: after the rows drawn, which keep their places', [S.groupSongs(hiddenFirst).map((song) => song.title), back.songs.map((song) => song.title), back.added],
    [['Roads'], ['Roads', 'Breathe Roads', 'Sour Times'], 2])
  const third = S.appendSongs(back.recordings, [take('d1', 'Glory Box', 'Portishead', 'Dummy')], back.songs)
  check('...and a page after that keeps the order DRAWN, not the order every page regrouped would give', third.songs.map((song) => song.title),
    ['Roads', 'Breathe Roads', 'Sour Times', 'Glory Box'])
  //? the same with real takes: DJ Tripp's two "Breathe Roads" (one on a release, one on none), the bare one on the first page
  const free = roadsFree.recordings
  const firstPage = [...free.slice(0, 3), free[4], ...free.slice(5, 8)], laterPage = [free[3], ...free.slice(8)]
  const real = S.appendSongs(firstPage, laterPage)
  const drawnFirst = S.groupSongs(firstPage).map((song) => song.credit)
  check('...real takes: DJ Tripp\'s mash-up, bare on the first page, comes after the six drawn', [real.songs.slice(0, drawnFirst.length).map((song) => song.credit), real.songs[drawnFirst.length].credit],
    [drawnFirst, 'DJ Tripp'])
  check('what a page said: new songs to VoiceOver only; albums alone; nothing', [S.moreSongsWords(3, 9), S.moreSongsWords(1, 0), S.moreSongsWords(0, 7), S.moreSongsWords(0, 1), S.moreSongsWords(0, 0)], [
    { note: null, said: '3 more songs from MusicBrainz' }, { note: null, said: '1 more song from MusicBrainz' },
    { note: 'No new songs - 7 more albums for the songs above.', said: 'No new songs - 7 more albums for the songs above' },
    { note: 'No new songs - 1 more album for the songs above.', said: 'No new songs - 1 more album for the songs above' },
    { note: 'MusicBrainz sent nothing new.', said: 'MusicBrainz sent nothing new' }])
}

console.log('\nwhat you have of it')
{
  const [song] = S.groupSongs(roads.recordings)
  const dummy = song.albums.find((album) => album.title === 'Dummy')
  const roseland = song.albums.find((album) => album.title === 'Roseland NYC Live')
  //? Dummy's 1994 UK CD - one of the pressings the search found Roads on
  const UK_CD = '87888070-1b25-4830-aebc-dee490058b74'
  const byGroup = buildOwnedIndex([{ path: 'Portishead/Dummy (1994)', artist: 'Portishead', album: 'Dummy', release_group_mbid: dummy.id, release_mbid: UK_CD }])
  check('Dummy held - a pressing the song is on: the row says so, as does Dummy\'s line', [S.songLine(song, byGroup), S.songAlbumLine(dummy, song, byGroup)],
    ['Portishead · 4:56 · Dummy · in your library', 'Album · 1994 · in your library'])
  check('...and the id bridge is asked about the release held', S.songAlbumHeldReleases(byGroup, dummy), [UK_CD])
  //? (second review) a pressing of Dummy this page of the search didn't find Roads on - Dummy's 1994 CD, the most common
  //? pressing, whose Roads is another recording (8a49dba0), past the first page of the real search (25 a page; and
  //? past this 12-recording fixture): nothing vouches for it either way - "a pressing in your library", never the
  //? song nor its absence ("another pressing" read as one WITHOUT the song) - and nothing of yours to open yet
  const CD_1994 = '76df3287-6cda-33eb-8e9a-044b5e15ffdd', ROADS_1994 = '8a49dba0-253a-4535-b87f-78bb035336ce'
  const cd94 = buildOwnedIndex([{ path: 'Portishead/Dummy (1994)', artist: 'Portishead', album: 'Dummy', release_group_mbid: dummy.id, release_mbid: CD_1994 }])
  check('a pressing held that the song isn\'t known on: the row claims nothing, Dummy\'s line says "a pressing in your library", and the id bridge is asked nothing',
    [S.songLine(song, cd94), S.songAlbumLine(dummy, song, cd94), S.songAlbumHeldReleases(cd94, dummy, song), S.songAlbumHolding(cd94, dummy, song).other.length],
    ['Portishead · 4:56 · Dummy', 'Album · 1994 · a pressing in your library', [], 1])
  //? ...the library half (Navidrome's search3, for the same words) playing Roads from that Dummy: the song held
  const heard = [{ id: 'nd-roads', title: 'Roads', artist: 'Portishead', album: 'Dummy', albumId: 'nd-dummy-94' }]
  check('...the library half\'s songs showing Roads by Portishead on an album named as that folder\'s: the row and Dummy\'s line say "in your library", that Navidrome album what opens - no bridge',
    [S.songLine(song, cd94, false, { heard }), S.songAlbumLine(dummy, song, cd94, false, { heard }), S.songAlbumHolding(cd94, dummy, song, { heard }).albums,
      S.songAlbumHolding(cd94, dummy, song, { heard }).heard.length, S.songAlbumHeldReleases(cd94, dummy, song, { heard })],
    ['Portishead · 4:56 · Dummy · in your library', 'Album · 1994 · in your library', ['nd-dummy-94'], 1, []])
  check('...case, accents and a leading "The" folded as names are',
    S.songAlbumHolding(cd94, dummy, song, { heard: [{ title: 'ROADS', artist: 'portishead', album: 'The DUMMY', albumId: 'nd-x' }] }).albums, ['nd-x'])
  const refused = (each) => S.songAlbumHolding(cd94, dummy, song, { heard: [{ ...heard[0], ...each }] }).albums
  check('...but never another song on it, the title by somebody else, the song on another album, or a song with no artist or no album id',
    [refused({ title: 'Sour Times' }), refused({ artist: 'Lorde' }), refused({ album: 'Roseland NYC Live' }), refused({ artist: undefined }), refused({ albumId: undefined }), S.songAlbumHolding(cd94, dummy, null, { heard }).albums],
    [[], [], [], [], [], []])
  check('...with logins on, the store\'s Dummy: "in the store"', S.songAlbumLine(dummy, song, buildOwnedIndex([{ path: 'a', album: 'Dummy', release_group_mbid: dummy.id, release_mbid: CD_1994, yours: false }]), true, { heard }),
    'Album · 1994 · in the store')
  //? ...or the album's pressings, kept for the session (its page opened before, a Get chip, or the tap's own look):
  //? the 1994 CD's tracklist has Roads, as another recording, known by its title
  const track = (recording, title = 'Roads') => ({ number: '8', position: 8, title, length: 302000, recording: { id: recording, title } })
  const dummyPressings = [
    { id: UK_CD, status: 'Official', date: '1994-08-22', country: 'GB', media: [{ format: 'CD', position: 1, tracks: [track('ef37de8d-8fab-42ed-82da-fbfe25715989')] }] },
    { id: CD_1994, status: 'Official', date: '1994-08-22', country: 'XE', media: [{ format: 'CD', position: 1, tracks: [track(ROADS_1994)] }] },
  ]
  const asked = []
  const pressings = (id) => { asked.push(id); return id === dummy.id ? dummyPressings : null }
  check('...or the album\'s pressings kept, the 1994 CD\'s tracklist with Roads as another recording: the song held - by its release, so the id bridge is asked about it',
    [S.songLine(song, cd94, false, { pressings }), S.songAlbumLine(dummy, song, cd94, false, { pressings }), S.songAlbumHeldReleases(cd94, dummy, song, { pressings }), asked.every((id) => id === dummy.id)],
    ['Portishead · 4:56 · Dummy · in your library', 'Album · 1994 · in your library', [CD_1994], true])
  const without = dummyPressings.map((each) => (each.id === CD_1994 ? { ...each, media: [{ format: 'CD', position: 1, tracks: [track('99999999-0000-0000-0000-000000000000', 'Numb')] }] } : each))
  check('...kept pressings whose 1994 CD hasn\'t Roads: still only "a pressing" - nothing claimed, nothing to ask the bridge',
    [S.songAlbumLine(dummy, song, cd94, false, { pressings: () => without }), S.songAlbumHeldReleases(cd94, dummy, song, { pressings: () => without })],
    ['Album · 1994 · a pressing in your library', []])
  check('...and none kept, or none for this album: the same', [S.songAlbumLine(dummy, song, cd94, false, { pressings: () => null }), S.songAlbumLine(dummy, song, cd94, false, { pressings: () => [] })],
    ['Album · 1994 · a pressing in your library', 'Album · 1994 · a pressing in your library'])
  const groupOnly = buildOwnedIndex([{ path: 'Portishead/Dummy', release_group_mbid: dummy.id }])
  check('...a folder with no release id at all can\'t be told apart: held by the group\'s id, as every screen holds it - nothing for the bridge to ask',
    [S.songLine(song, groupOnly), S.songAlbumHeldReleases(groupOnly, dummy)], ['Portishead · 4:56 · Dummy · in your library', []])
  const m4a = buildOwnedIndex([{ path: 'Portishead/Roseland NYC Live', artist: 'Portishead', album: 'Roseland NYC Live', release_mbid: roseland.releases[0] }])
  check('a folder with a release id alone (an .m4a deadwax filed) is held - and the row names THAT album, with its length there',
    [S.songAlbumHeld(m4a, roseland).length, S.songLine(song, m4a)], [1, 'Portishead · 5:30 · Roseland NYC Live · in your library'])
  check('nothing claimed without the library\'s answer', [S.songLine(song, null), S.songAlbumHeld(null, dummy)], ['Portishead · 4:56 · Dummy', []])
  const store = buildOwnedIndex([
    { path: 'Portishead/Dummy (1994)', release_group_mbid: dummy.id, release_mbid: UK_CD, yours: false },
    { path: 'Portishead/Roseland', release_mbid: roseland.releases[0], yours: true },
  ])
  check('logins on, a library of your own: the row names the album that is YOURS before one only the store has', S.songLine(song, store, true),
    'Portishead · 5:30 · Roseland NYC Live · in your library')
  check('...and one only the store has says "in the store" - with logins off, "in your library" (its length said: the row\'s is the live take\'s)',
    [S.songAlbumLine(dummy, song, store, true), S.songAlbumLine(dummy, song, store, false)], ['Album · 1994 · 4:56 · in the store', 'Album · 1994 · 4:56 · in your library'])
  const storeOnly = buildOwnedIndex([{ path: 'Portishead/Dummy (1994)', release_group_mbid: dummy.id, yours: false }])
  check('...a song held only by the store says so', S.songLine(song, storeOnly, true), 'Portishead · 4:56 · Dummy · in the store')
  //? (review) two albums only the store has: the row names the FIRST of them, as the albums are listed
  const twoStore = buildOwnedIndex([
    { path: 'Portishead/Dummy (1994)', release_group_mbid: dummy.id, release_mbid: UK_CD, yours: false },
    { path: 'Portishead/Roseland', release_mbid: roseland.releases[0], yours: false },
  ])
  check('...two only the store has: the first of them named (Dummy, listed before the live album)', S.songLine(song, twoStore, true), 'Portishead · 4:56 · Dummy · in the store')
}

console.log('\nwhat you have of it - a pressing without the song (review: the bonus-track case)')
{
  const [song] = S.groupSongs(patience.recordings)
  const rushAlbum = song.albums.find((each) => each.title === 'The Slow Rush')
  //? the dev library's own: The Slow Rush's usual (Australian) CD, 12 tracks, no Patience - tagged as deadwax files a FLAC
  const AU_CD = '1cf564b9-4e24-4362-89fb-1aa702ff60f2', JP_CD = '452ccdb4-d6f5-4ac2-9eea-3eb2df8e5bb6'
  check('Patience is on The Slow Rush by its Japanese CD alone', rushAlbum.releases, [JP_CD])
  const au = buildOwnedIndex([{ path: 'Tame Impala/The Slow Rush (2020)', artist: 'Tame Impala', album: 'The Slow Rush', release_group_mbid: rushAlbum.id, release_mbid: AU_CD, track_count: 12 }])
  check('the usual CD held: the row claims nothing - you haven\'t the song - The Slow Rush\'s line says "a pressing in your library", and nothing of yours opens',
    [S.songLine(song, au), S.songAlbumLine(rushAlbum, song, au), S.songAlbumHeldReleases(au, rushAlbum, song)],
    ['Tame Impala · 4:53 · The Slow Rush', 'Album · 2020 · a pressing in your library', []])
  check('...with logins on: "a pressing in the store" for the store\'s, "...in your library" for yours',
    [S.songAlbumLine(rushAlbum, song, buildOwnedIndex([{ path: 'a', release_group_mbid: rushAlbum.id, release_mbid: AU_CD, yours: false }]), true),
      S.songAlbumLine(rushAlbum, song, buildOwnedIndex([{ path: 'a', release_group_mbid: rushAlbum.id, release_mbid: AU_CD, yours: true }]), true)],
    ['Album · 2020 · a pressing in the store', 'Album · 2020 · a pressing in your library'])
  //? (second review) the evidence never makes a pressing without the song hold it: The Slow Rush's real pressings kept
  //? (the usual CD's tracklist hasn't Patience), and the library half showing another song of The Slow Rush
  check('...its real pressings kept - the usual CD without Patience - or the library half playing Borderline from it: still only "a pressing"',
    [S.songAlbumLine(rushAlbum, song, au, false, { pressings: (id) => (id === rushAlbum.id ? rush.releases : null) }),
      S.songAlbumLine(rushAlbum, song, au, false, { heard: [{ title: 'Borderline', artist: 'Tame Impala', album: 'The Slow Rush', albumId: 'nd-rush' }] })],
    ['Album · 2020 · a pressing in your library', 'Album · 2020 · a pressing in your library'])
  const both = buildOwnedIndex([
    { path: 'Tame Impala/The Slow Rush (2020)', release_group_mbid: rushAlbum.id, release_mbid: AU_CD },
    { path: 'Tame Impala/The Slow Rush (2020) [JP]', release_group_mbid: rushAlbum.id, release_mbid: JP_CD },
  ])
  check('the Japanese CD held too: the song is yours - the row and the line say so, and the bridge is asked about THAT CD alone',
    [S.songLine(song, both), S.songAlbumLine(rushAlbum, song, both), S.songAlbumHeldReleases(both, rushAlbum)],
    ['Tame Impala · 4:53 · The Slow Rush · in your library', 'Album · 2020 · in your library', [JP_CD]])
  const m4a = buildOwnedIndex([{ path: 'Tame Impala/The Slow Rush [JP]', release_mbid: JP_CD }])
  check('...held as an .m4a deadwax filed (a release id, no group id): the same', [S.songLine(song, m4a), S.songAlbumHeldReleases(m4a, rushAlbum)],
    ['Tame Impala · 4:53 · The Slow Rush · in your library', [JP_CD]])
}

console.log('\nthe address\'s song')
{
  const id = 'BBA0E134-26C5-4546-9CCA-5E0CCEA9CDFC'
  const many = Array.from({ length: 12 }, (_, n) => `0000000${n.toString(16)}-0000-0000-0000-000000000000`)
  check('lowercased, each once, only ids as MusicBrainz writes them, at most eight', [S.songIds(`${id},${id.toLowerCase()},nonsense,`), S.songIds(many).length, S.songIds(null), S.songIds('')],
    [['bba0e134-26c5-4546-9cca-5e0ccea9cdfc'], 8, [], []])
}

console.log('\nthe album opened from a song: a pressing with the song, the song marked')
{
  const [song] = S.groupSongs(patience.recordings)
  const album = song.albums.find((each) => each.title === 'The Slow Rush')
  check('Patience: The Slow Rush listed first, its single after, the rest folded - a compilation, two live broadcasts (Glastonbury, SNL) and a remix EP',
    [titles(S.songAlbumBands(song).listed), S.foldLabel(S.songAlbumBands(song).folded)],
    [['The Slow Rush', 'Patience'], 'On 4 compilations, broadcasts and other records'])
  const releases = rush.releases
  const usual = P.pressingsView(releases).defaultId
  const chosen = S.songPressing(releases, album.recordings)
  check('the usual pressing (the Australian CD) lacks it: the Japanese CD, which has it as a bonus track, is chosen', [usual.slice(0, 8), chosen && chosen.slice(0, 8)], ['1cf564b9', '452ccdb4'])
  const matches = S.songMatcher(releases, album.recordings)
  const jp = releases.find((release) => release.id === chosen)
  const view = P.pressingsView(releases, chosen)
  const rows = P.trackRows(jp, view.diffs.get(chosen), matches)
  check('...its Patience marked, and nothing else; still marked a Bonus track', [rows.filter((row) => row.song).map((row) => [row.number, row.title, row.mark && row.mark.chip])], [[['13', 'Patience', 'Bonus']]])
  check('...a pressing without it marks nothing; a page from no song marks nothing', [P.trackRows(releases.find((r) => r.id === usual), null, matches).some((row) => row.song), P.trackRows(jp, null).some((row) => row.song)], [false, false])
  const single = recordingIdOf('ebbf5e17')
  check('Borderline\'s single mix (another recording, only on one digital pressing): the usual pressing has Borderline, so it opens on that', S.songPressing(releases, [single]), null)
  check('...its Borderline marked by its title', P.trackRows(releases.find((r) => r.id === usual), null, S.songMatcher(releases, [single])).filter((row) => row.song).map((row) => row.title), ['Borderline'])
  check('the usual pressing\'s own track: no other pressing forced', S.songPressing(releases, [recordingIdOf('1274a2c2')]), null)
  //? (review) a track known by its RECORDING's title alone - the track itself titled otherwise ("Patience (bonus track)")
  const byRecordingTitle = matches({ title: 'Patience (bonus track)', recording: { id: '22222222-0000-0000-0000-000000000000', title: 'Patience' } })
  const songTitledOtherwise = [{ ...jp, media: jp.media.map((m) => ({ ...m, tracks: m.tracks.map((t) => (t.title === 'Patience' ? { ...t, title: 'Geduld' } : t)) })) }]
  check('...a track whose recording is titled as the song is the song; and the song\'s own recording title known though its track is titled otherwise',
    [byRecordingTitle, S.songMatcher(songTitledOtherwise, album.recordings)({ title: 'Patience', recording: { id: '33333333-0000-0000-0000-000000000000' } })], [true, true])
  check('no recording any pressing has: nothing to know the song by - the usual pressing, nothing marked', [S.songPressing(releases, ['00000000-0000-0000-0000-000000000000']), S.songMatcher(releases, ['00000000-0000-0000-0000-000000000000'])], [null, null])
  check('...and none asked: the same', [S.songPressing(releases, []), S.songMatcher(releases, [])], [null, null])
  //? several pressings with the bonus track: the most usual of them - an Official CD over a bootleg
  const extra = (id, status, format) => ({ ...jp, id, status, media: jp.media.map((m) => ({ ...m, format })) })
  const pool = [...releases.filter((r) => r.id !== chosen), extra('aaaaaaaa-0000-0000-0000-000000000000', 'Bootleg', 'CD'), extra('bbbbbbbb-0000-0000-0000-000000000000', 'Official', 'CD')]
  check('several pressings with it: the most usual of those (representativeRelease) - the Official CD, not the bootleg', S.songPressing(pool, album.recordings), 'bbbbbbbb-0000-0000-0000-000000000000')
  //? another recording of the song on no pressing, but a track of its title on one that isn't the usual pressing
  const retitled = releases.map((r) => (r.id !== chosen ? r : { ...r, media: r.media.map((m) => ({ ...m, tracks: m.tracks.map((t) => (t.title === 'Patience' ? { ...t, recording: { ...t.recording, id: '11111111-0000-0000-0000-000000000000' } } : t)) })) }))
  const withOther = [...retitled, { ...jp, id: 'cccccccc-0000-0000-0000-000000000000', status: 'Bootleg', media: jp.media.map((m) => ({ ...m, format: 'Cassette' })) }]
  check('pressings with the recording itself before those with only its title', S.songPressing(withOther, album.recordings), 'cccccccc-0000-0000-0000-000000000000')
}

if (failures) {
  console.log(`\n${failures} FAILED`)
  process.exit(1)
}
console.log('\nall passed')
