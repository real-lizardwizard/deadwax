#!/usr/bin/env node
/**
 * Get, for the iPhone app (Phase 6, slice 2 - notes/ios-specs/phase6-get-requests.md 6.2): what the web app's own
 * TypeScript answers, written as a fixture for the Swift ports in ios/DeadwaxKit/Sources/DeadwaxCore (GetRelease.swift,
 * StoreLine.swift, Sources.swift, GetSettings.swift, Whose.withStoreLine) to replay
 * (Tests/DeadwaxCoreTests/GetVectorTests.swift) - so a Get on the phone sends the body the web's sends, its store line
 * and its Sources sheet say what the web's say, and they rank, filter and describe every folder as the web does.
 *
 * Compiles lib/releasePayload.ts, lib/release.ts, lib/pressings.ts, lib/candidates.ts, lib/getSettings.ts,
 * lib/perPerson.ts, lib/whose.ts and lib/format.ts with what they import, and reads the words that live in components -
 * Sources.tsx's, SourceCard.tsx's, ReleaseGroupPage.tsx's Get the album and permissions.ts's GET_OFF - from their source.
 * Writes ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/get/get-vectors.json:
 *
 *   numbers     the speed bar's full rate, the score bands
 *   words       the sheet's, a card's, the store line's, the sort's, the floors', the signals'
 *   found       what each of the main page's two Find buttons sent (tests/fixtures/payloads/find-buttons.json) - each
 *               case's group and pressing, the body the one builder makes of them, and the album as a whole's
 *   groups      getGroup over the real pressings (tests/fixtures/pressings/, find-buttons.json's) - with and without the
 *               group Search handed over, each pressing chosen and none - and the body of each pressing chosen
 *   made        seeded groups and pressings with every edge a payload has (credits empty or absent, video media and
 *               recordings, disc titles of white space, events without an area, catalogue numbers empty) and their bodies
 *   editions    detectEditionTags over titles, disambiguations and packagings - JavaScript's \s included
 *   videos      isVideoTrack over every format and flag
 *   stores      seeded store answers: storeStatus, storeStatusFor at every floor, withoutJoin, storeNotes, and each
 *               download's progress, copy and floor verdicts
 *   whose       withStoreLine over seeded holdings and store answers
 *   cards       seeded folders: every fact a card draws and its reasoning
 *   lists       seeded answers through seeded chips and every sort: what passes, what shows in what order, the best,
 *               every state's line and the announcement
 *   chips       sourceChips, floorFilters and pressedCount for every floor and every set of chips
 *   settings    readGetSettings over answers right and wrong
 *   searching   searchingLine over credits as credited and current, "N/A", white space and case
 *   overrides   queryOverride over what was typed and what was shown
 *
 * Every random choice is seeded, and the output is plain ASCII (anything else as a \u escape), so a run on any machine
 * writes the same bytes. Never edit the fixture by hand - change the TypeScript, then run this.
 *
 *   node ios/scripts/export-get-vectors.cjs           write the fixture
 *   node ios/scripts/export-get-vectors.cjs --check   write nothing; exit 1 when the fixture differs
 *
 * Needs ui/node_modules (tsc) and a writable TMPDIR, as the sims do.
 */

const { execFileSync } = require('child_process')
const assert = require('assert')
const fs = require('fs'), os = require('os'), path = require('path')

const REPO = path.resolve(__dirname, '..', '..')
const UI = path.join(REPO, 'ui')
const FIXTURE = path.join(REPO, 'ios', 'DeadwaxKit', 'Tests', 'DeadwaxCoreTests', 'Fixtures', 'get', 'get-vectors.json')
const CHECK = process.argv.includes('--check')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-get-vectors-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/releasePayload.ts', 'src/lib/release.ts', 'src/lib/pressings.ts', 'src/lib/candidates.ts',
  'src/lib/getSettings.ts', 'src/lib/perPerson.ts', 'src/lib/whose.ts', 'src/lib/format.ts',
  '--rootDir', 'src', '--outDir', OUT, '--module', 'commonjs', '--target', 'es2022',
  '--skipLibCheck', '--moduleResolution', 'node', '--lib', 'es2022,dom',
], { cwd: UI, stdio: 'inherit' })

const R = require(path.join(OUT, 'lib/releasePayload.js'))
const Rel = require(path.join(OUT, 'lib/release.js'))
const Pr = require(path.join(OUT, 'lib/pressings.js'))
const C = require(path.join(OUT, 'lib/candidates.js'))
const G = require(path.join(OUT, 'lib/getSettings.js'))
const P = require(path.join(OUT, 'lib/perPerson.js'))
const W = require(path.join(OUT, 'lib/whose.js'))
const F = require(path.join(OUT, 'lib/format.js'))
const M = require(path.join(OUT, 'lib/myLibrary.js'))

