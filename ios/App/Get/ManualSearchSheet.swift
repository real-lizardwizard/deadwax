import DeadwaxCore
import SwiftUI

/// Search Soulseek (manual search, slice A1 - notes/ios.md "Manual search, slice A1"; the design is
/// ~/Desktop/Code/deadwax-plans/manual-search.md 3.1 and 3.3): the sheet Requests' first row opens. James, 24 Nov:
/// "let's add a manual search in the requests tab" - Soulseek by artist and album, for an album MusicBrainz doesn't have
/// or one you'd rather find by name.
///
/// - THE FORM: Artist and Album, words capitalised and nothing autocorrected; Artist has the cursor as the sheet opens.
///   Return in Artist goes to Album, Return in Album searches - and never anything else; on the Mac, Tab and Shift-Tab
///   go between the two (Platform's `tabs`, the Mac app's slice 7). Search, under them, is on once both have words.
/// - SEARCH pushes Choose a source - the very page an album's Get opens (SourcesPage, `pushed`), a new search for each
///   Search: the folders found ranked by how closely their names fit the words, then by format and availability; no
///   Complete albums only, nothing picked for you; Search again as there. Back returns to the form with the words as you
///   left them, and lets that search go as the page goes.
/// - GET is any card's Get: the download asked for in the tap, its row in Requests at once ("OK Computer · manual
///   search"), and the whole sheet goes - Requests is already showing.
/// - OUT OF REACH: "Getting albums works once deadwax is back." over the fields, and Search off; the results page is as
///   an album's (its cards dimmed, its Gets off).
/// - Cancel, a swipe let go, or a Get lets the search on the results go. Escape is Cancel (the Mac app, slice 2) only
///   with nothing typed: Cancel throws the words away without asking.
/// - (The redesign, slice R1c's review - notes/ios.md "The redesign, slice R1c: the phone is flat (2026-11-25)") THE
///   LOOK: flat, on the page's black - no Form, so no grey cells - with the two fields the look's boxes (DWWellField:
///   iRequests' `.in`s, square, 8 apart, each prompt in the third colour), the footer under them in the second colour
///   and the purple Search under that, as before. iRequests draws the fields inline at the top of Requests, beside a
///   flat Search; here they stay in the sheet its Search Soulseek… row opens (A1's), with the behaviour above.
struct ManualSearchSheet: View {
    /// A download asked for from the results: the sheet goes - Requests is already showing.
    let onQueued: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(Reachability.self) private var reachability
    @State private var artist = ""
    @State private var album = ""
    /// The search the results page shows - a new one for each Search - and whether it is pushed.
    @State private var results: GetRequest?
    @State private var showing = false
    @State private var searches = 0
    /// Artist has had the cursor once, as the sheet opened: Back from the results leaves the keyboard down.
    @State private var opened = false
    @FocusState private var focused: Field?

    private enum Field: Hashable { case artist, album }

    /// (The Mac app, slice 7) The fields in the order the sheet draws them: Tab's on the Mac.
    private static let order: [Field] = [.artist, .album]

    private var online: Bool { reachability.online }

    /// Search is on: deadwax in reach, and both fields with words.
    private var searchable: Bool { online && ManualSearch.canSearch(artist: artist, album: album) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !online {
                        // nothing can be searched until deadwax is back
                        ShelfNote(ManualSearch.offline)
                            .padding(.bottom, 12)
                    }
                    // (R1c's review) the look's boxes, iRequests' two `.in`s 8 apart - each field's focus still the
                    // sheet's own (`focused`), as A1 made it; DWWellField reads it for the edge
                    VStack(spacing: 8) {
                        TextField(ManualSearch.artistField, text: $artist,
                                  prompt: Text(ManualSearch.artistField).foregroundStyle(DWPalette.t3))
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .submitLabel(.next)
                            .focused($focused, equals: .artist)
                            .tabs($focused, in: Self.order)
                            .onSubmit { focused = .album }
                            .accessibilityLabel(ManualSearch.artistField)
                            .task {
                                // the cursor once it is drawn (a focus asked before the field exists is lost), only as
                                // the sheet opens
                                guard !opened else { return }
                                opened = true
                                focused = .artist
                            }
                            .modifier(DWWellField(focus: $focused, field: .artist))
                        TextField(ManualSearch.albumField, text: $album,
                                  prompt: Text(ManualSearch.albumField).foregroundStyle(DWPalette.t3))
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                            .focused($focused, equals: .album)
                            .tabs($focused, in: Self.order)
                            .onSubmit { search() }
                            .accessibilityLabel(ManualSearch.albumField)
                            .modifier(DWWellField(focus: $focused, field: .album))
                    }
                    // what the Form's footer said, under the fields on the page
                    Text(ManualSearch.footer)
                        .font(Typeface.Phone.text(.small))
                        .foregroundStyle(DWPalette.t2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                    // (the panel review's R19) the look's primary, large and across the page, where PrimaryFace was
                    Button(ManualSearch.search, action: search)
                        .buttonStyle(DWButtonStyle(kind: .pri, size: .large, fills: true))
                        .disabled(!searchable)
                        .padding(.top, 20)
                }
                // the page's sides, 16 (.f's padding 0 16px)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            // (R1c's review) the page's black, under the bar too: no sheet's grey behind it
            .background(DWPalette.page.ignoresSafeArea())
            // the sheet going for good - a swipe let go, Cancel, a Get: the results' search goes with it, there and then
            .background(SheetGoing { results?.search.close() })
            .navigationTitle(ManualSearch.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(SourcesWords.cancel) {
                        results?.search.close()
                        dismiss()
                    }
                    // (the Mac app, slice 2) Escape is Cancel only with nothing typed: Cancel throws the words away
                    // without asking
                    .escapeCloses(artist.isEmpty && album.isEmpty)
                }
            }
            .navigationDestination(isPresented: $showing) {
                if let results {
                    SourcesPage(request: results, pushed: true) {
                        queued(results)
                    }
                }
            }
        }
        // Back from the results lets their search go in the page's own onDisappear (SourcesPage), once the pop is done -
        // never as a back-swipe starts, which could be let go and cancelled, leaving the page up with its search shut
        // (slice A1's review). And however the sheet went, the search goes with it:
        .onDisappear { results?.search.close() }
        // (R1c's review) the sheet's own ground the page's black, as the Now Playing sheet's is its own
        .presentationBackground(DWPalette.page)
    }

    /// Search, from the button or Return in Album: the words as typed, a new search on a page of its own. Nothing while
    /// a field is blank or deadwax is out of reach, or with the results already up.
    private func search() {
        guard searchable, !showing else { return }
        focused = nil
        results?.search.close()
        searches += 1
        results = GetRequest(id: searches, release: GetRelease.manual(artist: artist, album: album),
                             subtitle: ManualSearch.subtitle, search: SourcesSearch())
        showing = true
    }

    /// A card's Get on the results: the sheet goes, only while it still shows the search that asked.
    private func queued(_ request: GetRequest) {
        guard showing, results?.id == request.id else { return }
        onQueued()
    }
}
