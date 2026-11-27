import DeadwaxCore
import SwiftUI

/// What went wrong, in a listener's words (ErrorNote.tsx): ErrorWords' sentence and its advice as one line, and -
/// only for whoever runs deadwax (Access.seesDetail) - the error's own words under "For whoever runs deadwax".
/// A page's Try again is its own, beside this (pass `retry: true` so the advice leaves it to the page).
///
/// (The panel review's R19) In the look's type: the line a card row's words (the phone's 16, callout's very size and
/// style; the Mac's 13), the detail and its disclosure the small size, the detail in the second colour - in the
/// words' face where it was the system's monospace: the readout face is for numbers that tick (25 Nov's review), as
/// Downloads' own detail is kept. Its colour otherwise the page's, as before.
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
                .font(Platform.mac ? Typeface.Look.text(.field) : Typeface.Phone.text(.row))
                .fixedSize(horizontal: false, vertical: true)
            if let detail = line.detail, !detail.isEmpty {
                DisclosureGroup(ErrorWords.forWhoever) {
                    Text(detail)
                        .font(Platform.mac ? Typeface.Look.text(.smallButton) : Typeface.Phone.text(.small))
                        .foregroundStyle(DWPalette.t2)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(Platform.mac ? Typeface.Look.text(.smallButton) : Typeface.Phone.text(.small))
            }
        }
    }
}
