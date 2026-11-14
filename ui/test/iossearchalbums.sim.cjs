/**
 * The iPhone app's Search draws MusicBrainz's albums in their moments, says what is held, and draws the album you don't
 * have as this app's Search and its album page do (notes/ios.md, "Phase 5, slice 2").
 *
 * The phone's Swift port (ios/DeadwaxKit/Sources/DeadwaxCore/SearchAlbums.swift, Pressings.swift, MusicBrainz.swift,
 * and slice 2's half of SearchList.swift and SearchState.swift) is held by SearchAlbumsVectorTests to
 * ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/search/search-albums-vectors.json, which
 * ios/scripts/export-search-albums-vectors.cjs writes from what this app's own TypeScript answers - lib/searchList.ts
 * (the pool with MusicBrainz's albums, decidedTop, the moments, rowLine, the words), lib/searchQuery.ts (allAlbumsQuery,
 * typeFilter, musicBrainzOnTyping), lib/searchResults.ts (a group's year and kind, groupHeld, notInLibrary,
 * heldUnlisted, studioOrder), lib/pressings.ts and lib/tracklistDiff.ts (the album you don't have), lib/idBridge.ts and
 * lib/artistPage.ts (heldReleases, libraryArtistFor) - and a few numbers and words read from Search.tsx and
 * pressingLists.ts. This runs that script with --check: every vector made again from the TypeScript as it is today and
 * compared byte for byte with the committed file. So a web rule changed here fails here until the vectors are written
 * again - and then the phone's Swift tests fail until the change is ported.
 *
 * Run it with:  TMPDIR=<writable> node ui/test/iossearchalbums.sim.cjs
 */

const { execFileSync } = require('child_process')
const path = require('path')

const REPO = path.resolve(__dirname, '..', '..')
const SCRIPT = path.join(REPO, 'ios', 'scripts', 'export-search-albums-vectors.cjs')

let failures = 0
try {
  const said = execFileSync(process.execPath, [SCRIPT, '--check'], { cwd: REPO, encoding: 'utf8' })
  console.log(`  PASS  ${said.trim()}`)
} catch (error) {
  failures++
  process.stdout.write(error.stdout || '')
  process.stderr.write(error.stderr || '')
  console.log(`  FAIL  Search's album vectors are not what the web's TypeScript answers today (exit ${error.status})`)
}

console.log(failures ? `\n${failures} FAILED` : '\nall passed')
process.exit(failures ? 1 : 0)
