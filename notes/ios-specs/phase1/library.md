# Phase 1 spec: the Library (your albums, the store's, sorts, headers, Find, the index, New)

Scouted on `ios` at 1199330 (deadwax 2.1.0, the server and web app identical to 2.0.15). Read for this: notes/ios.md,
the plan (sections 2, 3, 5), ui/src/lib/shelves.ts, ui/src/lib/owned.ts (foldName), ui/src/app/{albumIndex.ts,
useYourAlbums.ts, LibraryHome.tsx, LibrarySection.tsx, Shelf.tsx, ShelfIndex.tsx, AlbumTile.tsx, LibraryViews.tsx,
useMyLibrary.ts}, ui/src/player/{Library.tsx, api.ts, AlbumPage.tsx (the preview only)}, ui/src/lib/{myLibrary.ts,
yourLibrary.ts, appFrame.ts}, ui/src/api/types.ts (MyLibrary, LibraryEntry), src/routes/navidrome.py (/album_index),
src/api/json_etag.py, src/routes/my_library.py, notes/app-library.md, ui/test/shelves.sim.cjs, whose.sim.cjs,
mylibrary.sim.cjs, tests/test_navidrome_album_index.py, tests/test_ios_contract.py, ios/DeadwaxKit/Sources/DeadwaxCore.