/** A line of a component's source, which the exporter can't compile without Preact - the first match's group. */
function sourceMatch(file, pattern) {
  const text = fs.readFileSync(path.join(UI, file), 'utf8')
  const found = text.match(pattern)
  if (!found) throw new Error(`${file} no longer has ${pattern}`)
  return found[1]
}

/** Whether a component's source still says `words` - for the words it builds inline. */
function sourceHas(file, words) {
  if (!fs.readFileSync(path.join(UI, file), 'utf8').includes(words)) throw new Error(`${file} no longer says ${words}`)
  return words
}

/* ===== seeded randomness ===== */

let seed = 6620
const rand = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648
const pick = (list) => list[Math.floor(rand() * list.length)]
const between = (low, high) => low + Math.floor(rand() * (high - low + 1))
const chance = (p) => rand() < p
/** Some of a list, in its order. */
const some = (list, p = 0.5) => list.filter(() => chance(p))

/* ===== the numbers and the words ===== */

function numbers() {
  return {
    speedBarFull: C.SPEED_BAR_FULL,
    bands: [0, 39, 39.5, 40, 74, 74.5, 75, 100].map((percent) => ({ percent, band: C.scoreClass(percent) })),
  }
}

function words() {
  const sheet = 'src/app/Sources.tsx'
  const card = 'src/app/SourceCard.tsx'
  const page = 'src/app/ReleaseGroupPage.tsx'
  return {
    sheet: {
      title: sourceMatch(sheet, /<h2 id="app-sources-title" class="app-sources-title">([^<]+)<\/h2>/),
      cancel: sourceMatch(sheet, /class="app-sources-cancel" onClick=\{onClose\}>\s*([^<\s][^<]*?)\s*<\/button>/),
      searchTakes: sourceMatch(sheet, /export const SEARCH_TAKES = '([^']+)'/),
      searchFor: sourceMatch(sheet, /<span class="app-sources-query-label">([^<]+)<\/span>/),
      search: sourceMatch(sheet, /<button type="submit" class="app-button">\s*([^<\s][^<]*?)\s*<\/button>/),
      tryAgain: sourceHas(sheet, 'Try again'),
      clearFilters: sourceHas(sheet, 'Clear filters'),
      searchAgain: sourceHas(sheet, 'Search again'),
      sortLabel: sourceMatch(sheet, /<span class="app-visually-hidden">(Sort the sources)<\/span>/),
      chipsLabel: sourceMatch(sheet, /aria-label="(Filter the sources)"/),
    },
    card: {
      get: sourceMatch(card, /onClick=\{\(\) => onGet\(candidate\)\}\s*>\s*([^<\s][^<]*?)\s*<\/button>/),
      getLabel: sourceHas(card, 'aria-label={`Get ${candidate.directory_name} from ${candidate.username}`}'),
      match: sourceHas(card, 'aria-label={`${percent}% match`}'),
      from: sourceHas(card, 'from {candidate.username}'),
      discs: sourceHas(card, "{discs > 1 ? ` · in ${discs} parts, one per disc` : ''}"),
      speed: sourceMatch(card, /<span class="app-source-label">([^<]+)<\/span>/),
      facts: [...fs.readFileSync(path.join(UI, card), 'utf8').matchAll(/<dt class="app-source-label">([^<]+)<\/dt>/g)].map((m) => m[1]),
      noSize: sourceMatch(card, /formatSize\(candidate\.total_size\) \|\| '([^']+)'/),
      reasons: sourceHas(card, "Why it's a {percent}% match"),
      inItsName: sourceMatch(card, /<span class="app-visually-hidden">([^<]+)<\/span>\s*\{tags\.map/),
    },
    page: {
      get: sourceMatch(page, /<GetIcon class="app-rg-get-icon" \/>\s*([^<\s][^<]*?)\s*<\/button>/),
      getOff: sourceMatch('src/lib/permissions.ts', /export const GET_OFF = '([^']+)'/),
    },
    store: {
      heldTitle: C.HELD_TITLE,
      inTheStore: M.IN_THE_STORE,
      addNote: M.ADD_NOTE,
      joinNotes: ['Downloads', 'Requests'].map((place) => ({ place, said: P.joinNote(place) })),
      sharedNotes: ['Downloads', 'Requests'].map((place) => ({ place, said: P.sharedNote(place) })),
    },
    nothingLosslessNote: C.NOTHING_LOSSLESS_NOTE,
    sorts: Object.entries(C.SORT_LABELS).map(([sort, label]) => ({ sort, label })),
    floors: G.QUALITY_FLOORS.map(({ value, label }) => ({ floor: value, label })),
    signals: Object.keys(C.SIGNAL_LABELS).map((signal) => ({ signal, label: C.SIGNAL_LABELS[signal], meaning: C.SIGNAL_MEANINGS[signal] })),
    losslessFormats: [...C.LOSSLESS_FORMATS],
    sourcesCount: [0, 1, 2, 41].map((count) => ({ count, said: C.sourcesCount(count), none: C.noneMatchLine(count) })),
  }
}

