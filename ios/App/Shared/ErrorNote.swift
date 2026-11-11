import DeadwaxCore
import SwiftUI

/// What went wrong, in a listener's words (ErrorNote.tsx): ErrorWords' sentence and its advice as one line, and -
/// only for whoever runs deadwax (Access.seesDetail) - the error's own words under "For whoever runs deadwax".
/// A page's Try again is its own, beside this (pass `retry: true` so the advice leaves it to the page).
struct ErrorNote: View {
    private let error: (any Error)?
    private let service: ErrorWords.Service?
    private let gone: String?
    private let failed: String?
    private let retry: Bool
    private let text: String?
    private let detail: String?

    @Environment(ServerModel.self) private var server

    /// An error said through ErrorWords.of - `gone` a 404's sentence, `failed` what didn't work, `service` whose
    /// answer it was.
    init(_ error: any Error, service: ErrorWords.Service? = nil, gone: String? = nil, failed: String? = nil,
         retry: Bool = false) {
        self.error = error
        self.service = service
        self.gone = gone
        self.failed = failed
        self.retry = retry
        text = nil
        detail = nil
    }

    /// Words already said (a Core rule's own line), with raw `detail` for whoever runs deadwax.
    init(text: String, detail: String? = nil) {
        error = nil
        service = nil
        gone = nil
        failed = nil
        retry = false
        self.text = text
        self.detail = detail
    }

    private var line: (said: String, detail: String?) {
        if let error {
            let line = ErrorWords.of(error, admin: server.access.seesDetail, service: service, gone: gone,
                                     failed: failed, retry: retry)
            return (line.said, line.detail)
        }
        return (text ?? "", server.access.seesDetail ? detail : nil)
    }

    var body: some View {
        let line = line
        VStack(alignment: .leading, spacing: 6) {
            Text(line.said)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            if let detail = line.detail, !detail.isEmpty {
                DisclosureGroup(ErrorWords.forWhoever) {
                    Text(detail)
                        .font(.footnote.monospaced())
                        .foregroundStyle(Palette.quiet)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.footnote)
            }
        }
    }
}
