# Phase 7 - Managing: deadwax's tools opened in the web app, from You (app 0.13)

Design spec for the iPhone app's Phase 7, the last of the plan, read 2026-11-15 at `ios` 8f2d52f (app 0.12 (12), server
2.1.26). Area: You > **Manage** - the managing tools the person may use, each opened **in the web app, in Safari**: the
editors, Needs a look, Library care, People, Server settings and the event log - and the three other ways out to them
the phone already has or needs (an album's •••, Account's Change password, the Library's Set up Navidrome). Every path
is repo-relative and every line number is the code's at 8f2d52f.

**What binds it.** The plan (`~/Desktop/Code/deadwax-ios-plan.md`, outside the repo), section 5's "Phase 7 - Managing":
"You → Managing lists what the person may do (by permission, from `/me`) and **opens it in the web app** in Safari: the
editors, Needs a look, Library care, Settings and the log, People. These are admin tools, used rarely, and each is a
large panel already built and tested on the web. Rebuilding them natively is a choice for later, one at a time if ever
(Choice 17)." Its check: "each row opens the right page in Safari". James's answers at the plan's top (a free account,
no Simulator, plain http on his LAN and WireGuard); section 2's routes table ("Managing (admin) | links out to
`/player/` in Safari"); section 4's offline rule ("Search, Get, Requests and managing say they need deadwax, and show
nothing stale as if live"). **Nothing is rebuilt natively, and no route is added**: every tool is a page the web app
already has, and the permissions come from the `/deadwax/me` the app already reads.