/* ===== MusicBrainz's objects, kept to what a Get reads (presence, and null, kept as they were) ===== */

function only(object, keys, nested = {}) {
  if (object === null || typeof object !== 'object') return object
  const out = {}
  for (const key of keys) {
    if (!(key in object)) continue
    const value = object[key]
    out[key] = nested[key] && value !== null && value !== undefined ? nested[key](value) : value
  }
  return out
}
const list = (each) => (value) => (Array.isArray(value) ? value.map(each) : value)
const slimCredit = list((entry) => only(entry, ['name', 'joinphrase', 'artist'], { artist: (a) => only(a, ['id', 'name']) }))
const slimGroup = (group) => only(group, ['id', 'title', 'first-release-date', 'artist-credit'], { 'artist-credit': slimCredit })
const slimRecording = (recording) => only(recording, ['id', 'title', 'length', 'video', 'artist-credit'], { 'artist-credit': slimCredit })
const slimTrack = (track) => only(track, ['number', 'position', 'title', 'length', 'artist-credit', 'recording'], {
  'artist-credit': slimCredit, recording: slimRecording,
})
const slimMedium = (medium) => only(medium, ['position', 'format', 'title', 'tracks'], { tracks: list(slimTrack) })
const slimRelease = (release) => only(release, [
  'id', 'title', 'status', 'date', 'country', 'disambiguation', 'packaging', 'release-events', 'label-info',
  'artist-credit', 'release-group', 'media',
], {
  'release-events': list((event) => only(event, ['date', 'area'], { area: (area) => only(area, ['iso-3166-1-codes']) })),
  'label-info': list((info) => only(info, ['catalog-number', 'label'], { label: (label) => only(label, ['name']) })),
  'artist-credit': slimCredit,
  'release-group': slimGroup,
  media: list(slimMedium),
})

const built = (group, release) => {
  const { release: payload, label } = R.buildDownloadRelease(group, release)
  return { payload, label }
}

function found() {
  const { cases } = JSON.parse(fs.readFileSync(path.join(REPO, 'tests/fixtures/payloads/find-buttons.json'), 'utf8'))
  return cases.map((c) => {
    const pressing = c.kind === 'row' ? c.pressings.find((release) => release.id === c.release_id) : R.usualPressing(c.pressings)
    const group = slimGroup(c.group)
    const release = slimRelease(pressing)
    const made = built(group, release)
    //? the fixture's own word: the one builder sends what the main page's Find sent
    assert.deepStrictEqual(made.payload, c.expected, `${c.name}: the body isn't the main page's`)
    return { name: c.name, group, release, ...made, whole: built(group, null) }
  })
}

function groups() {
  const out = []
  const sets = []
  for (const name of ['dummy', 'slow-rush', 'third', 'wish-you-were-here-experience']) {
    const fixture = JSON.parse(fs.readFileSync(path.join(REPO, 'tests/fixtures/pressings', `${name}.json`), 'utf8'))
    //? these carry no group of their own: the page's, made of what the fixture names, and none
    sets.push({ name, id: fixture.group.id, releases: fixture.releases, previews: [null, { id: fixture.group.id, title: fixture.group.title }] })
  }
  const { cases } = JSON.parse(fs.readFileSync(path.join(REPO, 'tests/fixtures/payloads/find-buttons.json'), 'utf8'))
  for (const c of cases.filter((each) => each.kind === 'card')) {
    sets.push({ name: c.name, id: c.release_group_mbid, releases: c.pressings, previews: [null, slimGroup(c.group)] })
  }
  for (const set of sets) {
    const releases = set.releases.map(slimRelease)
    const chosen = [null, ...some(releases.map((_, at) => at), 0.25).slice(0, 4)]
    if (chosen.length === 1) chosen.push(0)
    const usual = releases.indexOf(R.usualPressing(releases))
    if (!chosen.includes(usual)) chosen.push(usual)
    for (const preview of set.previews) {
      for (const at of chosen) {
        const release = at === null ? null : releases[at]
        const group = Pr.getGroup(set.id, preview, releases, release)
        out.push({
          name: set.name, id: set.id, preview, chosen: at,
          group: { id: group.id, title: group.title, 'first-release-date': group['first-release-date'], credit: group['artist-credit'] ?? null },
          ...(release ? built(group, release) : {}),
        })
      }
    }
    out.push({ name: set.name, releases })
  }
  return out
}

/* ===== made groups and pressings ===== */

