/**
 * One vocabulary for your library, Home and the Library (2.0.5, UX batch 2) - a scan of the words a listener reads -
 * and for Search, the album you don't have, Sources and Requests (2.0.6, UX batch 3).
 *
 * James (2026-10-23) decided the shared music on the server is "All music" as a heading and "the collection" in a
 * sentence - never "the store", "Browse", "Navidrome" or "everything" - and that a person's own library is said as
 * what they see ("Added to your library", "waiting to be added"), never in starring mechanics. This script reads the
 * source of every file the batch owns, keeps only what a listener can read - string literals that are words (not class
 * names, ids, routes or scopes) and JSX text, comments taken out - and checks:
 *
 *  - in the batch's own files (BATCH): no "store", no "Browse", no "Navidrome", no "star"/"starred"/"starring",
 *    no "Subsonic", no "Put away", no "Request it again", no "the admin", no "First seen", no "Other pressings", no "everything";
 *  - in EVERY file of the app (app/, lib/, player/, hooks/, components/): no "the store" or "in the store" - the
 *    rename was the whole app's, and a new line saying it would undo it;
 *  - (2.0.6) in batch 3's files (BATCH3): James's "source" for where a download comes from - never "peer", "folder",
 *    "Soulseek" or "slskd"; "added to your library", never "filed" or "organizing"; "pressing", never "editions" or
 *    "release id"; albums you don't have, never "MusicBrainz" (but its own ↗ links); no "saved" mark; "Searching…" and
 *    "Loading…", never "Asking…"; "Getting…", never "Get…"; and none of the old Sources and Requests words - Signals,
 *    Titles, Lengths, Free slot, their own average, Re-search, "#3 in", Next peer, Ask again, "3 ahead", and Navidrome's
 *    name ("try 2" is a template's "try " the scanner can't tell from code - requests.sim pins "2nd try"). A line left on
 *    purpose is in ALLOW3, with why.
 *  - (2.0.7) in batch 4's files (BATCH4): Info's About, Now Playing, the mini player, the turntable and the visualizer
 *    say none of Debug's or the engine's words to a listener - no LUFS, "levelled", numpy or soundfile, STREAMINFO or
 *    MiB, "in one stream", "deadwax hasn't said", Navidrome; no "can't be seen" or WebGL; "Up Next", never "Up next"; no
 *    "Open now playing"; no "couldn't be decoded". Debug's own words live in lib/debugRows.ts and lib/loudness.ts, an
 *    admin's, which are not in BATCH4. And (after review) the readout's old labels "now:" and "feel:" and a lowercase
 *    "bpm" in ANY of those files' text (BATCH4_LABELS: short labels and template tails the words-only scan drops as
 *    code), and the playback error words pinned in usePlayer.ts and as troubleshooting.md quotes them.
 *
 *  - (2.0.8) in batch 5's files (BATCH5): the managing pages, the Edit album panel and its editors, People, You and the
 *    sidebar say "Select" (never "Tick"), "Marked fine" / "Ask about it again" (never "Ignored", "un-ignore", "Accepted as
 *    it is"), "Manage" (never "Managing"), "In nobody's library", "Needs a look" (never "Albums that need a look" or "the
 *    queue"), the Release tab (never "the metadata editor"), "Server settings" (never "deadwax's settings"); no "(s)", no
 *    "could not", no "currently:", no "No release id" or "off-convention", no WireGuard or Amperfy, no "Stop ·" whose
 *    meaning was only its title, no "Retry cover"; and none of the lower-case starts it put right (BATCH5_LOWER).
 *
 * Each rule is checked on a sample that breaks it, so a scan that finds nothing is known to look.
 *
 * Run it with:  node ui/test/vocabulary.sim.cjs
 */

const fs = require('fs'), path = require('path')

const SRC = path.resolve(__dirname, '..', 'src')

