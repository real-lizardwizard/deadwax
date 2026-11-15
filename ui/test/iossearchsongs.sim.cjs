/**
 * The iPhone app's Search draws MusicBrainz's artists and songs, opens the album a song is on with the song marked, and
 * lists a MusicBrainz artist's albums as this app's Search and its artist page do (notes/ios.md, "Phase 5, slice 3").
 *
 * The phone's Swift port (ios/DeadwaxKit/Sources/DeadwaxCore/SongSearch.swift, MBArtist.swift, Collation.swift, and
 * slice 3's half of SearchList.swift, SearchState.swift and Pressings.swift) is held by SearchSongsVectorTests to
 * ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/search/search-songs-vectors.json, which
 * ios/scripts/export-search-songs-vectors.cjs writes from what this app's own TypeScript answers - lib/songs.ts
 * (songKey, groupSongs, songAlbumBands, foldLabel, the holding of a song's album, its line, songIds, songMatcher, songPressing),
 * lib/searchList.ts (the pool with MusicBrainz's artists and songs, newArtists, newSongs, Top results, every line),
 * lib/searchQuery.ts (songSearchQuery, songTitleQuery), lib/artistPage.ts (artistRows, rowLine, factsLine),
 * lib/pressings.ts (trackRows with the song) and localeCompare itself - and a few words read from Search.tsx,
 * ReleaseGroupPage.tsx and ArtistPage.tsx. This runs that script with --check: every vector made again from the
 * TypeScript as it is today and compared byte for byte with the committed file. So a web rule changed here fails here
 * until the vectors are written again - and then the phone's Swift tests fail until the change is ported.
 *
 * And ios/scripts/collation-tables.cjs with --check: Collation.swift's tables made again from this Node's ICU and
 * compared with what is there (slice 3's review) - when this Node's ICU is the one they were made with; another ICU's
 * would differ without being wrong, so then it says so and passes.
 *
 * Run it with:  TMPDIR=<writable> node ui/test/iossearchsongs.sim.cjs
 */

const { execFileSync } = require('child_process')
const path = require('path')

const REPO = path.resolve(__dirname, '..', '..')
const SCRIPTS = [
  ['export-search-songs-vectors.cjs', "Search's song and artist vectors are not what the web's TypeScript answers today"],
  ['collation-tables.cjs', "Collation.swift's tables are not what this Node's ICU answers"],
]

let failures = 0
for (const [script, failed] of SCRIPTS) {
  try {
    const said = execFileSync(process.execPath, [path.join(REPO, 'ios', 'scripts', script), '--check'], { cwd: REPO, encoding: 'utf8' })
    console.log(`  PASS  ${said.trim()}`)
  } catch (error) {
    failures++
    process.stdout.write(error.stdout || '')
    process.stderr.write(error.stderr || '')
    console.log(`  FAIL  ${failed} (exit ${error.status})`)
  }
}

console.log(failures ? `\n${failures} FAILED` : '\nall passed')
process.exit(failures ? 1 : 0)