const CREDITS = [
  undefined, [],
  [{ name: 'Portishead', joinphrase: '', artist: { id: '8f6bd1e4-fbe1-4f50-aa9b-94c450ec0f11', name: 'Portishead' } }],
  [{ name: 'Kanye West', joinphrase: '', artist: { id: '164f0d73-1234-4e2c-8743-d77bf2191051', name: 'Ye' } }],
  [{ name: 'Simon', joinphrase: ' & ', artist: { id: 'a1', name: 'Paul Simon' } }, { name: 'Garfunkel', joinphrase: '', artist: { id: 'a2', name: 'Art Garfunkel' } }],
  [{ name: '', artist: { id: 'a3', name: 'Named By The Artist' } }],
  [{ artist: { id: 'a4', name: 'Same' } }, { name: 'Same Again', joinphrase: ' feat. ', artist: { id: 'a4', name: 'Same' } }],
  [{ name: '  Padded  ' }],
  [{ name: 'Björk', joinphrase: null, artist: { id: '', name: 'Björk' } }],
]
const FORMATS = [undefined, null, '', 'CD', 'Digital Media', 'Vinyl', '12" Vinyl', 'DVD', 'DVD-Video', 'Blu-ray', 'VHS', 'DualDisc (DVD-Video side)', 'dvd-video']
const DISC_TITLES = [undefined, null, '', '   ', ' Bonus ', 'Disc 2: Live', '﻿']
const TITLES = [undefined, '', 'Silence', 'Hunter', 'Nylon Smile', 'The Rip', 'Élégie']
const DATES = [undefined, null, '', '2008', '2008-04-28', '199', 'N/A', '19940822']
const ALBUMS = [undefined, '', 'Third', 'Dummy (Deluxe Edition)', 'Super Deluxe', 'Remastered', 'Acoustic', 'A Cappella', 'Instrumentals', 'Box Set']

function madeTrack() {
  const track = {}
  if (chance(0.8)) track.position = pick([null, 1, 2, 3, 7, 12])
  if (chance(0.7)) track.title = pick(TITLES)
  if (chance(0.7)) track.length = pick([null, 0, 1000, 214000, 2.5, 306973])
  if (chance(0.3)) track['artist-credit'] = pick(CREDITS)
  if (chance(0.8)) {
    const recording = {}
    if (chance(0.7)) recording.title = pick(TITLES)
    if (chance(0.7)) recording.length = pick([null, 0, 213999, 306200])
    if (chance(0.3)) recording.video = pick([true, false, null, 'true'])
    if (chance(0.3)) recording['artist-credit'] = pick(CREDITS)
    track.recording = recording
  }
  return track
}

function madeRelease(at) {
  const release = { id: `release-${at}` }
  if (chance(0.8)) release.title = pick(ALBUMS)
  if (chance(0.7)) release.date = pick(DATES)
  if (chance(0.5)) release.country = pick([null, '', 'GB', 'XE'])
  if (chance(0.6)) release.disambiguation = pick([null, '', 'deluxe edition', 'remaster', 'super deluxe', 'boxset', 'a cappella'])
  if (chance(0.4)) release.packaging = pick([null, 'Box', 'box', 'Jewel Case'])
  if (chance(0.7)) {
    release['release-events'] = pick([
      [], [{ date: '2008-04-28', area: { 'iso-3166-1-codes': ['GB'] } }], [{ date: '', area: { 'iso-3166-1-codes': [] } }],
      [{ area: null }], [{ date: '1999', area: { 'iso-3166-1-codes': ['XE', 'XW'] } }, { date: '2001', area: { 'iso-3166-1-codes': ['US'] } }],
      [{ date: null, area: { 'iso-3166-1-codes': [''] } }], [{ date: '2014-03' }],
    ])
  }
  if (chance(0.6)) {
    release['label-info'] = pick([
      [], [{ 'catalog-number': 'CID 8018', label: { name: 'Island' } }],
      [{ 'catalog-number': null }, { 'catalog-number': '' }, { 'catalog-number': 'ABC 1' }, { 'catalog-number': 'ABC 2' }],
    ])
  }
  if (chance(0.7)) release['artist-credit'] = pick(CREDITS)
  if (chance(0.9)) {
    release.media = [...Array(between(0, 3)).keys()].map(() => {
      const medium = {}
      if (chance(0.7)) medium.position = pick([null, 1, 2, 3])
      if (chance(0.8)) medium.format = pick(FORMATS)
      if (chance(0.6)) medium.title = pick(DISC_TITLES)
      if (chance(0.95)) medium.tracks = [...Array(between(0, 4)).keys()].map(madeTrack)
      return medium
    })
  }
  return release
}

function madeGroup(at) {
  const group = { id: pick(['', `group-${at}`, '48140466-cff6-3222-bd55-63c27e43190d']) }
  if (chance(0.8)) group.title = pick(ALBUMS)
  if (chance(0.8)) group['first-release-date'] = pick(DATES)
  if (chance(0.8)) group['artist-credit'] = pick(CREDITS)
  return group
}