let failures = 0
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` + (ok ? '' : `  (expected ${JSON.stringify(expected)})`))
}

/**
 * The source read once, as a tokenizer would: its comments blanked (`code`), and every string literal's own text
 * (`strings`: [offset, text]) - a template's literal parts, with a space where each `${...}` was, and the strings
 * inside those expressions read too (a template nested in a template's expression - `${a ? `x` : 'y'}` - is
 * followed, never taken for the outer one's end).
 */
function tokens(src) {
  let code = '', i = 0
  const strings = []
  //? what we are inside: 'code' (with the brace depth an expression of a template started at), or a template
  const stack = [{ kind: 'code', depth: 0 }]
  let depth = 0
  const top = () => stack[stack.length - 1]
  while (i < src.length) {
    const c = src[i]
    if (top().kind === 'template') {
      const part = top()
      if (c === '\\') { part.text += src.slice(i, i + 2); code += src.slice(i, i + 2); i += 2; continue }
      if (c === '`') { stack.pop(); strings.push([part.at, part.text]); code += c; i++; continue }
      if (src.startsWith('${', i)) { part.text += ' '; stack.push({ kind: 'code', depth }); depth++; code += '${'; i += 2; continue }
      part.text += c; code += c; i++; continue
    }
    if (src.startsWith('//', i)) { const j = src.indexOf('\n', i); const end = j < 0 ? src.length : j; code += ' '.repeat(end - i); i = end; continue }
    if (src.startsWith('/*', i)) { const j = src.indexOf('*/', i + 2); const end = j < 0 ? src.length : j + 2; code += src.slice(i, end).replace(/[^\n]/g, ' '); i = end; continue }
    if (c === '"' || c === "'") {
      let j = i + 1, text = ''
      while (j < src.length && src[j] !== c && src[j] !== '\n') { if (src[j] === '\\') { text += src.slice(j, j + 2); j += 2 } else text += src[j++] }
      strings.push([i, text]); code += src.slice(i, j + 1); i = j + 1; continue
    }
    if (c === '`') { stack.push({ kind: 'template', at: i, text: '' }); code += c; i++; continue }
    //? a regex literal (a "/" where a value starts - after an operator, a bracket, a comma or `return`): skipped
    //? whole, so a quote or backtick in it - /[’‘`´]/ - never opens a string
    //? (2.0.8 review) never a self-closing tag's "/>" after an attribute's expression (`<Loading label={x} />`): taken
    //? for a regex, it swallowed the rest of the line - Get cover's 'Try again' : 'Get cover' went unread
    if (c === '/' && !(src[i + 1] === '>' && /\}\s*$/.test(code.slice(-40))) && /(?:^|[(,=:[!&|?{};+\-*%<>~^]|\breturn)\s*$/.test(code.slice(-40))) {
      let j = i + 1, inClass = false
      while (j < src.length && src[j] !== '\n') {
        if (src[j] === '\\') { j += 2; continue }
        if (src[j] === '[') inClass = true
        else if (src[j] === ']') inClass = false
        else if (src[j] === '/' && !inClass) break
        j++
      }
      code += src.slice(i, j + 1); i = j + 1; continue
    }
    if (c === '{') depth++
    if (c === '}') {
      depth--
      if (stack.length > 1 && top().kind === 'code' && depth === top().depth) { stack.pop(); code += c; i++; continue }
    }
    code += c; i++
  }
  return { code, strings }
}