**Where the rules come from.** `ui/src/lib/permissions.ts` (`managing`, `albumEdit`, `LABELS`), `ui/src/app/access.ts`
(`accessOf`, `seesDetail` - already ported as Core's `Access`), `ui/src/lib/appRoutes.ts` (`formatRoute`, `parseHash`,
the Managing pages' ids and labels), `ui/src/app/You.tsx` (the Manage section: its title, its rows in order, each by its
part of `managing`), `ui/src/lib/ownPassword.ts` (`changeOffered`, `CHANGE_TITLE`); `notes/app.md` ("The one app": the
address is the hash; a cold deep link), `notes/app-desktop.md` ("Looking after deadwax from a phone": every Managing
page on a phone's frame), `notes/logins.md` ("Managing accounts": People, the permissions table). Held to the
TypeScript by a committed exporter (section 6).

## 0. The foundation - checked

- **The branch.** `phase7-managing`, from `ios` 8f2d52f, clean. `src/__init__.py` says `2.1.26`; `ios/Config/
  Base.xcconfig:11-12` say 0.12 and 12. This phase makes the app **0.13 (13)**, pinned with check_project.py, ios.yml,
  tests/test_ios_install.py, ios/README.md and docs/ios.md as 0.3 to 0.12 were. `__version__` is never changed here.
- **Every tool is a page of the web app's, on a phone's frame.** Since 2.0.0-player.47 Needs a look, Library care,
  Server settings, the event log - and since .61 People - are drawn on a phone exactly as on a desktop
  (`notes/app-desktop.md`, "Looking after deadwax from a phone"), and the album page's Edit is a chip in its bar there.
  Safari on an iPhone is that frame. Every one is in deadwax 2.0.0, the oldest the app talks to.
- **The address is the hash** (`appRoutes.ts:5-60`): StaticFiles has no fallback for page routes, so the web app is
  `/player/` and its route follows the `#`. A cold deep link opens its page straight away - `startNav` puts the page on
  its tab's root (`appRoutes.ts:259`), Back then lands on the tab - and `parseHash(formatRoute(page))` gives back that
  page with the same address (no rewrite). `/` answers a 307 to `/player/`, so the phone goes to `/player/` itself.
- **Signed out, the deep link still lands.** With logins on and no session in Safari, `signInGate.tsx` draws the sign-in
  screen alone, leaving the address as it is; once someone signs in it draws the app (`render(<App />)`), whose history
  starts from `location.hash` (`appHistory.ts:133`) - the page the row named. A query is nobody's instruction there
  (`signInGate.tsx`), so nothing is put after a `?`.
- **Each page refuses for itself.** Without its permission a Managing page draws `NO_PERMISSION` ("This page needs a
  permission an admin hasn't given you - ask one if you need it.") and asks nothing; People draws `PEOPLE_ONLY`; every
  route is the server's to refuse (`require(permission)`, `tests/test_logins.py`). So a row shown a moment too long
  (an admin took the permission away since /me last answered) opens a page that says why - nothing the phone shows is
  trusted.
- **The base.** `ServerAddress.base` is `scheme://host:port` with no path (a pasted `…/player/` link is the same
  server): deadwax's routes are absolute, and so is the web app, at `base + /player/`. The Library's **Set up
  Navidrome** has opened `base + /player/` in Safari since Phase 1 (`NavidromeGate.setUpURL`, D8: "Phase 7 brings the
  phone's links into it").

## 1. The rows, their permissions and addresses

You > **Manage** (the web's section title, `You.tsx:371` `app-managing-title`), between Downloads and Account (the web's
Manage comes before its Account), drawn only when it has a row. With logins off everyone is the admin (`Access(me:)`:
every permission), so everyone has every row but People.

| row | shown when (the web's rule) | opens (`base` + …) | straight to it? |
| --- | --- | --- | --- |
| **Edit an album** | Edit albums or Look after the library (`albumEdit(perms).shown`) | `/player/#/library` | no - the Edit panel opens only from a tap on an album's page (its chip); the Library is the nearest page that reaches it. Under the row: "Opens the web app's Library: open an album there, then Edit. An album's ••• here has Edit in the web app too." |
| **Needs a look** | Look after the library (`managing.queue`) | `/player/#/you/queue/all` | yes |
| **Library care** | Look after the library or Edit albums (`managing.care`) | `/player/#/you/care/library` | yes |
| **People** | People, with logins on (`managing.people`) | `/player/#/you/people/all` | yes (it opens locked: Unlock with your own password, as on the web) |
| **Server settings** | Settings and the log (`managing.settings`) | `/player/#/you/settings/server` | yes (at its first tab, Library: the tab is kept per page, not in the address) |
| **Event log** | Settings and the log (`managing.log`) | `/player/#/you/log/all` | yes |

The five after the first are the web's own rows, in the web's order, with the web's words (`You.tsx`); the first is the
phone's own, since the web's editors live on an album's page, not in You. A Navidrome admin has `people` and every
other permission; break-glass (`deadwax`) has them all and its People page says why it can't change accounts.

**The other ways out** (the same rule, the same base):

| where | shown when | opens |
| --- | --- | --- |
| an album's page, the bar's ••• - **Edit in the web app**, in its own section after the download items | Edit albums or Look after the library, deadwax in reach, the album still in the collection | `/player/#/library/album/<id>` - Navidrome's album id, `encodeURIComponent`'d as `formatRoute` does: the same album's page in the web app, its Edit chip one tap away |
| You > Account - **Change password**, above Sign out (the web's Account's order) | `changeOffered` (logins on, a Navidrome sign-in - never break-glass) | `/player/#/you` - the web's You, where Change password is under Account. Under the row: "Opens the web app's You: Change password is under Account there." |
| the Library's **Set up Navidrome** (an admin's, Navidrome not set up) | as before (NavidromeGate) | `/player/#/you/settings/server` - Server settings, where the gate's own line already says to go ("Set it up in Server settings (Connections), then come back."); the web's own button opens the page at Connections, which no address can say |

## 2. Words

The web's (held by the exporter): **Manage**; **Needs a look**, **Library care**, **People**, **Server settings**,
**Event log** (You.tsx's rows, and appRoutes.ts's page labels, which are the same words); **Change password**
(`CHANGE_TITLE`).

The phone's own (nothing on the web opens anything in Safari):

| where | words |
| --- | --- |
| the first row | **Edit an album**; under it "Opens the web app's Library: open an album there, then Edit. An album's ••• here has Edit in the web app too." |
| the album's ••• | **Edit in the web app** (symbol `safari`) |
| Manage's footer | "These open in the web app, in Safari." - and with logins on: "Safari has its own sign-in, apart from the app's: the first time, sign in there with the same name and password you use here." |
| Manage, deadwax out of reach | "These open once deadwax is back." in the footer's first sentence's place; every row dimmed (`Palette.off`) and off |
| Change password | under it "Opens the web app's You: Change password is under Account there." |
| VoiceOver, every row out | the hint "Opens in Safari." |

## 3. Signing in, in Safari

**Safari has its own sign-in, apart from the app's.** The app keeps its session cookie in its Keychain and sends it
itself (`httpShouldSetCookies` off, notes/ios.md Phase 0); Safari keeps its own cookies. Nothing hands one to the other,
on purpose:

- The only way to give Safari the app's session would be to put it in the address, and a session in a URL is a password
  in Safari's history, its tab list and any proxy's log (the standing privacy rule: nothing secret in a URL). The web
  sign-in takes no token from the address either - a query is nobody's instruction there.
- So the first time a row opens in Safari, with logins on, the web app's sign-in screen comes first, over the address
  the row named. The person signs in with the **same name and password they use in the app** (their Navidrome name and
  password; break-glass's `deadwax` and its password for break-glass), and the page the row named then opens - the
  sign-in keeps the address. After that Safari stays signed in on its own, as any browser does with deadwax: the
  session lasts 30 days from its last use, so a tool opened less often than monthly asks again. Signing out of the app
  doesn't sign Safari out, nor the other way round. With logins off there is no sign-in anywhere.
- **The web app on the Home Screen** (Add to Home Screen, docs/player.md) keeps its own sign-in too - a Home Screen web
  app's cookies are its own, apart from Safari's - and links from the app open in Safari, never in it. So someone who
  uses the web app from their Home Screen signs in once more, in Safari.
- **The cookie's SameSite=Strict** doesn't get in the way: the page itself (`/player/`, static) needs no cookie, and
  every request it makes is to its own site, which a Strict cookie goes with. Read from the cookie's rules, not watched
  in Safari: check 239 is the proof.

The footer says it in a listener's words (section 2): "Safari has its own sign-in, apart from the app's: the first time,
sign in there with the same name and password you use here."

## 4. Plain http, ATS and the local network

James opens deadwax at a plain `http://` address on his network, and over WireGuard on the phone.

- **ATS doesn't come into it.** App Transport Security governs the app's own loading (URLSession, a web view in the
  app); a URL handed to `openURL` is Safari's to load, by Safari's rules. Safari opens `http://` pages (its address bar
  says Not Secure). The app's `NSAllowsArbitraryLoads` stays as it is for the app's own requests, and nothing is added
  to Info.plist: `LSApplicationQueriesSchemes` is only for `canOpenURL` on other schemes, and http/https need no
  entry.
- **Safari's own settings.** If Safari is set to warn before a page that isn't secure, it warns here too, as it would
  for the address typed. Safari's automatic upgrade to https applies to sites it knows have it; a LAN address or a name
  over WireGuard isn't one, so the address stays http. Neither seen from here: check 240.
- **Local Network.** The app's own Local Network permission is the app's; Safari reaches addresses on the Wi-Fi's own
  network without asking (it isn't among the apps iOS asks about). Over WireGuard the tunnel is the phone's, so Safari
  goes through it as the app does. Believed, not seen: check 240.
- **The default browser.** `openURL` opens a web address in the phone's default browser, which is Safari unless it has
  been changed. The words say Safari (question 9).

## 5. Offline, no address, and what the rows read

- **Out of reach** (`Reachability.online` false): Manage's rows are drawn dimmed and off, "These open once deadwax is
  back." in the footer, nothing opened - Safari would only fail at the same address. The album's ••• has no Edit in the
  web app, as it has no Add to a playlist then; Change password is off, the offline banner saying why. Back in reach,
  all of it is live at once.
- **No server address**: there is no You to draw (RootView's first gate is the Server address screen). Core's addresses
  are nil without one, and a row with no address isn't drawn.
- **What the rows read**: `ServerModel.access` - the last /me (kept on the phone, asked again as You first shows and on
  a pull, as before). Nothing new is asked: the rows are links, and the page each opens asks deadwax itself.

## 6. Machinery

| Core (DeadwaxCore, pure, tested on Linux) | App (SwiftUI) |
| --- | --- |
| `Managing.swift`: `Managing.Parts` and `parts(_:loginsOn:)` (permissions.ts `managing`), `AlbumEdit` and `albumEdit(_:)`, `Tool` (the six rows, in You's order) and `tools(_:)`, `changeOffered(_:)` (ownPassword.ts), the addresses - `fragment(_:)` (formatRoute's), `url(_:at:)`, `albumURL(id:at:)`, `youURL(at:)` - and `ManagingWords` | `You/ManageSection.swift`: the section, its rows and footer, offline; `YouView` draws it between Downloads and Account; `AccountSection` gains Change password; `QueueMenuRequest.webEdit` and its section in `QueueMenu`, set by `AlbumView`'s bar •••; `NavidromeGate.setUpURL` on Server settings' address |

Every link opens with SwiftUI's `openURL` (the environment's action), which hands it to the default browser - never a web
view in the app (question 1).

**Held to the web.** `ios/scripts/export-managing-vectors.cjs` compiles `lib/permissions.ts`, `lib/appRoutes.ts`,
`lib/ownPassword.ts` and `app/access.ts` with the repo's TypeScript (Preact stubbed, as export-gate-vectors.cjs does)
and reads You.tsx's Manage section out of its source (its title, and its rows in order, each with the part of
`managing` that draws it); writes `ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/managing/managing-vectors.json`;
`ui/test/iosmanaging.sim.cjs` runs it with `--check`; `ManagingVectorTests` replays it:

- `managing` for every one of the 64 sets of permissions, logins on and off, and `albumEdit` for each;
- a run of /me answers (logins off, a Navidrome admin, break-glass, ordinary people with one or more permissions, an
  answer from before permissions, names it doesn't know) through `accessOf`, then `managing`, `albumEdit`, `seesDetail`
  and `changeOffered`;
- the addresses: every Managing page as You opens it (`formatRoute({tab: 'you', page})`), the Library's and You's roots,
  and an album's for ids from the plain to the awkward (a slash, `%`, `#`, `?`, a space, an accent, an emoji) - each with
  what `parseHash` makes of it, so the vectors also say each opens as itself, unrewritten;
- the words: the section title, the rows' labels, the pages' labels, `CHANGE_TITLE`.

By hand (`ManagingTests`): the URLs on every kind of base (an IP, a name, https, a port, IPv6 with a zone), nil without
an address, the phone's own row first and the rest in the web's order, the album's Edit gating, the gate's new address.

## 7. Dynamic Type and VoiceOver

- Each row is a Button whose label is the row's words (wrapping, never cut: `fixedSize(horizontal: false, vertical:
  true)`), with `arrow.up.forward` at the trailing edge in the quiet colour - an iOS sign for "opens elsewhere", where
  the app's other rows have a chevron for a page pushed. The symbol scales with the text (`Typeface.symbol(.body)`) and
  is hidden from VoiceOver. The two rows with a line under them draw it in `Typeface.footnote`, quiet, under the label.
- VoiceOver reads each row as one button: its label (and its line), then the hint "Opens in Safari."; dimmed rows
  read as dimmed (`.disabled`). The footer is read after the rows, as every section's.
- At the largest sizes the rows grow with their words; nothing is a fixed height. `Typeface` and `Palette` only
  (tests/test_ios_palette.py): the section's header and footer in `Typeface.footnote`.

## 8. James's checks (237 on)

Numbered after 236 (193-199 and 200-236 are taken). Written out in docs/ios.md ("Managing's checks (237-246)"):
the version; each row opening the right page (the plan's); the first sign-in in Safari and the second time straight
through; plain http and the network; each row by permission; the album's Edit in the web app; Change password; Set up
Navidrome; offline; the largest text and VoiceOver.

## 9. What only the phone can tell

- That Safari opens each address on the page it names, over plain http and WireGuard, with no warning James didn't ask
  for - and whether Safari opens a new tab each time or goes back to one it has.
- That the first sign-in in Safari lands on the page the row named, and the second time goes straight there (the
  SameSite reading in section 3).
- That Safari asks nothing about the local network.
- The rows at the largest text sizes, and VoiceOver's reading of them ("Opens in Safari." as a hint, after the label).

## 10. Open questions, each with the recommendation built

1. **Safari, or a web view in the app?** *Recommend, and built:* Safari, through `openURL`. It is James's decision, and
   it keeps the web app's own player out of the app: the web app is a player as well, and inside the app its audio
   would sit beside the native engine's. An in-app Safari view (SFSafariViewController) would keep its own cookies
   anyway - a third sign-in, apart from both.
2. **The section's name.** *Recommend, and built:* the web's **Manage** (the plan's "Managing" is its description).
3. **The editors have no address.** *Recommend, and built:* You's **Edit an album** opens the web app's Library, the
   nearest page that reaches them, saying so under the row; and the album page's ••• gains **Edit in the web app**,
   opening that album's page there, the Edit chip one tap away. A web change to open the Edit panel from the address
   would be main's, not this branch's, and isn't needed for one tap.
4. **The artist page's managing** (Artist images…, Move albums to …, Which artist is this?). *Recommend, and built:*
   not linked from the phone's artist page. They aren't in the plan's list; the web app's Library reaches the artist's
   page, and the editors' row opens it.
5. **Needs a look's count**, which the web's row carries. *Recommend, and built:* not shown. It would be the phone's
   first ask of `/library/queue/summary` (a route deadwax has; Look after the library's), as You shows - for a row that
   only opens a page that counts them itself.
6. **Connections** (whether deadwax reaches slskd, MusicBrainz and Navidrome - phase6-get-requests.md question 2 left
   it to this phase). *Recommend, and built:* not a row. It is part of the web's You with no address of its own, and a
   link could only land at the top of that page, several sections above it; whoever runs deadwax has the event log and
   Server settings here, and Requests already says slskd's troubles in words. If it is wanted on the phone, it is three
   read-only rows from routes deadwax has - a native change of its own later, not a link.
7. **Changing your own password.** *Recommend, and built:* a **Change password** row in Account (with logins on, not for
   break-glass - the web's `changeOffered`), opening the web app's You, the line under it saying where it is. It is the
   other thing docs/ios.md's "What it can't do yet" lists beside managing, and a listener's as much as an admin's.
8. **Set up Navidrome.** *Recommend, and built:* it opens Server settings now (`#/you/settings/server`), not the web
   app's Home: the gate's line already says Server settings (Connections). The tab Connections can't be named in an
   address, so it opens at the first tab.
9. **"Safari" in the words**, though `openURL` opens the default browser. *Recommend, and built:* keep "Safari" - it is
   what an iPhone has unless changed, and what the plan says; someone who changed it knows why it opened elsewhere.
10. **Offline.** *Recommend, and built:* the rows drawn dimmed and off, with "These open once deadwax is back." - the
    plan's "managing say they need deadwax" - rather than hidden (the person sees what they'll have back) or live
    (Safari would only fail at the same address).
11. **Handing the app's session to Safari.** *Recommend, and built:* never. It could only go in the address (section 3).
    Safari signs in once.

## Built

See notes/ios.md, "Phase 7: Managing". The app is **0.13 (13)**; no route added (ROUTE_COUNT stays 60), no server change.