function made() {
  return [...Array(120).keys()].map((at) => {
    const group = madeGroup(at)
    const release = chance(0.85) ? madeRelease(at) : null
    return { group, release, ...built(group, release) }
  })
}

/* ===== edition words, video ===== */

function editions() {
  const fixed = [
    ['Dummy', null, null], ['Donda (Deluxe)', null, null], ['Super Deluxe Edition', null, null],
    ['Remastered 2011', null, null], ['25th Anniversary Super Deluxe', 'remaster', null], ['The Box Set', null, null],
    ['Boxset', null, null], ['Box', null, 'Box'], ['Box Set', null, 'Box'], ['Album', null, 'box'],
    ['Album', null, 'Jewel Case'], ['Expanded Edition', null, null], ['Limited Edition', null, null],
    ['Special Edition', null, null], ['Instrumentals', null, null], ['Acoustic Sessions', null, null],
    ['A Cappella', null, null], ['a capella', null, null], ['Acappella', null, null], ['A Cappella', null, null],
    ['A cappella', null, null], ['A​cappella', null, null], ['A᠎cappella', null, null],
    ['A﻿cappella', null, null], ['A 　cappella', null, null], ['A\t\ncapella', null, null],
    ['a  c a p p e l l a', null, null], [undefined, 'deluxe edition', undefined], [undefined, undefined, undefined],
    ['', '', ''], ['SUPER DELUXE', 'DELUXE', null], ['deluxe', 'super deluxe', 'Box'], ['DELUXE', null, null],
    ['İnstrumental', null, null], ['Re­master', null, null], ['Remaster', 'anniversary', 'Box'],
  ]
  const pool = ['remaster', 'deluxe', 'super', 'box', 'set', 'boxset', 'anniversary', 'expanded', 'limited', 'edition',
    'special', 'instrumental', 'acoustic', 'a', 'capella', 'cappella', 'Live', '2011', ' ', ' ', '(', ')']
  for (let n = 0; n < 60; n++) {
    const text = () => [...Array(between(0, 5)).keys()].map(() => pick(pool)).join(pick([' ', '', '-']))
    fixed.push([chance(0.8) ? text() : undefined, chance(0.5) ? text() : pick([undefined, null]), pick([undefined, null, 'Box', 'Digipak'])])
  }
  return fixed.map(([title, disambiguation, packaging]) => {
    const release = {}
    if (title !== undefined) release.title = title
    if (disambiguation !== undefined) release.disambiguation = disambiguation
    if (packaging !== undefined) release.packaging = packaging
    return { release, tags: Rel.detectEditionTags(release) }
  })
}

function videos() {
  const out = []
  for (const format of FORMATS) {
    for (const video of [undefined, true, false, null, 'true']) {
      const recording = video === undefined ? {} : { video }
      out.push({ medium: format === undefined ? {} : { format }, recording, video: Rel.isVideoTrack(format === undefined ? {} : { format }, { recording }) })
    }
  }
  return out
}

/* ===== the store ===== */

const PATHS = ['Portishead/Third (2008)', 'Portishead/Third (2008)/CD 1', 'Portishead/Third (2008)/CD 2', 'Portishead/Third',
  'Portishead/Third (2008) [Deluxe]', 'Björk/Homogenic (1997)']
const FORMAT_LISTS = [[], ['flac'], ['flac', 'mp3'], ['', 'mp3'], ['mp3'], ['alac'], ['FLAC'], ['wav', 'flac']]
const USERS = ['bob', 'mellotron', 'Alice', 'nümber9']
const FLOORS = [null, 'any', '320', 'lossless', '24bit']

function heldPressing() {
  const complete = chance(0.5)
  const held = {
    path: pick(PATHS), artist: 'Portishead', album: 'Third', edition: pick(['', 'Deluxe']),
    track_count: between(0, 12), expected_tracks: pick([0, 1, 11, 12]), formats: pick(FORMAT_LISTS), complete,
  }
  const paths = pick([[held.path], [held.path], [PATHS[1], PATHS[2]], []])
  if (chance(0.9)) held.paths = paths
  if (!complete && chance(0.9)) {
    held.filed_to = pick([null, '', held.path, PATHS[4]])
    held.fills_gaps = chance(0.5) ? (held.paths ?? []).includes(held.filed_to) : chance(0.5)
  }
  if (chance(0.5)) held.yours = chance(0.5)
  return held
}

