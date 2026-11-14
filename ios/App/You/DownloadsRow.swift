import DeadwaxCore
import SwiftUI

/// You's Downloads row (notes/ios-specs/phase2-downloads.md 6.1), between Playback and Account: "Downloads", its value
/// what's on this phone ("2.1 GB" - nothing at all when nothing is), pushing You > Downloads; and a footer only while
/// something is happening - "Downloading - 6 songs to go", the first wait, or, amber, "2 songs didn't download" - so
/// You stays calm - your library's own line ("Your library: 38 of 412 albums to go") when only it is downloading. When this phone's downloads couldn't be read, its value is "…" and the footer says so, amber.
struct DownloadsRow: View {
    @Environment(DownloadModel.self) private var downloads
    @Environment(ServerModel.self) private var server

    var body: some View {
        let summary = downloads.summary
        let library = downloads.libraryProgress.map { progress -> (text: String, amber: Bool) in
            (AutoDownloadWords.youFooter(downloads.follower.scope ?? AlbumScope.albums(for: server.me), progress), false)
        }
        let footer: (text: String, amber: Bool)? = downloads.storeProblem != nil
            ? (DownloadWords.storeUnreadable, true)
            : DownloadWords.youFooter(fetching: summary.fetching, toGo: summary.toGo, firstWait: summary.firstWait,
                                      failed: summary.failed) ?? library
        Section {
            NavigationLink(value: AppRoute.downloads) {
                LabeledContent(DownloadWords.downloads) {
                    if downloads.storeProblem != nil {
                        Text("\u{2026}")
                    } else if downloads.bytesHere > 0 {
                        Text(Bytes.words(downloads.bytesHere))
                            .monospacedDigit()
                    }
                }
            }
        } footer: {
            if let footer {
                Text(footer.text)
                    .foregroundStyle(footer.amber ? Palette.amber : Palette.quiet)
            }
        }
    }
}