/** Whether a string is words a person reads - not a class list, an id, a route, a scope or an import. */
function wordy(text) {
  const s = text.trim()
  if (s.length < 3 || !/[A-Za-z]{2,}/.test(s)) return false
  if (/^(\.{1,2}\/|\/|#|@|http)/.test(s) && !s.includes(' ')) return false
  if (/^[\w\-.:/]+$/.test(s) && !/^[A-Z]/.test(s)) return false
  if (/^[a-z0-9\- ]+$/.test(s) && s.includes('-')) return false
  if (/^(app|pl)-[\w-]+/.test(s) && !/[A-Z]/.test(s)) return false
  return true
}

/**
 * Every piece of text in a file a listener could read: [line, words]. With `all`, every piece of text whether or not it
 * looks like words - a short label ("feel:" before an expression) or a template's tail (" bpm" after `${...}`) that
 * wordy() takes for code - for the batch 4 rules that look for exactly those (BATCH4_LABELS).
 */
function readable(src, all = false) {
  const { code, strings } = tokens(src)
  const lineOf = (at) => code.slice(0, at).split('\n').length
  const found = []
  for (const [at, text] of strings) {
    const before = code.slice(Math.max(0, at - 14), at)
    if (/\b(?:import|from)\s*$/.test(before) || /\bclass(?:Name)?=\{?`?$/.test(before)) continue
    if (all ? text.trim() : wordy(text)) found.push([lineOf(at), text])
  }
  //? JSX text: between a tag's end (or an expression's) and the next tag or expression
  const jsx = /(?<=[>}])([^<>{}]*[A-Za-z][^<>{}]*)(?=[<{])/g
  for (let m; (m = jsx.exec(code));) {
    const text = m[1].replace(/\s+/g, ' ').trim()
    //? code that happens to sit between a ">" and a "<" (a comparison, an arrow) is not text; words in brackets are
    if (!(all ? text : wordy(text)) || /=>|&&|\|\||[=!]==|[;=[\]]|\?\s|\(\)/.test(text)) continue
    if (/^(else|return|catch|as |while|from|function|const|let|if |case |default)/.test(text)) continue
    //? (2.0.6) code that sits between a ">" and a "{" too: a type annotation, a loop's head, a spread
    if (/\bvoid\b|\(const |\.\.\.\(|^\||^[\w.]+\.\w+\($/.test(text)) continue
    found.push([lineOf(m.index + 1), text])
  }
  return found
}

const BATCH = [
  'app/Home.tsx', 'app/LibraryHome.tsx', 'app/LibrarySection.tsx', 'app/LibraryViews.tsx', 'app/Pinned.tsx', 'app/PinToggle.tsx',
  'app/YourLibrary.tsx', 'app/AlbumProperties.tsx', 'app/ArtistPage.tsx', 'app/PressingPicker.tsx', 'app/Sidebar.tsx',
  'lib/pins.ts', 'lib/artistPage.ts', 'lib/whose.ts', 'lib/myLibrary.ts', 'lib/yourLibrary.ts', 'lib/appFrame.ts',
  'lib/albumProperties.ts', 'lib/idBridge.ts', 'lib/upNext.ts', 'player/AlbumPage.tsx', 'player/PlayerBar.tsx',
  //? (2.0.5 review) Library care's Held by nobody: its Put away became Dismiss in this batch too
  'app/HeldByNobody.tsx',
  //? (2.0.13) the artist's and the album's description - its clamp's words and its source's
  'app/Description.tsx', 'lib/describe.ts', 'app/useDescription.ts',
]

/** The words the batch's files never say to a listener - each with a sample that says it. */
const BATCH_RULES = [
  ['"store"', /\bstore\b/i, 'Removed from the store'],
  ['"Browse" as a label', /\bBrowse\b/, 'Browse the store'],
  ['"Navidrome"', /Navidrome/, 'Not in Navidrome yet'],
  ['starring', /\bstar(?:s|red|ring)?\b/i, 'Waiting for its turn to be starred.'],
  ['"Subsonic"', /Subsonic/, 'star it in a Subsonic app'],
  ['"Put away"', /\bput(?:ting)? away\b/i, 'Put away'],
  ['"Request it again"', /request it again/i, 'Request it again'],
  ['"the admin"', /\bthe admin\b/i, 'Removed by the admin'],
  ['"First seen"', /First seen/, 'First seen'],
  ['"Other pressings"', /Other pressings/, 'Other pressings'],
  ['"everything" for the collection', /\beverything\b/i, 'Then everything again, in a new order.'],
]

/** ...and the whole app never says "the store" (2.0.5: "the collection"). */
const APP_RULE = ['"the store"', /\b(?:the|in the|from the) store\b/i, 'Searching the store…']

/** (2.0.6, UX batch 3) Search, the album you don't have, Sources and Requests - and the artist page's MusicBrainz words
 *  and "2 editions", which batch 2 left to this one. */
const BATCH3 = [
  'app/Search.tsx', 'app/SearchRows.tsx', 'lib/searchList.ts', 'lib/searchResults.ts', 'lib/songs.ts',
  'app/ReleaseGroupPage.tsx', 'lib/pressings.ts', 'app/PressingPicker.tsx', 'lib/owned.ts',
  'app/Sources.tsx', 'app/SourceCard.tsx', 'lib/candidates.ts', 'lib/getSettings.ts', 'app/StoreState.tsx', 'hooks/useCandidateSearch.ts',
  'app/Requests.tsx', 'app/JobCard.tsx', 'lib/requestsView.ts', 'lib/perPerson.ts', 'hooks/useDownloadJobs.ts', 'app/Arriving.tsx', 'lib/myLibrary.ts',
  'lib/artistPage.ts', 'app/ArtistPage.tsx',
]

/** The words batch 3's files never say to a listener - each with a sample that says it. */
const BATCH3_RULES = [
  ['"MusicBrainz"', /MusicBrainz/, 'Asking MusicBrainz…'],
  ['"Soulseek"', /Soulseek/, '41 folders on Soulseek, none pass your filters'],
  ['"slskd"', /slskd/, 'slskd listens for answers for a few seconds.'],
  ['"peer"', /\bpeers?\b/i, 'Trying next peer…'],
  ['"folder" for a source', /\bfolders?\b/i, '2 disc folders'],
  ['"filed" / "filing"', /\bfil(?:ed|ing)\b/i, 'Partly filed: 2 file(s) failed to organize'],
  ['"organizing"', /organi[sz]/i, '12 of 12 files · organizing'],
  ['"release id"', /release id/i, 'its folder has no MusicBrainz release id'],
  ['"editions"', /\beditions\b/i, '1994 · in your library · 2 editions'],
  ['the "saved" mark', /\bsaved\b/i, 'Saved - MusicBrainz is away.'],
  ['"Asking…"', /\bAsking\b/, 'Asking the collection…'],
  ['the code\'s signal names', /\b(?:Signals|Titles|Lengths)\b/, 'Signals · 2'],
  ['"Free slot"', /\bFree slot\b/, 'Free slot'],
  ['"their own average"', /own average/, 'their own average'],
  ['"Re-search"', /Re-search/, 'Re-search'],
  ['"#3 in"', /#\s*in\b/, '#3 in their queue'.replace('3', ' ')],
  ['"Next peer" / "Ask again"', /Next peer|\bAsk(?:ing)? again\b/, 'Next peer · 3 left'],
  ['"Get…"', /\bGet…/, 'Get…'],
  ['"ahead"', /\bahead\b/, '3 ahead'],
  ['"Navidrome"', /Navidrome/, "Navidrome hasn't found it yet - it may still be scanning"],
]

/** Lines batch 3's rules leave on purpose: [file, the line's words, why]. */
const ALLOW3 = [
  ['app/ReleaseGroupPage.tsx', /^On MusicBrainz$/, 'the label over its own links to musicbrainz.org - the one place the name stays (the review\'s X2)'],
  ['lib/owned.ts', /^A folder with this name, not matched to a pressing/, "the maybe's tooltip, drawn only for whoever can Edit albums - its folders' paths; anyone reads the line under Get"],
  ['lib/candidates.ts', /^(?:those folders|that folder|Getting it adds only the tracks that folder doesn't have yet\.)$/, "a library folder, named by its path beside it (the store box's notes) - not a source"],
  ['app/Requests.tsx', /Downloads still arrive in slskd/, 'the database line for whoever runs deadwax only (it names DB_PATH); anyone else reads UNTRACKED_TEXT'],
  ['app/ArtistPage.tsx', /^Folders?$/, "the artist's facts' folder paths - the review's AR7, flagged beyond the batches (B6)"],
  ['lib/myLibrary.ts', /^its folder$/, "Held by nobody's flag line, a managing page's (batch 5)"],
]

/** (2.0.7, UX batch 4) Info's About, Now Playing, the mini player, the turntable and the visualizer - and the engine's
 *  playback error words (usePlayer.ts: its strings only, the one engine file this batch may change). */
const BATCH4 = [
  'lib/aboutRows.ts', 'lib/aboutSound.ts', 'app/InfoSheet.tsx', 'lib/idBridge.ts', 'player/MiniPlayer.tsx', 'player/NowPlaying.tsx', 'lib/upNext.ts',
  'app/UpNext.tsx', 'player/PlayerBar.tsx', 'lib/turntable.ts', 'player/Turntable.tsx', 'lib/vizSync.ts', 'player/Visualizer.tsx', 'lib/visualizer.ts',
  'lib/musicFeel.ts', 'player/usePlayer.ts',
]

/** The words batch 4's files never say to a listener - each with a sample that says it. */
const BATCH4_RULES = [
  ['"LUFS"', /\bLUFS\b/, 'Album, -3.56 dB · the album at -14.4 LUFS'],
  ['"levelled"', /\blevell?ed\b/i, 'Not levelled - MP3 songs play as they are'],
  ['numpy and soundfile', /numpy|soundfile/, 'deadwax is running without numpy and soundfile'],
  ['STREAMINFO and MiB', /STREAMINFO|\bMiB\b/, "its STREAMINFO doesn't say how long it is"],
  ['"in one stream"', /in one stream/i, 'On, in one stream'],
  ['"hasn\'t said"', /hasn't said/, "Asked for; deadwax hasn't said yet"],
  ['"Navidrome"', /Navidrome/, "Couldn't play this song - Navidrome didn't send audio this device can play"],
  ['"can\'t be seen"', /can't be seen/, "This song can't be seen - it isn't a FLAC file."],
  ['"WebGL"', /WebGL/, "WebGL isn't available here, so Ambient is showing the simple version."],
  ['"Up next"', /\bUp next\b/, 'Up next - Shuffle on'],
  ['"Open now playing"', /Open now playing/i, 'Open now playing'],
  ['"couldn\'t be decoded"', /couldn't be decoded/, "This song's file couldn't be decoded"],
]

/**
 * (after review) The readout's old labels, looked for in EVERY piece of text (readable's `all`): JSX text before an
 * expression is read alone - "now:" of <span>now: {STYLE_NAMES[...]}</span> - and a template's " bpm" after `${...}`,
 * both of which wordy() drops as code, so a rule over readable()'s words could never see them. Each sample is shaped
 * like the code that said it, and shown missed by the words-only scan, so the rule is known to need `all`.
 */
const BATCH4_LABELS = [
  ['the feel readout\'s "now:" label', /^now:$/, 'const v = <span>now: {STYLE_NAMES[nowStyle]}</span>'],
  ['the feel readout\'s "feel:" label', /^feel:$/, 'const v = <span>feel: {feelText}</span>'],
  ['a lowercase "bpm"', /\bbpm\b/, 'const t = `${Math.round(F.bpm)} bpm`'],
]

/**
 * (after review) The playback error words a listener reads (usePlayer.ts's describeMediaError and skipNotice, the one
 * engine file this batch changes - its strings only), pinned here rather than in player.sim (an engine file), as the
 * source says them and as docs/troubleshooting.md quotes them, so a rewording that misses the docs fails.
 */
const PLAYBACK_WORDS = [
  ["This device couldn't play this song's audio", "This device couldn't play this song's audio"],
  ["Couldn't play this song - it didn't come as audio this device can play", "Couldn't play this song - it didn't come as audio this device can play"],
  ['Skipped "${title}" - this device couldn\'t play its audio', 'Skipped "…" - this device couldn\'t play its audio'],
]

/** (2.0.8, UX batch 5) Managing in plain words: Edit album and its editors, Needs a look, Library care, In nobody's library,
 *  People, Server settings, the event log, You's structure and the sidebar's Manage group. */
const BATCH5 = [
  'app/NeedsALook.tsx', 'lib/needsLook.ts', 'lib/metadataQueue.ts', 'app/LibraryCare.tsx', 'app/useLibraryCare.ts', 'lib/libraryCare.ts',
  'lib/bulkTargets.ts', 'app/HeldByNobody.tsx', 'app/People.tsx', 'app/usePeople.ts', 'app/AddPerson.tsx', 'app/RemovePerson.tsx',
  'app/ResetPassword.tsx', 'app/UnlockPeople.tsx', 'lib/people.ts', 'lib/permissions.ts', 'app/You.tsx', 'app/SignOutRow.tsx',
  'app/EventLog.tsx', 'lib/eventLog.ts', 'app/ServerSettings.tsx', 'lib/serverSettings.ts', 'app/EditPanel.tsx', 'lib/albumEdit.ts',
  'app/FolderPicker.tsx', 'app/TrackInspector.tsx', 'hooks/useTrackDetails.ts', 'components/MetadataEditor.tsx', 'components/TrackTagEditor.tsx',
  'components/LibraryParts.tsx', 'components/DeleteAlbumDialog.tsx', 'components/RetimeLyrics.tsx', 'components/MusicBrainzAnswers.tsx',
  'lib/getResults.ts', 'lib/lyrics.ts', 'app/ArtistPanel.tsx', 'app/Sidebar.tsx', 'lib/appFrame.ts', 'lib/appRoutes.ts',
]

/** The words batch 5's files never say - each with a sample that says it. */
const BATCH5_RULES = [
  ['"(s)" for a count', /\w\(s\)/, '12 of 14 file(s) would change'],
  ['"Tick" for choosing', /\b(?:un)?tick(?:s|ed|ing)?\b/i, 'Tick tracks to edit only those; Shift ticks a run.'],
  ['"Ignored" and its kin, for "Marked fine"', /\bIgnor(?:ed|ing)\b|\bun-ignore\b|Accepted as it is/i, 'Accepted as it is: no release'],
  ['"Managing" for the admin area', /\bManaging\b/, "The lyrics lead are in Managing's Settings, under Library."],
  ['"the metadata editor"', /metadata editor/i, 'No file is renamed - the metadata editor re-files an album once its tags say where it belongs.'],
  ['"could not"', /\bcould not\b/i, 'could not load that release'],
  ['"Held by nobody"', /Held by nobody/i, 'Held by nobody'],
  ['WireGuard and Amperfy', /WireGuard|Amperfy/, "That's fine on your own network or over WireGuard"],
  ['the plumbing chips', /No release id|off-convention/i, 'Folder off-convention'],
  ['"the queue" for Needs a look', /\bthe queue\b/i, 'Put this album back in the queue'],
  ['"deadwax\'s settings" for Server settings', /deadwax's settings/, "set it up in deadwax's settings (Connections)."],
  ['"Asking…"', /\bAsking\b/, 'Asking deadwax…'],
  ['"Stop ·" with what it does only in a title', /\bStop · /, 'Stop · 3 of 40'],
  ['the Archive by a nickname', /\bthe Archive\b/, '2 had none on the Archive'],
  ['"Logins are off" as a headline', /Logins are off/, 'Logins are off'],
  ['"Albums that need a look"', /Albums that need a look/i, 'Albums that need a look'],
  ['"People was made for"', /People was made for/, 'People was made for Navidrome 0.64 - this is 0.65.0.'],
  ['a Get button\'s old words', /\bRetry (?:cover|lyrics|CD art)\b|No CD art found/, 'Retry cover'],
  ['"break-glass" said to a person', /break-glass/i, 'with the break-glass password - it lasts 12 hours.'],
  //? (2.0.8 review) the Release tab's lines the first pass missed: "tagged with" right under "Matched to MusicBrainz"
  ['"tagged with" a release, for "matched to"', /\b(?:is|was) tagged with\b/i, 'This album is tagged with this release'],
  ['a sentence without its full stop', /^No releases found for that search$/, 'No releases found for that search'],
]

/** (2.0.8) Short labels the words-only scan drops as code (readable's `all`, as BATCH4_LABELS): the editor's old
 *  "currently:" over its line, the sidebar's and page's bare "Log", and the editor's "un-ignore" - each sample shaped
 *  like the code that said it. */
const BATCH5_LABELS = [
  ['editor\'s "currently:" line', /^currently:$/i, 'const v = <span>currently:</span>'],
  ['a bare "Log" for the Event log', /^Log$/, "const SIDEBAR_LOG = { id: 'log', label: 'Log' }"],
  //? (after a mutation slipped past) a lower-case hyphenated word reads as a class name to the words-only scan
  ['old undo "un-ignore"', /\bun-ignore\b/i, 'const v = <button class="metadata-issue-undo">un-ignore</button>'],
  //? (2.0.8 review) a release row's "11 trk", and the tag editor's lower-case "undo" - both too short for the words scan
  ['"trk" for tracks', /\btrk\b/, "const v = <span>{tracks || '?'} trk</span>"],
  ['a lower-case "undo"', /^undo$/, 'const v = <button class="tags-revert">undo</button>'],
]

/** ...and the lower-case starts batch 5 put right, as they started (case matters: the sentence's own first words). */
const BATCH5_LOWER = /^(?:could not|the search failed|replace cover only|save cover only|download cover art|working out the changes|fetching the tracklist|delete permanently|re-timing|reading the library|skip ▷|fetched |saved lyrics for|stop asking about|no edition|no year|not tagged with|none on file|pick a release|search to match|the release this album)/

/** Lines batch 5's rules leave on purpose: [file, the line's words, why]. */
const ALLOW5 = []

function filesUnder(dir) {
  return fs.readdirSync(path.join(SRC, dir)).filter((name) => /\.tsx?$/.test(name)).map((name) => `${dir}/${name}`)
}

console.log('\nthe scanner sees what a listener reads, and only that')
{
  const sample = `
    import { x } from './store'
    // the store, in a comment
    /* Navidrome in a block comment */
    const a = 'app-store-line is-store'
    const b = "Removed from the store"
    const c = \`\${n} albums in the store\`
    const d = <p class="pl-notice">Browse the store</p>
    const h = <p>Your favourite (starred) albums.</p>
    const e = scope === 'store'
    const f = name.replace(/[’‘\`´]/g, "'")
    const g = 'Then the end'
  `
  const words = readable(sample).map(([, text]) => text.trim())
  //? (2.0.8 review) a string after a self-closing tag with an attribute's expression, inside an expression - Get cover's
  check('the strings after "<Loading label={x} />" in an expression are read',
    readable("{state === 'working' ? <Loading label={GETTING.cover} /> : state === 'failed' ? 'Retry cover' : 'Get cover'}").map(([, text]) => text),
    ['Retry cover', 'Get cover'])
  check("a string, a template and JSX text are read; comments, imports, classes, scopes and a regex's quotes are not",
    words, ['Removed from the store', 'albums in the store', 'Then the end', 'Browse the store', 'Your favourite (starred) albums.'])
  for (const [name, rule, said] of [...BATCH_RULES, APP_RULE, ...BATCH3_RULES, ...BATCH4_RULES, ...BATCH5_RULES]) {
    check(`the ${name} rule catches "${said}"`, readable(`const x = ${JSON.stringify(said)}`).some(([, text]) => rule.test(text)), true)
  }
  for (const [name, rule, said] of BATCH5_LABELS) {
    check(`the ${name} rule catches ${said} - in every piece of text`, readable(said, true).some(([, text]) => rule.test(text.trim())), true)
  }
  check('the batch 5 lower-case rule catches "could not load that release" - and not "Couldn\'t load that release."',
    [readable('const x = "could not load that release"').some(([, text]) => BATCH5_LOWER.test(text.trim())), BATCH5_LOWER.test("Couldn't load that release.")], [true, false])
  for (const [name, rule, said] of BATCH4_LABELS) {
    check(`the ${name} rule catches ${said} - in every piece of text, which the words alone miss`,
      [readable(said, true).some(([, text]) => rule.test(text.trim())), readable(said).some(([, text]) => rule.test(text.trim()))], [true, false])
  }
}

console.log('\nthe batch\'s files: your library, Home, the Library, the album and artist pages, pins, You > Your library')
for (const file of BATCH) {
  const found = readable(fs.readFileSync(path.join(SRC, file), 'utf8'))
  const broken = []
  for (const [line, text] of found) for (const [name, rule] of BATCH_RULES) if (rule.test(text)) broken.push(`${file}:${line} ${name}: ${text.trim().slice(0, 120)}`)
  check(`${file}: none of the old words a listener reads (${found.length} lines read)`, broken, [])
}

console.log('\nbatch 3\'s files (2.0.6): Search, the album you don\'t have, Sources, Requests - source, added, pressing, and no plumbing')
{
  const allowed = new Set()
  for (const file of BATCH3) {
    const found = readable(fs.readFileSync(path.join(SRC, file), 'utf8'))
    const broken = []
    for (const [line, text] of found) {
      for (const [name, rule] of BATCH3_RULES) {
        if (!rule.test(text)) continue
        const allow = ALLOW3.find(([where, words]) => where === file && words.test(text.trim()))
        if (allow) allowed.add(allow)
        else broken.push(`${file}:${line} ${name}: ${text.trim().slice(0, 120)}`)
      }
    }
    check(`${file}: none of batch 3's old words a listener reads (${found.length} lines read)`, broken, [])
  }
  //? an allowance nothing needs any more is a hole a new line could slip through: each must still be used
  check('every line left on purpose is still there - none of ALLOW3 stale', ALLOW3.filter((allow) => !allowed.has(allow)).map(([file, words]) => `${file} ${words}`), [])
}

console.log('\nbatch 4\'s files (2.0.7): Info\'s About, Now Playing, the turntable and the visualizer - a listener\'s words, Debug\'s numbers left to Debug')
for (const file of BATCH4) {
  const found = readable(fs.readFileSync(path.join(SRC, file), 'utf8'))
  const broken = []
  for (const [line, text] of found) for (const [name, rule] of BATCH4_RULES) if (rule.test(text)) broken.push(`${file}:${line} ${name}: ${text.trim().slice(0, 120)}`)
  check(`${file}: none of batch 4's old words a listener reads (${found.length} lines read)`, broken, [])
  const labels = []
  for (const [line, text] of readable(fs.readFileSync(path.join(SRC, file), 'utf8'), true)) {
    for (const [name, rule] of BATCH4_LABELS) if (rule.test(text.trim())) labels.push(`${file}:${line} ${name}: ${text.trim().slice(0, 120)}`)
  }
  check(`${file}: none of the readout's old labels in any of its text`, labels, [])
}
{
  const player = fs.readFileSync(path.join(SRC, 'player/usePlayer.ts'), 'utf8')
  const guide = fs.readFileSync(path.join(SRC, '..', '..', 'docs/troubleshooting.md'), 'utf8').replace(/\s+/g, ' ')
  check('the playback error words: each in usePlayer.ts as a listener reads it, and quoted so in troubleshooting.md',
    PLAYBACK_WORDS.map(([source, quoted]) => [player.includes(source), guide.includes(quoted)]), PLAYBACK_WORDS.map(() => [true, true]))
}

console.log('\nbatch 5\'s files (2.0.8): managing in plain words - Select, Marked fine, Manage, sentences, no plumbing')
for (const file of BATCH5) {
  const source = fs.readFileSync(path.join(SRC, file), 'utf8')
  //? a declaration the JSX-text scan takes for words (`interface Managing`, `function checkboxes(… ticked: …`) is code
  const found = readable(source).filter(([, text]) => !/^(?:export\s+)?(?:interface|function|type|const|let)\b/.test(text.trim()))
  const broken = []
  for (const [line, text] of found) {
    for (const [name, rule] of BATCH5_RULES) if (rule.test(text)) broken.push(`${file}:${line} ${name}: ${text.trim().slice(0, 120)}`)
    if (BATCH5_LOWER.test(text.trim())) broken.push(`${file}:${line} a lower-case start: ${text.trim().slice(0, 120)}`)
  }
  for (const [line, text] of readable(source, true)) {
    for (const [name, rule] of BATCH5_LABELS) if (rule.test(text.trim())) broken.push(`${file}:${line} ${name}: ${text.trim().slice(0, 120)}`)
  }
  check(`${file}: none of batch 5's old words (${found.length} lines read)`, broken, [])
}
check('every line left on purpose is still there - ALLOW5 has none', ALLOW5, [])

console.log('\nthe whole app: "the collection", never "the store"')
{
  const files = ['app', 'lib', 'player', 'hooks', 'components'].flatMap(filesUnder)
  const broken = []
  for (const file of files) {
    for (const [line, text] of readable(fs.readFileSync(path.join(SRC, file), 'utf8'))) if (APP_RULE[1].test(text)) broken.push(`${file}:${line} ${text.trim().slice(0, 120)}`)
  }
  check(`no file of ${files.length} says "the store" to anyone`, broken, [])
}

console.log('\nthe guide (2.0.8): the way to a managing page goes through You → Manage, its rows by their names now')
{
  //? (review) You's managing rows sit under Manage, Change password under Account, and the sidebar says Server settings
  //? and Event log: a path written the old way sends a phone's reader looking for a row that isn't where it says
  const OLD_PATHS = [
    ['a managing row straight under You', /You →(?: \*\*)? ?(?:Server settings|Library care|Event log|Log\b|Needs a look|People|In nobody's library)/],
    ['Change password straight under You', /You →(?: \*\*)? ?Change password/],
    ["the sidebar's old Settings or Log", /sidebar's (?:\*\*)?(?:Settings|Log)\b/],
    ['"Settings" for the Server settings page in a step', /Fill in Settings →/],
  ]
  const docs = path.join(SRC, '..', '..', 'docs')
  const guides = [...fs.readdirSync(docs).filter((name) => name.endsWith('.md')).map((name) => path.join(docs, name)), path.join(docs, '..', 'README.md')]
  const broken = []
  for (const file of guides) {
    //? a path wraps across lines in the guide: read it as one line
    const words = fs.readFileSync(file, 'utf8').replace(/\s+/g, ' ')
    for (const [name, rule] of OLD_PATHS) {
      const at = words.match(new RegExp(rule.source, 'g'))
      if (at) broken.push(`${path.basename(file)} ${name}: ${at.join(' | ')}`)
    }
  }
  const samples = ['or **You → Library care**)', 'with **You → Change password**', "the desktop sidebar's Settings, or", '**Fill in Settings → Connections**']
  check('the guide scan knows each old way, and passes the new', [OLD_PATHS.map(([, rule], at) => rule.test(samples[at])),
    OLD_PATHS.some(([, rule]) => rule.test("**You → Manage → Library care**, **You → Account → Change password**, the sidebar's Server settings"))],
    [[true, true, true, true], false])
  check(`${guides.length} guides: none writes a managing page's way the old way`, broken, [])
}

console.log(failures ? `\n${failures} FAILED` : '\nall passed')
process.exit(failures ? 1 : 0)