function inFlight() {
  const download = {
    job_id: between(1, 400), status: pick(['queued', 'downloading', 'organizing', 'complete', 'failed', 'partly_organized']),
    username: pick(USERS), files: between(1, 14),
  }
  if (chance(0.5)) download.done_files = between(0, download.files)
  if (chance(0.5)) download.yours = chance(0.5)
  if (chance(0.4)) download.shared = chance(0.6)
  if (chance(0.3)) download.requested_by = some(['ethan', 'sam', 'jo'])
  if (chance(0.7)) download.formats = pick(FORMAT_LISTS)
  if (chance(0.6)) download.bitrates = pick([[], [320], [128, 320], [245], [1411]])
  if (chance(0.6)) download.bit_depths = pick([[], [16], [24], [16, 24]])
  if (chance(0.6)) download.sample_rates = pick([[], [44100], [96000], [44100, 48000]])
  if (chance(0.5)) download.variable_bitrate = chance(0.5)
  return download
}

function storeAnswer() {
  const answer = { held: null, downloading: null, downloading_part: null, other_pressings: [] }
  const shape = pick(['nothing', 'held', 'downloading', 'part', 'mixed', 'mixed'])
  if (shape === 'held' || (shape === 'mixed' && chance(0.6))) answer.held = heldPressing()
  if (shape === 'downloading' || (shape === 'mixed' && chance(0.3))) answer.downloading = inFlight()
  if (shape === 'part' || (shape === 'mixed' && chance(0.4))) answer.downloading_part = inFlight()
  if (chance(0.4)) {
    answer.other_pressings = [...Array(between(1, 3)).keys()].map(() => {
      const pressing = {
        path: pick(PATHS), release_mbid: pick([null, 'r-1']), edition: pick(['', 'Deluxe']), year: pick(['', '1994']),
        track_count: between(1, 12), formats: pick(FORMAT_LISTS),
      }
      if (chance(0.5)) pressing.yours = chance(0.5)
      return pressing
    })
  }
  return answer
}

const statusOut = (status) => (status ? {
  kind: status.kind, title: status.title, lines: status.lines, joinJobId: status.joinJobId ?? null, add: Boolean(status.add),
} : null)

function downloadOut(download) {
  if (!download) return null
  return {
    beingFiled: C.beingFiled(download), progress: C.downloadProgressText(download), copy: P.copyText(download),
    verdicts: ['any', '320', 'lossless', '24bit'].map((floor) => ({ floor, verdict: P.floorVerdict(download, floor), note: P.floorNote(download, floor) })),
  }
}

function stores() {
  return [...Array(200).keys()].map(() => {
    const answer = storeAnswer()
    const cancelIn = pick(['Downloads', 'Requests'])
    return {
      answer, cancelIn,
      status: statusOut(C.storeStatus(answer, cancelIn)),
      heldTrackText: answer.held ? C.heldTrackText(answer.held) : null,
      notes: C.storeNotes(answer),
      for: FLOORS.map((floor) => {
        const status = P.storeStatusFor(answer, cancelIn, floor)
        return { floor, status: statusOut(status), withoutJoin: statusOut(status ? P.withoutJoin(status) : null) }
      }),
      downloading: downloadOut(answer.downloading),
      part: downloadOut(answer.downloading_part),
    }
  })
}

function whose() {
  return [...Array(80).keys()].map(() => {
    const holding = some(PATHS, 0.4).map((path) => (chance(0.6) ? { path, yours: chance(0.5) } : { path }))
    const said = chance(0.15) ? null : storeAnswer()
    return { holding, said, yours: W.withStoreLine(holding, said).map((album) => (album.yours === undefined ? null : album.yours)) }
  })
}

/* ===== the sources ===== */

const SIGNALS = ['title_match', 'track_count', 'duration_match', 'edition', 'format', 'peer']
const TAGS = ['REMASTER', 'SUPER DELUXE', 'DELUXE', 'BOX SET', 'ANNIVERSARY', 'EXPANDED', 'LIMITED', 'SPECIAL EDITION', 'INSTRUMENTAL', 'ACOUSTIC', 'A CAPPELLA', '']
let folders = 0

