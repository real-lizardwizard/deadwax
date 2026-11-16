import DeadwaxCore
import SwiftUI

/// Settings > Manage > Library care (Phase 8, slice 7 - notes/ios-specs/phase8-managing.md 6; the web's
/// app/LibraryCare.tsx): what the page is for (naming only the parts this person has), then, as the web's ladder has it,
/// LIBRARY_PATH's problem said plainly, Reading the library, a first read failed with Try again - else Rescan (Look after
/// the library's: the scan's facts, a read again that failed with Try again, the button, and why it is there) and the runs
/// (Edit albums': Narrow to, what they act on, and for Covers, CD art and Lyrics each its Start or Stop, what it will do
/// and what its last run did). With logins on and Look after the library, In nobody's library is a row under them, its
/// page pushed (HeldByNobodyScreen).
///
/// The runs are the app's (CareRunModel, every decision Core's CareRuns): leaving the page doesn't stop one, and its
/// result stays. One run at a time - the others' Start off while one goes, saying so. The screen stays on while a run goes
/// and this page shows. Out of reach, what is drawn is how it was under the amber line Edit album has, and nothing can be
/// pressed until it is back and the library read again. Without either part it says so and asks nothing; opened out of
/// reach before anything was read, it says it needs deadwax. With Reduce Motion nothing slides; VoiceOver reads each
/// row once, and hears each run's result as it ends.
struct LibraryCareScreen: View {
    @Environment(CareRunModel.self) private var care
    @Environment(Reachability.self) private var reachability
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let parts = care.parts
        Group {
            if !parts.shown {
                ContentUnavailableView {
                    Label(LibraryCare.title, systemImage: "lock")
                } description: {
                    Text(EditWords.noPermission)
                }
            } else if !reachability.online && !care.scan.loaded {
                ContentUnavailableView {
                    Label(LibraryCare.title, systemImage: "wifi.slash")
                } description: {
                    Text(EditWords.needsDeadwax)
                }
            } else {
                list(parts)
            }
        }
        .navigationTitle(LibraryCare.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { care.shows() }
        .onDisappear { care.hides() }
        // a part given while the page is up: read now
        .onChange(of: parts.shown) { _, shown in
            if shown { care.shows() }
        }
    }

    // MARK: the page

    @ViewBuilder private func list(_ parts: Managing.CareParts) -> some View {
        let online = reachability.online
        List {
            Section {
                Text(LibraryCare.careLine(rescan: parts.rescan, bulk: parts.bulk))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(Typeface.footnote)
            switch care.state {
            case .problem(let problem):
                Section {
                    Text(problem)
                        .foregroundStyle(Palette.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .reading:
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(LibraryCare.reading).foregroundStyle(Palette.quiet)
                    }
                    .accessibilityElement(children: .combine)
                }
            case .failed:
                Section {
                    ErrorNote(text: care.failure ?? LibraryCare.readFailed)
                    Button(LibraryCare.tryAgain) {
                        care.retry()
                    }
                    .disabled(care.scan.reading || care.runs.rescanning || !online)
                }
            case .list:
                if parts.rescan {
                    rescanSection(online: online)
                }
                if parts.bulk {
                    runsSection(parts, online: online)
                    ForEach(BulkTargets.kinds, id: \.self) { (kind: BulkTargets.Kind) in
                        kindSection(kind, online: online)
                    }
                }
            }
            if care.heldShown {
                Section {
                    NavigationLink(value: AppRoute.heldByNobody) {
                        Text(Held.title)
                    }
                }
            }
        }
        .transaction { (transaction: inout Transaction) -> Void in
            if reduceMotion { transaction.animation = nil }
        }
        .editOutOfReach(!online && care.scan.loaded)
    }

    // MARK: Rescan

    private func rescanSection(online: Bool) -> some View {
        Section {
            // the scan's age moves on while the page shows
            TimelineView(.periodic(from: .now, by: 30)) { (context: TimelineViewDefaultContext) in
                Text(care.facts(now: context.date.timeIntervalSince1970 * 1000))
                    .font(Typeface.footnote)
                    .foregroundStyle(Palette.quiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
            rereadFailure(online: online)
            Button {
                care.rescan()
            } label: {
                HStack(spacing: 8) {
                    Text(care.runs.rescanning ? LibraryCare.rescanning : LibraryCare.rescan)
                    if care.runs.rescanning {
                        ProgressView()
                            .accessibilityHidden(true)
                    }
                }
            }
            .disabled(!care.rescanOpen(online: online))
        } header: {
            Text(LibraryCare.rescanTitle)
                .font(Typeface.footnote)
        } footer: {
            Text(LibraryCare.rescanWords)
                .font(Typeface.footnote)
        }
    }

    /// A read again that failed over the scan on screen, with Try again - under Rescan (the web's), or under the runs for
    /// someone without Rescan (the phone's: the web says it nowhere for them).
    @ViewBuilder private func rereadFailure(online: Bool) -> some View {
        if let failure = care.failure, care.scan.loaded {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(failure)
                    .foregroundStyle(Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(LibraryCare.tryAgain) {
                    care.retry()
                }
                .buttonStyle(.borderless)
                .font(Typeface.footnote.weight(.semibold))
                .disabled(care.scan.reading || care.runs.rescanning || !online)
            }
            .font(Typeface.footnote)
        }
    }

    // MARK: the runs

    private func runsSection(_ parts: Managing.CareParts, online: Bool) -> some View {
        Section {
            TextField(LibraryCare.narrowTo, text: Binding(
                get: { care.narrow },
                set: { (typed: String) -> Void in care.narrow = typed }
            ), prompt: Text(LibraryCare.narrowPrompt))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .accessibilityLabel(LibraryCare.narrowTo)
            Text(care.scopeNote)
                .font(Typeface.footnote)
                .foregroundStyle(Palette.quiet)
                .fixedSize(horizontal: false, vertical: true)
            if !parts.rescan {
                rereadFailure(online: online)
            }
        } header: {
            Text(LibraryCare.runsTitle)
                .font(Typeface.footnote)
        }
    }

    /// Covers, CD art or Lyrics: Stop while it runs, else Start with how many albums it takes (none to take, no button),
    /// what it will do, and what its last run did.
    private func kindSection(_ kind: BulkTargets.Kind, online: Bool) -> some View {
        let runs = care.runs
        let targets = care.targets(kind)
        let result = runs.result(kind)
        return Section {
            if let stop = runs.stopLabel(kind) {
                Button {
                    care.stop(kind)
                } label: {
                    HStack(spacing: 8) {
                        ProgressView()
                            .accessibilityHidden(true)
                        Text(stop)
                    }
                }
                .disabled(runs.stopping(kind))
                Text(LibraryCare.screenOnNote)
                    .font(Typeface.footnote)
                    .foregroundStyle(Palette.quiet)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let targets, !targets.isEmpty {
                Button(LibraryCare.startLabel(kind, count: targets.count)) {
                    care.start(kind)
                }
                .disabled(!care.startOpen(kind, online: online))
                if let other = runs.under?.kind, other != kind {
                    Text(LibraryCare.waiting(for: other))
                        .font(Typeface.footnote)
                        .foregroundStyle(Palette.quiet)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(LibraryCare.note(kind, targets: targets, typed: runs.narrow))
                .font(Typeface.footnote)
                .foregroundStyle(Palette.quiet)
                .fixedSize(horizontal: false, vertical: true)
            if !result.isEmpty {
                Text(result)
                    .font(Typeface.footnote.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text(LibraryCare.heading(kind))
                .font(Typeface.footnote)
        }
    }
}