**Verified here, not assumed**: a Swift port of foldName/findText, Date.parse (Navidrome's forms), monthLabel, the
five sorts with both `AddedBy`, groupAlbums (moments included), filterAlbums, indexEntries, fitIndex and entryAt was
compiled with Xcode 27.1's toolchain on this Mac and compared output-for-output with the compiled shelves.ts:
**0 differences** over 4,077 names (fold and find), 3,031 date strings (TZ=UTC and TZ=America/New_York), 46 album
lists (the sim's fixtures and 40 random lists of 1-300 albums with stars seconds apart across month ends) x 5 sorts
x 2 `by` x 12 Find strings, and the index over 0-40 slots swept every 0.5 px. The reference code is in section 5-9.
shelves.sim (71 checks) and test_navidrome_album_index.py (21) pass at HEAD.

## 0. What changed in these files since 2.0.0 (`git log 85aa7be..HEAD`)

| file | commits | what the phone must follow |
| --- | --- | --- |
| lib/shelves.ts | ae41360 (2.0.11) | `AddedBy` (`collection`/`you`), `SAME_MOMENT_MS`, `moments()`, `starred` in AlbumKeys, `groupAlbums(..., by, whole)`: Recently added over YOUR albums is when YOU starred them |
| app/LibrarySection.tsx | bec8e8c 2.0.4, 6452ff3 2.0.5, e04ac43 2.0.9, ae41360 2.0.11 | COULDNT_REFRESH reworded; errors through errorNote; "No albums yet." (was "No albums in Navidrome yet."); `by` from the scope |
| app/LibraryHome.tsx | 2.0.4, 2.0.5, 0056222 2.0.10, 2.0.11 | the Browse heading is **"All music"** (was "Browse"); row icons (record / head / note); the root's 12 by `'you'` |
| app/LibraryViews.tsx, lib/yourLibrary.ts, lib/appFrame.ts | 2.0.4, 2.0.5, 2.0.8, 2.0.9 | **"See All music"** (was "Browse the store"); titles "Your albums", "All albums" (was "Albums in the store") |
| lib/myLibrary.ts | 2.0.5, 2.0.6 | words only; `newMarks`/`isNew` unchanged |
| src/routes/navidrome.py | bec8e8c 2.0.4 | playlists' errors only; `/album_index` unchanged since 2.0.0-player.59 |
| lib/owned.ts (foldName) | 098c66c 2.0.6 | chip words only; **foldName unchanged** |
| albumIndex.ts, useYourAlbums.ts, Shelf.tsx, ShelfIndex.tsx, player/api.ts Album | none (api.ts: 2.0.4 errors only) | - |

So the plan's "Browse the store" row is now **All albums** under **All music** in the web's words.

## 1. What the web's phone Library is, and the Phase 1 subset

The web (player/Library.tsx:46-158, app/LibraryHome.tsx:46-160): a ROOT of rows - Shuffle (Phase 4), Playlists
(Phase 4), then `libraryItems(hasSongs, personal)` minus `recent` (appFrame.ts:239-243), then with a library of your
own a group headed `ALL_MUSIC` = "All music" holding `browseItems` (appFrame.ts:246-249), then "Recently added" with
"See all" and the newest `RECENT_ON_ROOT` = 12 tiles. Each row pushes a SECTION page (app/LibrarySection.tsx:187-200).

`personal` = `hasLibrary()` (useMyLibrary.ts:42-45) = `me.auth == "on" && me.user != "deadwax"` (BREAK_GLASS_USER,
lib/signIn.ts:11). In Swift: `me.loginsOn && me.user != "deadwax"`.

| row id | label personal (SIDEBAR_YOURS/BROWSE, appFrame.ts:172-188) | label otherwise (SIDEBAR_LIBRARY) | scope | `by` | section title (libraryTitle) |
| --- | --- | --- | --- | --- | --- |
| `albums` | "Your albums" | "Albums" | personal ? `yours` : `store` | `you` if scope is `yours`, else `collection` | "Your albums" / "Albums" |
| `store` | "All albums" (under "All music") | - (not shown; `shownPick` maps it to `albums`) | `store` | `collection` | "All albums" |
| `recent` | (the root's grid + "See all") | same | as `albums` | as `albums` | "Recently added" |

Scope rule, verbatim from AlbumSection (LibrarySection.tsx:210, 222): `scope = id == 'store' || !personal ? 'store' :
'yours'`; `by = scope == 'yours' ? 'you' : 'collection'`. With logins off, and for break-glass, nothing ever asks
`scope=yours`.

**Phase 1 subset** (plan section 5): one Albums screen of the scope above - grid or list, the sorts Artist / Title /
Recently added / Year, Find in place, letter (and month, year) headers, the index if cheap, and with `personal` one
row "All albums" pushing the same screen with `scope=store`. Not in Phase 1: the root's Shuffle, Playlists, Artists,
Songs rows, the played sorts, the root's 12 (see Open questions 1).

## 2. The route: `GET /deadwax/navidrome/album_index?scope=yours|store`

src/routes/navidrome.py:285-328 (permission **user**: the navidrome router is included with `signed_in`,
src/api/app.py:437).

- `scope`: `AlbumScope = Literal["yours", "store"]` (:289), **required** (`Query(...)`). Missing, empty, `frequent`,
  `STORE` -> **422**, Navidrome not asked (`test_a_scope_outside_the_two_is_refused_before_navidrome_is_asked`).
- `SCOPE_LIST = {"yours": "starred", "store": "newest"}` (:293): getAlbumList2 of that type, **as the asker**
  (`client_for`), `size` `INDEX_PAGE` = 500 (:285), offset 0, 500, 1000 ... until a page shorter than 500, or offset
  reaches `INDEX_MAX` = 10000 (:286) -> `truncated: true` (Python `while ... else`: 20 full pages always say
  truncated, even if exactly 10,000 exist). Nothing else the app sends reaches Navidrome
  (`test_nothing_the_page_sends_reaches_navidrome_but_the_scope`).
- Each album once by `id` (a filing between pages repeats one; left out); entries that aren't objects or whose `id`
  isn't a string are dropped; each trimmed to `INDEX_FIELDS` (:287-288) **and only those present**, values exactly as
  Navidrome sent them; Navidrome's order (yours: starred_at desc; store: created_at desc).
- Answer **200**: `{"albums": [...], "truncated": bool}` - both keys always present. Through `json_with_etag`
  (src/api/json_etag.py:13-31): body = `json.dumps(payload, separators=(",", ":"))`; `ETag: "<blake2b-96 hex>"`
  (quoted, 24 hex chars); `Cache-Control: no-cache`. A request whose `If-None-Match` **equals the ETag string
  exactly** -> **304**, empty body, same ETag and Cache-Control. Gzipped by the app's GZipMiddleware (JSON over 1 KB);
  URLSession decompresses. Measured on the stand-in (notes/app-library.md): 3,000 albums = 813 KB, 132 KB gzipped,
  0.76 s at 0.1 s per Navidrome call.
- Failures: a page failing fails the whole answer (never partial) - **502** `detail` in Navidrome's words
  (`"database is locked"`), or "Navidrome couldn't be reached at ..." (`_fail`, :109-110); **503** NOT_CONFIGURED
  (navidrome_endpoint.py:69-71, 160); **401** with logins on and no session, or `detail` = `auth.LOGIN_GONE`
  ("Navidrome no longer accepts the login you signed in with - if you changed your Navidrome password, sign in with
  the new one.") when Navidrome refused the stored login - the session has ended: DeadwaxClient.failure already maps
  any 401 to `.signedOut`.
- Who is asked: logins off -> the shared account (`test_with_logins_off_the_shared_account_is_asked`); break-glass ->
  the shared account (`test_the_break_glass_admin_asks_as_the_shared_account`); logins on -> the signed-in user.

INDEX_FIELDS and what Navidrome (0.64.2's AlbumID3, as the fakes are shaped) puts in them:

| field | JSON type | present when | read by |
| --- | --- | --- | --- |
| `id` | string | always (the route drops others) | everything; New marks; album page |
| `name` | string | always from Navidrome (may be `""`) - not guaranteed by the route | tile/row title, Title sort, Find |
| `artist` | string | usually; the sim has `""` and absent | tile/row second line, Artist/Year sorts, Find |
| `artistId` | string | usually | album page's artist line |
| `coverArt` | string | usually | `/navidrome/cover/{coverArt}?size=` ; absent = empty square |
| `year` | integer | omitted when 0 | Year sorts/headers; `<= 0` or absent = "No year" |
| `genre` | string | optional | album page header ("genre · year · format") |
| `created` | string, RFC 3339 (Go RFC3339Nano: 0-9 fraction digits, `Z` or `+hh:mm`) | when Navidrome has it; **the dev stand-in sends a float** | Recently added (collection), moments' tie-break |
| `played` | string RFC 3339 | only once played | (Recently played - not Phase 1) |
| `playCount` | integer | only once played | (Most played - not Phase 1) |
| `starred` | string RFC 3339 | only if the ASKER starred it (every `yours` album has one; some `store` albums) | Recently added over `yours` |
| `musicBrainzId` | string (`""` for none) | Navidrome 0.64.2 always | New marks by release; album page |
| `songCount` | integer | always | list row (optional) |
| `duration` | integer seconds | always | list row (optional) |

pytest pinning the route: test_navidrome_album_index.py - `test_the_store_is_every_album_read_500_a_call_until_a_short_page`,
`test_a_full_last_page_asks_once_more_and_finds_the_end`, `test_yours_is_your_starred_albums_asked_as_you`,
`test_nothing_the_page_sends_reaches_navidrome_but_the_scope`, `test_a_scope_outside_the_two_is_refused_before_navidrome_is_asked`
(4 paths), `test_past_twenty_full_pages_the_answer_says_truncated_and_asks_no_more`,
`test_the_real_cap_is_twenty_pages_of_navidromes_500`, `test_an_album_repeated_across_pages_is_left_out`,
`test_entries_that_are_not_albums_with_an_id_are_dropped`, `test_each_album_is_trimmed_to_what_the_library_reads_values_untouched`,
`test_a_page_that_fails_fails_the_whole_answer_in_navidromes_words`, `test_a_navidrome_that_cant_be_reached_answers_as_every_route_does`,
`test_the_answer_carries_an_etag_and_an_unchanged_list_is_a_304`, `test_a_change_in_the_list_is_a_new_etag_and_a_200`,
`test_with_logins_off_the_shared_account_is_asked`, `test_the_break_glass_admin_asks_as_the_shared_account`,
`test_a_refused_login_is_the_401_that_ends_the_session`, `test_with_logins_on_the_list_needs_a_session`.
**No server change is needed for this area.**

## 3. Models, routes and the contract test (DeadwaxCore)

### Routes.swift (one line each, the form test_ios_contract.py reads)

```swift
public static let albumIndex = Endpoint(method: "GET", path: "/deadwax/navidrome/album_index", query: ["scope"])
// only if New marks are in (Open question 4); Add/Remove's area may add myLibrary anyway
public static let myLibrary = Endpoint(method: "GET", path: "/deadwax/me/library", query: [])
public static let librarySeen = Endpoint(method: "POST", path: "/deadwax/me/library/seen", query: [])
```

Add each to `Routes.all`. `CoverSize` gains `tile = 400` and `row = 128` (player/api.ts:438-443 `COVER_SIZES =
[128, 400, 1024]`, `coverSize()` = the smallest step >= the drawn size, else 1024; AlbumTile asks `size={400}`).

### Models.swift (keep them in this file: the contract test's `required_fields` reads only Models.swift)

```swift
public enum AlbumScope: String, Sendable { case yours, store }

/// One album of /album_index - INDEX_FIELDS. Only `id` is required; every other field is decoded leniently
/// (a missing key, null, or a value of another type is nil - never a failed list: the dev stand-in's `created`
/// is a float, which synthesized Codable would throw on, losing the whole Library).
public struct IndexAlbum: Decodable, Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let name: String?, artist: String?, artistId: String?, coverArt: String?, genre: String?
    public let year: Int?, playCount: Int?, songCount: Int?
    public let duration: Double?
    public let created: String?, played: String?, starred: String?, musicBrainzId: String?
    // init(from:): id = try decode(String); s(k) = (try? c.decodeIfPresent(String.self, forKey: k)) ?? nil;
    // i(k) likewise with Int; duration with Double. (Verified: decodes the sim's fixture with the float `created`.)
}

public struct AlbumIndexAnswer: Decodable, Sendable, Equatable {
    public let albums: [IndexAlbum]
    public let truncated: Bool
}
```

Web parity note: albumIndex.ts:58 reads `answer.albums ?? []` and `!!answer.truncated`; the server always sends
both, so required is right and lets the contract test pin them.

For New marks (optional, section 11): `MyLibrary { on: Bool; library: Bool?; kept: Bool?; count: Int?; starred: Int?;
new: [LibraryEntry]? }` and `LibraryEntry { album_id: Int; artist: String; album: String; release_mbid: String?;
release_group_mbid: String?; navidrome_id: String?; added_at: String?; how: String? }` (types.ts:1212-1248;
my_library.py:62-73 `_entry`, :85-122). `SeenBody { release_mbid: String?; album_ids: [Int]? }` - send exactly one of
the two (my_library.py:188-190: `release_mbid` max_length 64, `album_ids` max 200 items). Answer `{cleared: Int}`.

### DeadwaxClient

```swift
public enum AlbumIndexFetch: Sendable, Equatable {
    case fresh(AlbumIndexAnswer, etag: String?)   // 200
    case unchanged                                // 304: keep what you hold
}
public func albumIndex(_ scope: AlbumScope, ifNoneMatch etag: String?) async throws -> AlbumIndexFetch
```

- Sends `If-None-Match: <etag>` exactly as last received (`response.header("ETag")`), only when one is held.
- 200 -> decode; 304 -> `.unchanged` (a 304 with no ETag held is impossible; treat as a failure); else `failure()`.
- **Timeout**: the server answers only after reading every page; the transport's `timeoutIntervalForRequest = 8`
  (App/URLSessionTransport.swift) is an idle timer that no byte resets until then. Give this request 30 s (add an
  optional `timeout` to `HTTPRequest`, applied as `URLRequest.timeoutInterval`).
- The transport is `.ephemeral` with `.reloadIgnoringLocalCacheData`, so URLSession holds no cached copy and should
  hand the 304 itself to the app. Unverified on iOS 27 - the phone's Debug/log should show a 304 on the second look.

### tests/test_ios_contract.py (Python, on the ios branch)

- `test_the_app_names_its_routes_in_the_form_this_test_reads` hard-codes **7** routes: it must become the new count.
- New: every `IndexAlbum` field name is in `navidrome.INDEX_FIELDS` (else the app reads a field the route strips -
  silently nil); `required_fields("IndexAlbum") == {"id"}`; `required_fields("AlbumIndexAnswer") == {"albums",
  "truncated"}` and `inspect.getsource(navidrome.album_index)` returns both keys (as `test_search_answers_albums_and_songs`
  does); `typing.get_args(navidrome.AlbumScope) == ("yours", "store")` equals the Swift enum's raw values;
  `CoverSize.tile` and `CoverSize.row` within the cover route's `size` bounds (ge 16, le 2000); if Seen is in,
  `SeenBody`'s fields equal `my_library.Seen.model_fields`.

## 4. One list per scope (app/albumIndex.ts, app/useYourAlbums.ts) - the Swift store

Port albumIndex.ts's rules into a small `AlbumIndexStore` (an actor or @MainActor @Observable in the app over a
pure Core state machine - the state machine is what Linux tests).

Per scope (`yours`, `store`) it keeps: `generation: Int`, `held: (generation, task, pending)?`, `kept: (answer, etag,
at)?`. Rules (albumIndex.ts:52-95):

1. `list(scope)`: if nothing held or held for an older generation, ask (one ask shared by every reader). On success
   `pending = false`; the answer is kept if it is for the current generation **or nothing is kept yet**; an older ask
   landing late keeps nothing (whose.sim: "an older ask landing after a newer one keeps nothing"). On failure the ask
   is let go (`held = nil` if still the held one) - the next look asks again; nothing is kept from it.
2. `kept(scope)`: the last answer that landed this session, any generation - drawn at once while a new one is on its
   way (the list never empties; the scroll stays put).
3. `forget(scope)`: `generation += 1; held = nil` - asked again at the next look; the kept list still draws.
4. `refreshIfOld(scope)`: nothing kept -> nothing; an ask for this generation still pending -> nothing; else forget
   if `now - kept.at > INDEX_FRESH_MS` = **60,000 ms** (:33).
5. On a 304 (phone addition - the browser's cache did this for the web): keep the answer, set `at = now`.

When (the web's callers): `refreshIfOld` as the Albums screen appears (LibrarySection.tsx:240-242) and as the Library
tab shows (App.tsx:1280-1290: `store` always, `yours` with a library) - on iOS: `.onAppear` and the scene becoming
active with the screen visible. `forget(.yours)` after Add or Remove to/from your library (useYourAlbums.ts:28-33) and
when `GET /me/library`'s `starred` count moves from the last value seen (player/Library.tsx:86-94; the starring worker,
a star read back from Amperfy). **Never** after a filing (second review of .59). Clear everything on sign-out, sign-in
and a server change: a kept `yours` must never draw for another person.

Screen states (LibrarySection.tsx:246-281), drawn from `kept` and the last ask's failure:

| state | draws |
| --- | --- |
| no list, asking | spinner (accessibility "Loading") |
| no list, failed | errorNote(problem, retry: true) + button "Try again" (asks again) |
| list, a refresh failed | above the list: "Couldn't update this list - showing it as it was." + errorNote + "Try again" |
| `truncated` | "Showing the first 10000 albums - deadwax reads at most that many." |
| `yours` and 0 albums | EmptyLibrary: "Nothing in your library yet." / "Look through All music and add the albums you like, or find new ones in Search and Get them." / button "See All music" (opens All albums) |
| `store` and 0 albums | "No albums yet." |
| Find found none | `No albums match “<typed, trimmed>”.` (U+201C, U+201D) |

errorNote's sentences are lib/errorWords.ts's (the errors area's spec), with `retry: true`.

## 5. Folding: lib/owned.ts:50-61 `foldName`, lib/shelves.ts:312-321 `findText`

foldName, in this order (each a JS step on code points, `u` flag):
1. `String(name || '')` - nil, undefined, `""` -> `""`.
2. `.normalize('NFKD')` (compatibility decomposition: ligatures, fullwidth, superscripts, Roman numerals, Hangul).
3. `.replace(/\p{M}/gu, '')` - every Mn, Mc, Me scalar removed.
4. `.toLowerCase()` - full default mappings (SpecialCasing's unconditional ones) **and Final_Sigma**.
5. `.replace(/\s*[([][^)\]]*[)\]]/g, ' ')` - from an opener `(` or `[` to the FIRST `)` or `]` after it, either
   kind ("x (a] y" -> "x y"), as one space; an opener with no closer after it stays ("Album (unclosed" -> "album
   unclosed"). The leading `\s*` changes nothing once step 7 runs.
6. `.replace(/[’‘`´]/g, "'")` - no effect on the result (step 7 turns `'` into a space too).
7. `.replace(/&/g, ' and ')`, then `.replace(/[^\p{L}\p{N}]+/gu, ' ')` - every run of scalars outside L* and N*
   (Lu Ll Lt Lm Lo Nd Nl No) is one space.
8. `.trim()`, then `.replace(/^the /, '')` - only "the" followed by a space, once ("The The" -> "the", "The" -> "the",
   "Theatre" stays).

findText = the same without steps 5 and 8 (a bracketed aside and a leading "The" are words a person types).

**Collation - how the TS compares: never localeCompare.** `text(a, b) = a < b ? -1 : a > b ? 1 : 0`
(shelves.ts:128): **UTF-16 code-unit order** of the fold keys; equality is code-unit equality; Find is a code-unit
substring (`includes`). There are no locale rules, no numeric ordering ("10cc" < "2pac" because '1' < '2'), no
article handling but foldName's own "the ". Three Swift defaults would differ - each found by running both:

- `String.lowercased()` never makes a final sigma: "ΟΔΟΣ" -> "οδοσ", JS "οδος". Port Final_Sigma (below).
- `String <` and `==` compare canonically (NFC): NFKD Hangul is conjoining jamo (U+1100-11FF) in the JS key, which
  Swift compares as composed syllables (U+AC00+). JS sorts artist "방탄" before "一"; Swift's `<` the other way.
  And Swift orders U+FA0E before U+20000 (scalar order), JS after (a surrogate, D840, is below FA0E).
- `String.contains` matches whole Characters: "바" isn't found in "방탄" by Swift, is by JS.

So: keep each fold key as `[UInt16]` (`Array(key.utf16)`), compare with `lexicographicallyPrecedes`, and search
Find words as code-unit subsequences. Reference implementation (verified, 0 differences on 4,077 names):

```swift
public enum Fold {
    public static func key(_ name: String?) -> String { fold(name, comparing: true) }       // foldName
    public static func findText(_ name: String?) -> String { fold(name, comparing: false) } // findText

    static func fold(_ name: String?, comparing: Bool) -> String {
        var s: [Unicode.Scalar] = (name ?? "").decomposedStringWithCompatibilityMapping.unicodeScalars.filter { !isMark($0) }
        s = lowercased(s)
        if comparing { s = dropAsides(s) }
        var out = String.UnicodeScalarView()
        var spaced = false
        func gap() { if !spaced { out.append(" "); spaced = true } }
        for c in s {
            if c == "&" { gap(); out.append(contentsOf: "and".unicodeScalars); spaced = false; gap(); continue }
            if isLetterOrNumber(c) { out.append(c); spaced = false } else { gap() }
        }
        var t = Substring(String(out))
        while t.unicodeScalars.first == " " { t = Substring(t.unicodeScalars.dropFirst()) }
        while t.unicodeScalars.last == " " { t = Substring(t.unicodeScalars.dropLast()) }
        if comparing && t.unicodeScalars.starts(with: "the ".unicodeScalars) { t = Substring(t.unicodeScalars.dropFirst(4)) }
        return String(t)
    }
    static func isMark(_ c: Unicode.Scalar) -> Bool {
        switch c.properties.generalCategory { case .nonspacingMark, .spacingMark, .enclosingMark: return true; default: return false }
    }
    static func isLetterOrNumber(_ c: Unicode.Scalar) -> Bool {
        switch c.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .decimalNumber, .letterNumber, .otherNumber: return true
        default: return false
        }
    }
    /// JS toLowerCase: each scalar's full lowercase mapping; Σ (U+03A3) -> ς (U+03C2) where Final_Sigma holds:
    /// the nearest non-case-ignorable scalar before it is cased, and the nearest after it isn't (or there is none).
    static func lowercased(_ s: [Unicode.Scalar]) -> [Unicode.Scalar] {
        var out: [Unicode.Scalar] = []
        for (i, c) in s.enumerated() {
            if c.value == 0x03A3, cased(s, from: i - 1, step: -1), !cased(s, from: i + 1, step: 1) { out.append("\u{03C2}") }
            else { out.append(contentsOf: c.properties.lowercaseMapping.unicodeScalars) }
        }
        return out
    }
    static func cased(_ s: [Unicode.Scalar], from: Int, step: Int) -> Bool {
        var i = from
        while i >= 0 && i < s.count { let p = s[i].properties; if !p.isCaseIgnorable { return p.isCased }; i += step }
        return false
    }
    static func dropAsides(_ s: [Unicode.Scalar]) -> [Unicode.Scalar] {
        var out: [Unicode.Scalar] = []
        var i = 0
        while i < s.count {
            if s[i] == "(" || s[i] == "[", let close = s[(i + 1)...].firstIndex(where: { $0 == ")" || $0 == "]" }) {
                out.append(" "); i = close + 1
            } else { out.append(s[i]); i += 1 }
        }
        return out
    }
}
```

`decomposedStringWithCompatibilityMapping` is Foundation (swift-corelibs-foundation on Linux has it; the Linux job
proves it). Unicode-version drift between V8's ICU and Apple's/Linux's tables is possible for newly assigned
characters only.

Fold vectors (input -> foldName | findText | initial), all from shelves.js:

```
"The Beatles" -> "beatles" | "the beatles" | B          "Björk" -> "bjork" | "bjork" | B
"Simon & Garfunkel" -> "simon and garfunkel" | same | S   "Dummy (Deluxe Edition)" -> "dummy" | "dummy deluxe edition" | D
"AC/DC" -> "ac dc" | same | A                        "Guns N' Roses" -> "guns n roses" | same | G
"坂本龍一" -> "坂本龍一" | same | #                      "ΟΔΟΣ" -> "οδος" | same | #  (03BF 03B4 03BF 03C2)
"ΑΣ ΣΑ" -> "ας σα" (03B1 03C2 0020 03C3 03B1)         "ΟΔΟΣ’Α" -> "οδοσ α" (’ is case-ignorable: not final)
"İstanbul" -> "istanbul" | I                        "ﬁve" -> "five" | F        "Ｔｈｅ Ｂｅａｔｌｅｓ" -> "beatles" | "the beatles" | B
"½ Life" -> "1 2 life" | #     "x²" -> "x2" | X     "Ⅳ" -> "iv" | I     "ǅemal" -> "dzemal" | D     "Ⓐrt" -> "art" | A
"Æther" -> "æther" | #   "Øresund" -> "øresund" | #   "Łódź" -> "łodz" | #   "Đorđe" -> "đorđe" | #   (no decomposition)
"Straße" -> "straße" | S   "Ångström" -> "angstrom" | A   "ŉ" -> "ʼn" (02BC 006E, a letter) | #
"The The" -> "the" | "the the" | T     "The" -> "the" | T     "  the  beatles " -> "beatles" | "the beatles" | B
"Thé Band" -> "band" | "the band"      "The-Band" -> "band" | "the band"     "THE BEATLES" -> "beatles"   "the\tbeatles" -> "beatles"
"[Remastered] Album" -> "album" | "remastered album"    "Album (unclosed" -> "album unclosed" | same
"x (a] y" -> "x y" | "x a y"     "a (b) c (d) e" -> "a c e" | "a b c d e"     "Kid A [Deluxe] (2009)" -> "kid a" | "kid a deluxe 2009"
"Plaid & Co (Live)" -> "plaid and co" | "plaid and co live"     "Hello ‘World’" -> "hello world"     "$uicideboy$" -> "uicideboy"
"!!!" -> "" | #     "" -> "" | #     nil -> "" | #     "…And You Will Know Us" -> "and you will know us"     "🎵 Music" -> "music"
"방탄" -> jamo 1107 1161 11BC 1110 1161 11AB (displayed "방탄")
```

## 6. Dates: shelves.ts:74-78 `time()`, :199-212 `monthOf`/`monthLabel`

- Only a **string** is a date: `Date.parse(string)`; NaN, a number (the stand-in's float), absent -> nil.
- Keep times as **Int64 milliseconds since 1970** (JS numbers are integral ms here); every comparison is on them.
- Date.parse, for what Navidrome can send (verified against V8 on 3,031 strings, in UTC and New York):
  `YYYY`, `YYYY-MM`, `YYYY-MM-DD` (UTC midnight); `YYYY-MM-DD` then `T`, `t` or a space, then `HH:MM`, optional
  `:SS`, optional `.` + 1 or more digits (**truncated** to ms: ".9999" -> 999), then `Z`, `z`, `+HH:MM`, `-HH:MM`, or
  nothing = **local time** (TimeZone.current, as JS). Month 1-12, day 1-31 with overflow rolling on ("2026-02-30" =
  2 March, as V8), hour 0-24 (24 only as 24:00:00 = next midnight), minute and second 0-59; anything else nil
  ("2026-13-05", "14:60", "25:00", "31.Z", "31,5Z", "not a date", ""). Not ported: V8's legacy forms ("Mon, 05 Oct
  2026 14:22:31 GMT"), which Navidrome never sends.
- `monthOf(ms)`: `"<Month> <year>"` from the **UTC** month and year, English month names from the fixed table
  (`January` ... `December`), never a locale formatter; nil -> `DATE_UNKNOWN` = "Date unknown". Use the
  proleptic-Gregorian civil-from-days arithmetic, not Foundation's Calendar (Foundation's Gregorian is Julian before
  1582; "0001-01-01T00:00:00Z" - Go's zero time - must read "January 1").

Reference (verified):

```swift
public enum AlbumTime {
    public static func ms(_ text: String?, zone: TimeZone = .current) -> Int64? {
        guard let text else { return nil }
        let u = Array(text.utf8); var i = 0
        func digits(_ n: Int) -> Int? {
            guard i + n <= u.count else { return nil }
            var v = 0
            for k in 0..<n { let d = u[i + k]; guard d >= 48 && d <= 57 else { return nil }; v = v * 10 + Int(d - 48) }
            i += n; return v
        }
        func take(_ ch: UInt8) -> Bool { if i < u.count && u[i] == ch { i += 1; return true }; return false }
        guard let year = digits(4) else { return nil }
        var month = 1, day = 1, hour = 0, minute = 0, second = 0, millis = 0
        var offset: Int? = 0                                            // date-only forms are UTC
        if take(45) { guard let m = digits(2) else { return nil }; month = m          // "-"
            if take(45) { guard let d = digits(2) else { return nil }; day = d } }
        if i < u.count && (u[i] == 84 || u[i] == 116 || u[i] == 32) {               // "T" "t" " "
            i += 1; offset = nil                                        // a time with no zone is local
            guard let h = digits(2), take(58), let mi = digits(2) else { return nil }
            hour = h; minute = mi
            if take(58) { guard let se = digits(2) else { return nil }; second = se
                if take(46) {                                                         // "."
                    var count = 0
                    while i < u.count, u[i] >= 48, u[i] <= 57 { if count < 3 { millis = millis * 10 + Int(u[i] - 48) }; count += 1; i += 1 }
                    guard count > 0 else { return nil }
                    var scale = count; while scale < 3 { millis *= 10; scale += 1 }
                }
            }
            if i < u.count {
                if u[i] == 90 || u[i] == 122 { i += 1; offset = 0 }                    // "Z" "z"
                else if u[i] == 43 || u[i] == 45 {                                    // "+" "-"
                    let sign = u[i] == 45 ? -1 : 1; i += 1
                    guard let oh = digits(2), take(58), let om = digits(2) else { return nil }
                    offset = sign * (oh * 3600 + om * 60)
                }
            }
        }
        guard i == u.count, (1...12).contains(month), (1...31).contains(day), hour <= 24, minute <= 59, second <= 59,
              hour < 24 || (minute == 0 && second == 0 && millis == 0) else { return nil }
        let days = Int64(daysFromCivil(year, month, 1)) + Int64(day - 1)
        var ms = days * 86_400_000 + Int64(hour * 3_600_000 + minute * 60_000 + second * 1000 + millis)
        if let offset { ms -= Int64(offset) * 1000 }
        else { ms -= Int64(zone.secondsFromGMT(for: Date(timeIntervalSince1970: Double(ms) / 1000))) * 1000 }
        return ms
    }
    static func daysFromCivil(_ y0: Int, _ m: Int, _ d: Int) -> Int {          // Hinnant, proleptic Gregorian
        let y = m <= 2 ? y0 - 1 : y0
        let era = (y >= 0 ? y : y - 399) / 400, yoe = y - era * 400
        let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1
        return era * 146097 + yoe * 365 + yoe / 4 - yoe / 100 + doy - 719468
    }
    static func civil(_ ms: Int64) -> (year: Int, month: Int) {
        var days = ms / 86_400_000; if ms % 86_400_000 < 0 { days -= 1 }
        let z = Int(days) + 719468, era = (z >= 0 ? z : z - 146096) / 146097, doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100), mp = (5 * doy + 2) / 153
        let m = mp < 10 ? mp + 3 : mp - 9
        return (yoe + era * 400 + (m <= 2 ? 1 : 0), m)
    }
    static let months = ["January", "February", "March", "April", "May", "June", "July", "August", "September",
                         "October", "November", "December"]
    public static func month(_ ms: Int64?) -> String {
        guard let ms else { return "Date unknown" }
        let c = civil(ms); return "\(months[c.month - 1]) \(c.year)"
    }
}
```

(Of the strict forms only these differ from a "Z-only RFC 3339" parser; the extra forms cost nothing and are pinned.)

Vectors (ms, TZ=UTC; monthLabel): `2026-10-05T14:22:31Z` 1791210151000; `.1Z` +100; `.123456789Z` 1791210151123;
`.9999Z` 1791210151999; `+01:00` 1791206551000; `14:22:31.5-05:30` 1791229951500; `2026-10-05` 1791158400000;
`2026-10-05T14:22Z` 1791210120000; `2026-10-05 14:22:31Z` 1791210151000; `2026-10-05T14:22:31` 1791210151000 in UTC,
1791224551000 in New York; `2026` 1767225600000; `2026-10` 1790812800000; `2026-10-05T24:00:00Z` 1791244800000;
`2026-02-30T00:00:00Z` 1772409600000 (March 2026); `0001-01-01T00:00:00Z` -62135596800000 "January 1";
`1969-12-31T23:59:59.999Z` -1. nil: `2026-13-05T00:00:00Z`, `2026-10-05T14:60:00Z`, `2026-10-05T25:00:00Z`,
`2026-10-05T14:22:31.Z`, `2026-10-05T14:22:31,5Z`, `not a date`, `""`. shelves.sim's own: `monthLabel` of
`2026-10-31T23:30:00-05:00` = "November 2026", `2026-01-01T00:00:00Z` = "January 2026", `''`, undefined and
1729000000.5 = "Date unknown" ("a month from UTC, never the device's zone or language").

## 7. Keys, sorts, moments, headers (shelves.ts:28-265)

### Sorts offered (ALBUM_SORTS, :31-39 - ids are what a device saves; labels verbatim)

| id | label | Phase 1 |
| --- | --- | --- |
| `alphabeticalByArtist` | Artist | yes - **the default** (`DEFAULT_ALBUM_SORT`, :42) |
| `alphabeticalByName` | Title | yes |
| `newest` | Recently added | yes |
| `byYearDesc` | Year, newest first | yes (Open question 2) |
| `byYearAsc` | Year, oldest first | yes (Open question 2) |
| `recent` | Recently played | later (`played` set only; `played` desc) |
| `frequent` | Most played | later (`playCount > 0`; count desc, then `played` desc missing last) |

One choice per device for both scopes (the web: localStorage `deadwax-player-order`, persisted.ts:30; the phone:
UserDefaults, its own key). `albumSortFrom(saved)` (:49-51): a known id, anything else (nil, "", an old or mistyped
value, "starred", "random") -> `alphabeticalByArtist`. The picker's accessibility label "Album order"
(LibrarySection.tsx:298). Choosing a sort or typing into Find scrolls the screen back to its top (`backToTop`,
:152-154). The Recently added SECTION (the root's See all) has no picker: its sort is fixed `newest` (:219).

### Keys, once per album (`albumKeys`, :107-126; the sim counts 6,000 foldName calls for two sorts of 3,000)

Compute when an answer lands, never in a comparator: `artist = FoldKey(Fold.key(album.artist))`, `title =
FoldKey(Fold.key(album.name))`, `initial`, `titleInitial` (= `initialOf`), `year` = `album.year` if > 0 else nil,
`created = AlbumTime.ms(album.created)`, `starred = AlbumTime.ms(album.starred)` (and later `played`, `plays` = 
`playCount` if > 0 else 0). `FoldKey` holds `[UInt16]`; `<` is `lexicographicallyPrecedes`.

`initialOf(key)` (:69-72): the FIRST UTF-16 unit; `a`...`z` -> its capital; anything else, the empty key included,
`OTHER_INITIAL` = "#". (sim "initials": `beatles`->B, `zz`->Z, `10cc`->#, ``->#, `ß`->#, `坂本`->#.)

### Comparators (all end in the index the album had in the answer - Navidrome's order breaks every tie)

- `text(a,b)`: code-unit order (above). `byName(a, ai, b, bi)` (:130-131): an `#` initial after any letter, then
  `text` - so every `#` key (digits, symbols, other scripts, empty) sorts after Z, in code-unit order among themselves.
- `missingLast(a, b, descending)` (:133-134): nil after any value whichever the direction; two nils equal.
- **Artist**: byName(artist) -> missingLast(year, ascending) -> text(title) -> index.
- **Title**: byName(title) -> text(artist) -> index.
- **Recently added, `by: .collection`**: missingLast(created, descending) -> index. Never reads `starred`.
- **Year newest / oldest first**: missingLast(year, desc / asc) -> byName(artist) -> text(title) -> index.
- **Recently added, `by: .you`**: the moments, below.

Swift's `sorted(by:)` is not stable, but every comparator ends in the index, so the order is total and equals JS's.

### Moments (2.0.11, `moments()`, :153-170; `SAME_MOMENT_MS` = 30,000, :88)

`addedAt = starred ?? created` (:138-140).
1. Order all albums by addedAt descending, nil last, then index.
2. Walk them: an album joins the current moment if (its addedAt is nil and the moment's `at` is nil) or (both the
   PREVIOUS album's addedAt and its own exist and `previous - own <= 30_000`); else it starts a moment whose `at` is
   its addedAt (so `at` is the moment's NEWEST time). The gap is to the previous album, chained, not to the moment's
   first - a seed of thousands a second apart is one moment. A dated album after a nil? Impossible (nil sorts last).
3. Inside each moment: missingLast(created, desc) -> missingLast(addedAt, desc) -> index.
4. The sort is the moments in order, flattened.

Groups for `newest` + `.you` (`groupAlbums(sorted, sort, by, whole)`, :251-259, `addedMonthsOf` :232-242): each
album's header is `monthOf(its moment's at)`, the moments cut from **`whole`** (the sorted list BEFORE Find) - never
from what Find left (taking albums out of a run widens its gaps and would split a moment over a month's end). Albums
not in `whole` read "Date unknown". So one moment over a month's end is under one header, its newest star's month.

### Headers (`groupAlbums`, :251-265; `runs`, :215-224: consecutive equal keys are one group)

| sort | group key / label | order of groups |
| --- | --- | --- |
| Artist | `initial` / the same ("A"..."Z", "#") | letters then "#" |
| Title | `titleInitial` / same | same |
| Recently added, collection | `monthOf(created)` / same | newest month first, "Date unknown" last |
| Recently added, you | the moment's month (from `whole`) / same | same |
| Year either way | `String(year)` or "none" / `String(year)` or `NO_YEAR` = "No year" | the sort's direction, "No year" last |
| (played sorts) | one group, key "all", label nil | - |

An empty list has no groups (not one empty group). Headers are in the flow, not sticky (Shelf.tsx:65), each a
heading for VoiceOver (`.isHeader`). Group keys are contiguous for every sort above, but scroll to a header by its
group INDEX, not its key.

### Vectors (shelves.sim "the seven album sorts" / "the headers each sort groups by" - the ALBUMS fixture)

```json
[{"id":"abbey","name":"Abbey Road","artist":"The Beatles","year":1969,"created":"2026-09-02T10:00:00Z","played":"2026-10-01T10:00:00Z","playCount":3},
 {"id":"help","name":"Help!","artist":"The Beatles","year":1965,"created":"2026-10-05T10:00:00Z"},
 {"id":"tribute","name":"Tribute","artist":"Beatles Tribute","year":2001,"created":"2026-10-06T10:00:00Z","played":"2026-10-15T10:00:00Z","playCount":1},
 {"id":"debut","name":"Debut","artist":"Björk","year":1993,"created":"not a date"},
 {"id":"post","name":"Post","artist":"bjork","year":0,"created":"2026-10-06T11:00:00Z"},
 {"id":"cc","name":"Sheet Music","artist":"10cc","year":1974,"created":"2026-08-31T23:59:59Z","played":"2026-10-14T10:00:00Z","playCount":3},
 {"id":"pac","name":"Me Against the World","artist":"2Pac","created":"2026-10-07T10:00:00Z"},
 {"id":"sakamoto","name":"async","artist":"坂本龍一","year":2017},
 {"id":"nobody","name":"Untitled","artist":"","year":1999,"created":1729000000.5},
 {"id":"simon","name":"Bookends","artist":"Simon & Garfunkel","year":1968,"created":"2026-10-06T10:00:00Z","playCount":0},
 {"id":"debut2","name":"Debut","artist":"Björk","year":1993}]
```

- Artist: `help abbey tribute debut debut2 post simon nobody cc pac sakamoto`; heads `B 6, S 1, # 4`.
- Title: `abbey sakamoto simon debut debut2 help pac post cc tribute nobody`; heads `A 2, B 1, D 2, H 1, M 1, P 1, S 1, T 1, U 1`.
- Recently added (collection): `pac post tribute simon help abbey cc debut sakamoto nobody debut2`; heads
  `October 2026 5, September 2026 1, August 2026 1, Date unknown 4`.
- Year newest first: `sakamoto tribute nobody debut debut2 cc abbey simon help post pac`; heads `2017 1, 2001 1,
  1999 1, 1993 2, 1974 1, 1969 1, 1968 1, 1965 1, No year 2`.
- Year oldest first: `help simon abbey cc debut debut2 nobody tribute sakamoto post pac`; heads `1965 ... 2017`, then
  `No year 2`.
- (later) Recently played `tribute cc abbey`; Most played `cc abbey tribute` - both one group, label nil.
- "nothing left out or doubled ... the list handed in untouched": 11 and 11, the input's first still `abbey`.
- "no albums, no groups": `[]`.

shelves.sim "Recently added over YOUR albums" (`yours` fixture: late, tA, tB, amperfy, noStar, far, s3, s4, s2, s1,
none - copy it from ui/test/shelves.sim.cjs:110-123):
- `SAME_MOMENT_MS` == 30000.
- by `.you`: `late tB tA amperfy noStar far s3 s1 s2 s4 none`; the same list `.collection`:
  `amperfy noStar s3 s1 s2 tB tA late far s4 none`; Artist, Title, Year newest give the same order for either `by`.
- `.you` heads: `October 2026 4, September 2026 6, Date unknown 1`.
- `over` (m2 starred 09-01T00:00:05Z created 2025, m1 08-31T23:59:50Z created 2026-01-01, aug 08-20): heads
  `[September 2026: m1, m2], [August 2026: aug]`.
- `seed` (a 09-01T00:00:10Z, b 08-31T23:59:50Z, c 08-31T23:59:30Z, d 08-20; created 2025-01, 2026-03, 2026-06,
  2026-01-02): sorted `c b a d`; Find leaving out b, groups from the whole: `[September 2026: c, a], [August 2026: d]`
  (unfound: `[September 2026: c, b, a], [August 2026: d]`).
- `tied` (older/newer same created, stars 12:00:00/12:00:05; olderBare/newerBare no created, 11:59:50/11:59:55):
  `newer older newerBare olderBare`.
- `store` (c1 created 10-01 starred 10-20, c2 created 10-10, c3 created 09-01 starred 10-22): `.collection` (and the
  default) `c2 c1 c3`, heads `October 2026 2, September 2026 1`; as `.you` `c3 c1 c2`.
- whose.sim "your library: your starred albums, in the order chosen" (a The Slow Rush/Tame Impala 2020 created 10-01;
  b Dummy/Portishead 1994 10-10; c Third/Portishead 2008 09-01; d Abbey Road/The Beatles 1969 no created; none
  starred) with `.you`: Recently added `b a c d`, Artist `d b c a`, Title `d b a c`.
- Collation (new, from the JS): artists "방탄" then "一" (JS order; Swift's `<` would invert); artists "\u{20000}"
  then "\u{FA0E}".

## 8. Find (shelves.ts:305-368)

- `findWords(typed)` = `findText(typed)` split on " ", empties dropped. `finding(typed)` = any word (spaces alone are
  nothing).
- `filterAlbums(sorted, typed)`: no words -> everything; else the albums (in the sorted order) for which EVERY word
  is a code-unit substring of `findText(name) + " " + findText(artist)` (made once per album and kept - the web's
  WeakMap). Substring, not word start: "eat" finds "Beatles"; words in any order; "&" typed is "and".
- No debounce (measured fine at 3,000). The headers stay (computed from the found list, months from the whole); the
  index goes; the count reads `filteredCountText(found, sorted, "album", "albums")` = `"<found> of <total> albums"` -
  the plural chosen by the TOTAL ("1 of 1 album", "0 of 2 artists"); none found -> `noMatchText`.
- Placeholder and accessibility label "Find in albums" (LibrarySection.tsx:291). Clearing: the web's Escape; on iOS the
  field's clear button. Find is the screen's own state: leaving the screen (Back) clears it.
- Count without Find (`countText`, artistPage.ts:428-430): `"<n> albums"`, `"1 album"`, `"0 albums"`; `""` while no
  list.

Vectors (shelves.sim "Find", on ALBUMS sorted by Artist... the sim filters the unsorted fixture; order = input order):
"beatles road" -> [abbey]; "road BEATLES" -> [abbey]; "help" -> [help]; "beatles" -> [abbey, help, tribute];
"bjork" -> [debut, post, debut2]; "BJÖRK post" -> [post]; "simon and" -> [simon]; "&" -> [simon];
"deluxe" over + {dlx "Dummy (Deluxe Edition)" Portishead} -> [dlx]; "the beatles abbey" -> [abbey]; "" and "   " ->
all 11; `finding("  ")` false, `finding("a")` true. Words: `12 of 3012 albums`, `1 of 1 album`, `0 of 2 artists`,
`No albums match “dumy”.` (from " dumy "), `No artists match “x”.`. Collation: "바" finds "방탄소년단".

## 9. The index down the edge (shelves.ts:370-474; app/ShelfIndex.tsx)

- `indexKind(sort)` (:385-389): Artist and Title -> letters; Year either way -> decades; Recently added (and the
  played sorts) -> none.
- `showsIndex(sort, sortedCount, typed)` (:392-394): a kind, nothing found-typed, and `sortedCount >= INDEX_MIN` = 50
  (the count of the SORTED list, not the found one). Sim: (Artist,50,"") true; (Artist,49,"") false;
  (Artist,3000,"dum") false; (Artist,3000,"   ") true; (newest,3000,"") false; (byYearAsc,50,"") true.
- `indexEntries(groups, sort)` (:401-424). Letters: always all 27, "A"..."Z" then "#"; each jumps to the first group
  whose rank >= its own (rank: A=0 ... Z=25, "#"=26) - a letter with no group jumps to the NEXT group, past the last
  group to the last; accessibility "Jump to A", ..., "Jump to numbers and symbols". Decades: for each group whose
  label is an integer and not "No year", decade = floor(year / 10) * 10 as a string, one entry per run of the same
  decade, in the groups' order, jumping to the run's first group; accessibility "Jump to the 1990s". No groups -> no
  entries. Vectors: Artist groups [B, S, #] -> groups `0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,2,2,2,2,2,2,2,2`; a list
  all under Z -> every entry 0; Year newest -> `[2010, 0], [2000, 1], [1990, 2], [1970, 4], [1960, 5]`; oldest ->
  `1960 1970 1990 2000 2010`; none for newest/recent/frequent.
- `fitIndex(entries, slots)` (:435-449): all when `count <= max(1, slots)`; else `kept = max(2, (slots + 1) / 2)`
  entries at `round(n * (count - 1) / (kept - 1))` for n in 0..<kept (skip a repeat), a dot between two kept entries
  more than one apart. Vectors over the 27 letters: 13 -> `A•E•J•N•R•W•#`; 7 -> `A•J•R•#`; 3, 1 and 0 -> `A•#`; 27
  and 40 -> all 27.
- `entryAt(drawn, y, top, height)` (:458-474): nil if no slots or height <= 0; `place = (y - top) / height *
  slots`; slot = clamp(floor(place)); an entry's slot is that entry; a dot's slot spreads the entries it stands for
  over its own height: `before + 1 + min(between - 1, floor(clamp01(place - index) * between))`, `between = after -
  before - 1`. Sim: full strip (27 slots, top 100, height 270): y 100->0, 110->1, 120->2, 369->26, 9999->26, 0->0,
  106->0, 109.9->0, 115.5->1; `entryAt([], ...)` and height 0 -> nil; every drawn letter at 5%, 50%, 95% of its
  slot lands on itself for every slot count 1-27; a drag across A•E at 13 slots names B, C, D; a drag down the strip
  at 3, 7, 13, 18, 26 slots reaches all 27.
- The view (if built in Phase 1): an overlay on the trailing edge, as tall as the visible list; `slots =
  max(1, floor(height / 15))` (`--app-index-entry: 15px`, app.css:3444); a `DragGesture(minimumDistance: 0)` reading
  `entryAt` over the DRAWN slots' extent as it was when the touch began (the .59 reviews: never the strip's own box,
  and a press reads one strip throughout); jump on touch-down and on each change of entry, at most once a frame;
  `ScrollViewReader.scrollTo(groupIndex, anchor: .top)` with no animation. The index never scrolls the page itself.

Swift reference for the three (verified):

```swift
public struct IndexEntry: Equatable, Sendable { public let label: String; public let aria: String; public let group: Int }
public enum IndexSlot: Equatable, Sendable { case entry(IndexEntry, at: Int); case dot }
// letters: rank(label) = label == "#" ? 26 : (letters.firstIndex(of: label ?? "") ?? -1)
//          group = groupLabels.firstIndex { rank($0) >= at } ?? groupLabels.count - 1
// fit:     at = Int((Double(n * (count - 1)) / Double(kept - 1)).rounded(.toNearestOrAwayFromZero))
// entryAt: index = min(slots - 1, max(0, Int(place.rounded(.down)))); a dot with a non-entry neighbour returns the
//          entry neighbour's `at` (before first), else nil
```

**Not ported** (web-only machinery): `blocks`/`BLOCK_SIZE`/`blocksNear` and Shelf.tsx's estimates, observer and
jump re-alignment - a SwiftUI `LazyVGrid`/`LazyVStack` makes only what is near the view. Keep `Section` headers
unpinned.

## 10. The tiles, the rows, and the words

- **Grid** (the web's only album view): 2 columns on a phone (Shelf.tsx GUESS), each tile (AlbumTile.tsx:14-37): the
  cover (`coverArt`, `CoverSize.tile` 400; no `coverArt` or a failed load -> the empty square, never a broken image -
  Cover.tsx), the title (`name`), the artist; with `personal` the **New** mark (section 11). A tap opens the album
  page with this IndexAlbum as its preview (the header draws at once from `name`, `artist`, `artistId`, `coverArt`,
  `genre`, `year`, `musicBrainzId` - AlbumPage.tsx:265-286, 408-419). **Whose it is comes from the album's own answer
  (`/albums/{id}` `starred`), never the tile's `starred`** (AlbumPage.tsx:290-295, a review rule). Nothing in the
  Library plays (the web's gesture rule; the Library's Shuffle is Phase 4).
- **List** (new to the phone - the web left "a grid/list switch" out in .59): see Open question 3.
- Words, verbatim:

| where | words | source |
| --- | --- | --- |
| screen titles | "Your albums", "Albums" (logins off / break-glass), "All albums", "Recently added" | appFrame.ts:191-216 |
| the store's row and heading | "All albums" under "All music" | appFrame.ts:180-188 |
| Find | placeholder "Find in albums" | LibrarySection.tsx:291 |
| sort picker | "Album order"; the labels in section 7 | :298, shelves.ts:31-39 |
| count | "3012 albums", "1 album", "12 of 3012 albums" | artistPage.ts:428, shelves.ts:361 |
| headers | "A"..."Z", "#", "October 2026", "Date unknown", "1994", "No year" | shelves.ts |
| index | "Jump to" (the strip), "Jump to A", "Jump to numbers and symbols", "Jump to the 1990s" | shelves.ts:410, 421; ShelfIndex.tsx:167 |
| empty, yours | "Nothing in your library yet." / "Look through All music and add the albums you like, or find new ones in Search and Get them." / "See All music" | yourLibrary.ts:28-29, LibraryViews.tsx:17-29 |
| empty, store | "No albums yet." | yourLibrary.ts:35 |
| no match | `No albums match “dumy”.` | shelves.ts:366-368 |
| refresh failed | "Couldn't update this list - showing it as it was." + errorNote + "Try again" | LibrarySection.tsx:29 |
| capped | "Showing the first 10000 albums - deadwax reads at most that many." | :31 |
| loading | spinner, accessibility "Loading" | :266 |
| New | "New", read as "New in your library" | AlbumTile.tsx:30-34 |

## 11. New marks (optional - Open question 4)

With `personal` only (logins off: `GET /me/library` answers `{"on": false}` and nothing is drawn; break-glass:
`{"on": true, "library": false, "kept": false}`).
- Ask `GET /deadwax/me/library` as the Library tab shows (App.tsx:1282), and after Add/Remove. Only the newest answer
  counts; a failed ask keeps the last answer.
- `newMarks(answer)` (myLibrary.ts:164-172): ids = every `new[].navidrome_id` present; releases = every
  `new[].release_mbid` **lowercased**. `isNew(marks, album)` (:175-179): `marks.ids` has `album.id`, or
  `album.musicBrainzId` trimmed and lowercased is non-empty and in `marks.releases`.
- Opening an album (useMyLibrary.ts:83-99, `seenAlbum`): no answer yet -> remember it (the last 20 distinct by id,
  `OPENED_KEPT`) and look at each as the first answer lands; not new -> nothing; new -> drop from the kept answer's
  `new` every entry with `navidrome_id == album.id` or (release non-empty and `release_mbid` lowercased == release),
  redraw, and `POST /deadwax/me/library/seen` with `{"release_mbid": release}` when the album has one, else
  `{"album_ids": [those entries' album_id]}`; a failed POST is ignored (the mark is gone here; deadwax keeps it until
  the next open).
- Sim vectors (mylibrary.sim "the New marks: by Navidrome id, or by release whatever its case"; LIBRARY.new = entry 1
  Dummy {navidrome_id "nd-dummy", release_mbid "rel-1"}, entry 3 Third {navidrome_id null, release_mbid "rel-3"}):
  isNew {id nd-dummy} true; {id nd-x, musicBrainzId "REL-3"} true; {id nd-x, musicBrainzId "rel-4"} false; with no
  answer false. mylibrary.sim's useMyLibrary checks: "an album that isn't new: deadwax told nothing", "an album new in
  your library, opened: told by its release, its mark gone at once", "...one opened by the Navidrome id it was starred
  on, no release known: told by the store's ids", "an album opened before any answer: deadwax told nothing yet",
  "...and once the first answer lands it is looked at", "...and nothing at all with logins off". pytest:
  `test_your_library_says_what_waits_and_why_and_what_is_new` (`new` entries' navidrome_id may be null; /seen by
  release answers `{"cleared": 1}` and the entry leaves `new`).

## 12. Swift tests to write (DeadwaxCoreTests, Linux)

Mirror each by its sim/pytest name:
- **Fold**: the vector block in section 5 (each line a case), including Final_Sigma ("ΟΔΟΣ", "ΑΣ ΣΑ", "ΟΔΟΣ’Α"),
  Hangul as jamo, "x (a] y", "Album (unclosed", "The The".
- **Collation**: "방탄" before "一" and U+20000 before U+FA0E under Artist; "바" found in "방탄소년단"; "eat" finds
  "Beatles".
- **AlbumTime**: the section 6 vectors, with an injected `zone` for the local case; shelves.sim's monthLabel check.
- **Sorts/groups**: shelves.sim's "the seven album sorts" (the five), "the headers each sort groups by", "Recently
  added over YOUR albums" (all nine checks), whose.sim's four-album orders, "no albums, no groups", "a sort read from
  storage" (the four old ids kept, anything else Artist), "the sorts offered, in the select's order".
- **Decoding**: the ALBUMS fixture decodes (the float `created` -> nil -> "Date unknown"); `year: 0` -> No year;
  missing `artist` -> folds as `""` -> `#`; `{albums, truncated}` both required.
- **Find, index**: shelves.sim "Find" and "the index down the right edge" checks as listed in sections 8-9.
- **Store** (fake transport): one ask shared; a 304 keeps the list and renews `at`; If-None-Match sent only with an
  ETag held, exactly as received; a failed ask not kept and asked again; an older generation's late answer keeps
  nothing (once something is kept); refreshIfOld at 60 s and not while pending; forget after Add/Remove; cleared on
  sign-out; the scope picked from Me (logins off, break-glass -> store) - whose.sim's module checks listed above.
- Keep any mutation checks honest as Phase 0 did: break UTF-16 comparison (use `<`), Final_Sigma, `whole` (pass the
  found list), the 30 s chain (compare to the moment's first), `>= INDEX_MIN` -> `>`, and see each fail.

## Open questions

1. **The Library tab's top level.** The web phone has a root of rows (Playlists, Your albums, Your artists, All music
   > All albums / All artists / All songs, Recently added's 12 + See all); Phase 1 has only albums. *Recommend*: open
   the tab straight on the Albums screen ("Your albums" / "Albums"), with - for `personal` only - an "All albums" row
   at its top (the web's words, under an "All music" heading) pushing the store's screen; the root of rows arrives in
   Phase 4 with Artists, Songs and Playlists. Recently added stays a sort, not a second screen.
2. **"Year": one entry or two?** The plan says four sorts; the web's Year is two (newest first / oldest first), one
   comparator with a flag. *Recommend*: offer five - the web's labels verbatim - so a device's choice means the same in
   both apps; keep the web's ids so Phase 4 can add Recently played and Most played without migrating.
3. **The list view** (the web has none). *Recommend*: a per-device toggle beside the sort (default grid); a row = the
   cover at `CoverSize.row` 128, the title, and the artist on the second line, with the same headers, Find, index and
   New mark as the grid. Year in the row only under the Year sorts? *Recommend* no - the header already says it.
4. **New marks in Phase 1?** They need `GET /me/library` (which Add/Remove's area wants for its count anyway) and
   one POST on album open. *Recommend*: yes - about 60 lines of Core with the sim's vectors, and without them a
   person's newly added albums look the same on the phone and marked on the web.
5. **Keep the last list across launches?** The web keeps nothing across reloads (.59 left out "a snapshot across
   launches"); the phone's plan wants the Library from a database offline (Phase 2). *Recommend*: in Phase 1 write the
   last 200 answer's bytes and ETag per (server, user, scope) to Application Support/deadwax/<server-key>/, draw it
   at launch, and ask with its ETag - a 304 then costs one small round trip; Phase 2's database replaces the file.
6. **The 30 s timeout for /album_index** - James's library size is recorded nowhere (notes/app-library.md "Not
   verified"). *Recommend*: 30 s for this request only, and Debug shows the last answer's time and size, so check 1
   ("count them against the web app's Library") also measures it.
7. **The index in Phase 1** ("if cheap"): the pure part is ported and verified above; the view is a DragGesture strip
   plus ScrollViewReader. *Recommend*: build it - letters for Artist/Title, decades for Year, only at 50 albums or more
   and not while finding - and check on the phone that `scrollTo` in a LazyVGrid lands the header under the bar.
