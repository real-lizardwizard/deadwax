import Foundation

/// The Albums screen's words, verbatim from the web app (lib/appFrame.ts, app/LibrarySection.tsx,
/// lib/yourLibrary.ts, app/LibraryViews.tsx, app/AlbumTile.tsx), and what its body draws.
public enum LibraryWords {
    /// The heading over the collection's views, with a library of your own (ALL_MUSIC).
    public static let allMusic = "All music"
    /// The store's row under it, and its screen's title.
    public static let allAlbums = "All albums"
    public static let recentlyAdded = "Recently added"

    /// The Albums screen's title (libraryTitle): "Your albums" with a library of your own, else "Albums"; the
    /// store's list with a library of your own is "All albums".
    public static func title(_ scope: AlbumScope, personal: Bool) -> String {
        guard personal else { return "Albums" }
        return scope == .yours ? "Your albums" : allAlbums
    }

    /// Find's placeholder and accessibility label.
    public static let findPlaceholder = "Find in albums"
    /// The sort picker's accessibility label.
    public static let sortLabel = "Album order"
    /// The spinner's accessibility label.
    public static let loading = "Loading"
    public static let tryAgain = "Try again"
    /// Above a list that couldn't be refreshed - the list stays drawn (COULDNT_REFRESH), over the error's words.
    public static let couldntRefresh = "Couldn't update this list - showing it as it was."
    /// Above a list cut at the route's cap (TRUNCATED_NOTICE).
    public static let truncated = "Showing the first 10000 albums - deadwax reads at most that many."
    /// Your library empty (EMPTY_LIBRARY, EMPTY_LIBRARY_HOW), and the button to the store's albums.
    public static let emptyLibrary = "Nothing in your library yet."
    public static let emptyLibraryHow = "Look through All music and add the albums you like, or find new ones in Search and Get them."
    public static let seeAllMusic = "See All music"
    /// The store's list empty (NO_ALBUMS).
    public static let noAlbums = "No albums yet."
    /// The New mark, and what VoiceOver says of it.
    public static let newMark = "New"
    public static let newMarkSpoken = "New in your library"

    /// "No albums match “dumy”."
    public static func noMatch(_ typed: String) -> String { Find.noMatchText("albums", typed: typed) }
}

/// What an Albums screen's body draws (app/LibrarySection.tsx AlbumSection), from the list in hand.
public enum AlbumListBody: Sendable, Equatable {
    /// no list yet, asking: a spinner
    case loading
    /// no list, and the ask failed: the error's words and Try again
    case failed
    /// your library, empty: what to do about it, and See All music
    case emptyLibrary
    /// the store's list, empty: "No albums yet."
    case noAlbums
    /// Find kept nothing: "No albums match “...”."
    case noMatch(String)
    /// the albums, under their headers
    case albums

    /// `list`: the albums in hand (nil before any landed); `failed`: the last ask failed; `found`: how many Find kept.
    public static func of(_ scope: AlbumScope, list: [IndexAlbum]?, failed: Bool, found: Int, typed: String) -> AlbumListBody {
        guard let list else { return failed ? .failed : .loading }
        if list.isEmpty { return scope == .yours ? .emptyLibrary : .noAlbums }
        if found == 0 { return .noMatch(LibraryWords.noMatch(typed)) }
        return .albums
    }
}