function candidate() {
  folders += 1
  const expected = pick([0, 10, 11, 14, 34])
  const signals = {}
  for (const signal of SIGNALS) signals[signal] = chance(0.2) ? null : pick([0, 0.1, 0.395, 0.4, 0.745, 0.75, 1, rand()])
  if (chance(0.15)) signals[pick(['bitrate', 'year', 'zebra'])] = rand()
  if (chance(0.05)) signals.title_match = '0.5'
  const formats = pick([[], ['flac'], ['flac', 'mp3'], ['mp3'], ['alac'], ['wav'], ['ogg'], ['', 'flac'], ['m4a', 'flac']])
  const lossless = formats.length && formats.every((format) => C.LOSSLESS_FORMATS.has(format))
  const out = {
    username: pick(USERS), directory: `${pick(['Music', 'share', '@@abcde'])}\\${pick(['Portishead', 'P'])}\\${folders}`,
    directory_name: pick(['Third', 'Portishead - Third (2008) [FLAC]', 'Third (Deluxe)', 'Élégie']),
    score: pick([0, 1, 0.75, 0.745, 0.4, 0.3949, rand(), rand(), rand()]),
    signals,
    matched_tracks: between(0, expected + 1), expected_tracks: expected, audio_file_count: between(0, 16),
    detected_edition_tags: some(TAGS, 0.15),
    formats,
    upload_speed: pick([0, 1500, 921600, 1048575, 1048576, 2202009.6, 3145728, 5242880]),
    queue_length: pick([0, 0, 1, 3, 12]),
    has_free_slot: chance(0.5),
    total_size: pick([0, 52428800, 313524224, 1073741823, 1073741824, 1503238553]),
    bitrates: lossless && chance(0.6) ? [] : pick([[], [320], [128, 320], [245, 256], [1411], [319]]),
    bit_depths: pick([[], [16], [24], [16, 24], [32]]),
    sample_rates: pick([[], [44100], [48000], [96000], [44100, 96000], [88200], [22050.5]]),
    variable_bitrate: chance(0.3),
    files: [...Array(between(0, 3)).keys()].map((at) => ({ filename: `${folders}\\${at + 1} Track.flac`, size: pick([0, 31415926, 1024]) })),
  }
  if (chance(0.6)) out.disc_folders = pick([[], ['CD 1'], ['CD 1', 'CD 2'], ['Disc 1', 'Disc 2', 'Disc 3']])
  if (chance(0.4)) out.measured_speed = pick([0, 900 * 1024, 2.1 * 1024 * 1024, 4 * 1024 * 1024])
  if (chance(0.4)) out.measured_samples = pick([0, 1, 2, 7])
  if (chance(0.8)) {
    out.missing_tracks = [...Array(between(0, 5)).keys()].map(() => ({
      position: pick([null, 1, 4, 11]), disc: pick([null, 1, 2]), title: pick(['', 'Threads', 'Small', 'Silence', 'Hunter', '“Quoted”']),
    }))
  }
  if (chance(0.8)) out.missing_count = Math.max(out.missing_tracks?.length ?? 0, between(0, 7))
  if (chance(0.15)) out.missing_count = 0
  if (chance(0.8)) out.audio_expected = pick([0, expected, Math.max(0, expected - 2), 14])
  return out
}

function facts(candidate) {
  return {
    key: C.candidateKey(candidate),
    percent: Math.round(candidate.score * 100),
    band: C.scoreClass(Math.round(candidate.score * 100)),
    speed: C.speedFact(candidate),
    starts: C.startsFact(candidate),
    quality: C.qualityText(candidate),
    tracks: C.tracksText(candidate),
    size: F.formatSize(candidate.total_size),
    signals: C.signalChips(candidate),
    tags: C.editionTags(candidate),
    missing: C.missingLine(candidate),
    everyTrack: C.everyTrackPresent(candidate),
    rank: C.qualityRank(candidate),
    copy: P.candidateQuality(candidate),
  }
}

function cards() {
  return [...Array(200).keys()].map(() => {
    const made = candidate()
    return { candidate: made, facts: facts(made) }
  })
}

function sourceFilters() {
  const filters = { ...G.NO_SOURCE_FILTERS }
  for (const key of Object.keys(filters)) filters[key] = chance(0.25)
  return filters
}

function result() {
  const candidates = [...Array(pick([0, 0, 1, 2, 4, 6, 9, 12])).keys()].map(candidate)
  const query = pick(['', 'Portishead Third', 'Kanye West Donda'])
  const answer = { query, response_count: pick([0, 0, 3, 41]), candidates }
  if (chance(0.7)) answer.queries = pick([[], [query], ['Kanye West Donda', 'Ye Donda'], ['a', 'b', 'c']])
  return answer
}

function lists() {
  const out = []
  for (let n = 0; n < 120; n++) {
    const answer = result()
    const filters = chance(0.3) ? { ...G.NO_SOURCE_FILTERS } : sourceFilters()
    const chosen = G.candidateFilters(filters)
    const passing = answer.candidates.filter((each) => C.passesFilters(each, chosen))
    const top = C.sortCandidates(passing, 'score')[0]
    const format = pick(['prefer_lossless', 'any', 'lossless_only', 'lossless_only', null])
    const status = chance(0.2) ? P.storeStatusFor(storeAnswer(), 'Requests', pick(FLOORS)) : null
    const notPicked = pick([null, null, G.notPickedLine(null, answer.candidates.length)])
    out.push({
      answer, filters, format,
      passing: passing.map(C.candidateKey),
      sorted: Object.keys(C.SORT_LABELS).map((sort) => ({ sort, keys: C.sortCandidates(passing, sort).map(C.candidateKey) })),
      best: top ? C.candidateKey(top) : null,
      queries: C.queriesText(answer),
      nothingLossless: C.nothingLossless(answer, format),
      nothingLosslessLine: C.nothingLosslessLine(answer),
      nothingFound: C.nothingFoundLine(answer),
      noneMatch: C.noneMatchLine(answer.candidates.length),
      searched: C.searchedLine(answer, passing.length),
      status: statusOut(status), notPicked,
      announcement: C.sourcesAnnouncement({
        pending: false, release: null, error: null, status, result: answer, shown: passing.length, notPicked, format,
      }),
    })
  }
  return out
}

function chips() {
  const out = []
  const keys = Object.keys(G.NO_SOURCE_FILTERS)
  for (const floor of G.QUALITY_FLOOR_VALUES) {
    for (let mask = 0; mask < 1 << keys.length; mask++) {
      const filters = Object.fromEntries(keys.map((key, at) => [key, Boolean(mask & (1 << at))]))
      out.push({ floor, filters, chips: G.sourceChips(floor, filters), pressed: G.pressedCount(filters), quality: G.candidateFilters(filters).quality })
    }
  }
  return { floors: G.QUALITY_FLOOR_VALUES.map((floor) => ({ floor, filters: G.floorFilters(floor) })), chips: out }
}

function settings() {
  const answers = [
    null, undefined, {}, { get_mode: 'pick', quality_floor: '320', format_preference: 'lossless_only' },
    { get_mode: 'sources', quality_floor: 'lossless', format_preference: 'any' },
    { get_mode: 'PICK', quality_floor: 320, format_preference: null }, { quality_floor: '24bit' },
    { get_mode: 'pick', quality_floor: '24-bit', format_preference: 'prefer_lossless', stored: ['get_mode'], seeded: true },
    { get_mode: ['pick'], quality_floor: { value: 'any' }, format_preference: 'Lossless only' },
  ]
  return answers.map((answer) => {
    const read = G.readGetSettings(answer)
    return { answer: answer === undefined ? null : answer, mode: read.get_mode, floor: read.quality_floor, format: read.format_preference }
  })
}

function searching() {
  const releases = [
    { artist: 'Portishead', album_artist: 'Portishead', album: 'Third' },
    { artist: 'Kanye West', album_artist: 'Ye', album: 'Donda' },
    { artist: 'N/A', album_artist: 'N/A', album: 'N/A' },
    { artist: 'N/A', album_artist: 'Someone', album: 'Untitled' },
    { artist: '  Portishead ', album_artist: 'portishead', album: 'Dummy' },
    { artist: '', album_artist: '', album: '' },
    { artist: 'BJÖRK', album_artist: 'björk', album: 'Homogenic' },
    { artist: 'İstanbul', album_artist: 'i̇stanbul', album: 'X' },
    { artist: 'Simon & Garfunkel', album_artist: 'Paul Simon & Art Garfunkel', album: 'Bookends' },
    { artist: ' ', album_artist: '﻿Ye　', album: '“Quotes”' },
    { artist: 'n/a', album_artist: 'N/A ', album: 'Lower' },
  ]
  return releases.map((release) => ({ release, said: C.searchingLine(release) }))
}

function overrides() {
  const typed = ['', '   ', 'Portishead Third', ' Portishead Third ', 'Portishead  Third', 'portishead third', ' Third ', 'Third']
  const shown = ['', 'Portishead Third', 'Third']
  return typed.flatMap((text) => shown.map((last) => ({ typed: text, shown: last, override: C.queryOverride(text, last) })))
}

/* ===== out ===== */

function vectors() {
  return {
    numbers: numbers(),
    words: words(),
    found: found(),
    groups: groups(),
    made: made(),
    editions: editions(),
    videos: videos(),
    stores: stores(),
    whose: whose(),
    cards: cards(),
    lists: lists(),
    chips: chips(),
    settings: settings(),
    searching: searching(),
    overrides: overrides(),
  }
}

/** JSON with every character outside printable ASCII as an escape, so the file holds none raw. */
const say = (value) => JSON.stringify(value, null, 1).replace(/[^\n -~]/g, (c) => `\\u${c.charCodeAt(0).toString(16).padStart(4, '0')}`) + '\n'

const madeText = say(vectors())
if (CHECK) {
  const committed = fs.existsSync(FIXTURE) ? fs.readFileSync(FIXTURE, 'utf8') : null
  if (committed !== madeText) {
    console.error(`  FAIL  ${path.relative(REPO, FIXTURE)} isn't what the web's TypeScript answers today - run node ios/scripts/export-get-vectors.cjs, then port the change to DeadwaxCore and see GetVectorTests pass`)
    process.exit(1)
  }
  console.log(`${path.relative(REPO, FIXTURE)} is what the web's TypeScript answers today`)
} else {
  fs.mkdirSync(path.dirname(FIXTURE), { recursive: true })
  fs.writeFileSync(FIXTURE, madeText)
  console.log(`wrote ${path.relative(REPO, FIXTURE)}`)
}
