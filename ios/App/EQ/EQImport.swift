import DeadwaxCore
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// An import (eq.md 3.9): what was read - or why the whole of it was refused - from a file or the clipboard, kept for
/// its preview. One at a time (AppNavigation's `eqImport`).
struct EQImportItem: Identifiable, Equatable, Sendable {
    let id = UUID()
    /// the file's name; nil for a paste
    let name: String?
    /// the text, kept with the correction (4) - and a refused line's, for whoever runs deadwax
    let text: String
    let result: Result<APOReading, APORefusal>
    /// iOS's own words when the file couldn't be read - for whoever runs deadwax
    let detail: String?
    /// the output For starts on: the page's own, for an import from an EQ page; nil, the output now (a shared file)
    let forKey: String?
}

/// The three ways in (3.9), read off the main thread - a GraphicEQ's conversion takes a moment.
enum EQImportReading {
    /// A file from Files or from another app, through its security-scoped URL: past 256 KB it is refused unread - and
    /// one whose size iOS doesn't say is read no further than one byte past it, so no file is ever read whole into
    /// memory; the copy iOS made in Documents/Inbox (a shared file) is deleted once read.
    static func file(_ url: URL, forKey: String?) -> EQImportItem {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
            deleteIfInbox(url)
        }
        let name = url.lastPathComponent
        func tooBig(_ size: Int) -> EQImportItem {
            EQImportItem(name: name, text: "", result: .failure(EQWords.Import.tooBig(bytes: size)), detail: nil,
                         forKey: forKey)
        }
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > APOReader.maxBytes {
            return tooBig(size)
        }
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: APOReader.maxBytes + 1) ?? Data()
            if data.count > APOReader.maxBytes {
                let end = try? handle.seekToEnd()
                return tooBig(end.map { (bytes: UInt64) -> Int in Int(clamping: bytes) } ?? data.count)
            }
            return EQImportItem(name: name, text: EQImportRules.text(data), result: APOReader.read(data), detail: nil,
                                forKey: forKey)
        } catch {
            return EQImportItem(name: name, text: "", result: .failure(EQWords.Import.unreadable),
                                detail: error.localizedDescription, forKey: forKey)
        }
    }

    /// What Paste gave.
    static func pasted(_ text: String, forKey: String?) -> EQImportItem {
        EQImportItem(name: nil, text: text, result: APOReader.read(Data(text.utf8), pasted: true), detail: nil,
                     forKey: forKey)
    }

    /// iOS hands a shared file over as a copy in Documents/Inbox (LSSupportsOpeningDocumentsInPlace is NO): it is the
    /// app's to delete. Nothing anywhere else is touched.
    private static func deleteIfInbox(_ url: URL) {
        guard url.isFileURL,
              let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let inbox = documents.appendingPathComponent("Inbox", isDirectory: true).resolvingSymlinksInPath().path
        let folder = url.deletingLastPathComponent().resolvingSymlinksInPath().path
        if folder == inbox { try? FileManager.default.removeItem(at: url) }
    }
}

/// An EQ page's two ways in (3.8, 3.9): "Import from Files…" and the system's Paste - each read off the main thread,
/// then shown in the page's own preview, For starting on the page's output.
struct EQImportRows: View {
    /// the page whose preview shows it
    let page: UUID
    /// the page's output
    let key: String

    @Environment(AppNavigation.self) private var navigation
    @State private var choosing = false

    var body: some View {
        Button {
            choosing = true
        } label: {
            Label(EQWords.Import.fromFiles, systemImage: "doc")
        }
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.plainText], allowsMultipleSelection: false) {
            (result: Result<[URL], any Error>) -> Void in
            guard case .success(let urls) = result, let url = urls.first else { return }
            read { EQImportReading.file(url, forKey: key) }
        }
        PasteButton(payloadType: String.self) { (strings: [String]) -> Void in
            guard let text = strings.first else { return }
            read { EQImportReading.pasted(text, forKey: key) }
        }
        .buttonBorderShape(.capsule)
        .labelStyle(.titleAndIcon)
    }

    /// Read off the main thread, then shown.
    private func read(_ reading: @escaping @Sendable () -> EQImportItem) {
        let page = self.page
        let navigation = self.navigation
        Task.detached(priority: .userInitiated) { () async -> Void in
            let item = reading()
            await MainActor.run { navigation.importOnPage(page, item) }
        }
    }
}

/// The preview's sheet (3.9): the import AppNavigation holds now - kept while the sheet goes, so it never empties on
/// its way down - and, while it is drawn, the preview counted as up, so a file shared meanwhile takes its place here.
struct EQImportSheetContent: View {
    @Environment(AppNavigation.self) private var navigation
    @State private var last: EQImportItem?

    var body: some View {
        Group {
            if let item = navigation.eqImport ?? last {
                EQImportPreview(item: item)
                    .id(item.id)
            }
        }
        .onChange(of: navigation.eqImport?.id, initial: true) { _, _ in
            if let item = navigation.eqImport { last = item }
        }
        .onAppear { navigation.eqPreviewUp = true }
        .onDisappear {
            navigation.eqPreviewUp = false
            // gone without an answer (what it was over closed): nothing it held is applied, and nothing waits
            navigation.importAnswered(last?.id)
        }
    }
}

/// The preview (3.9): "Import", Cancel at the top left and **Import** at the top right; where it's from, For (the
/// output now first), the curve of what was read alone, one line of what it is, the preamp as it will play, what it
/// replaces, and what was skipped. Import sets it as For's correction (crossfaded when that output is playing), turns
/// the EQ on, and closes. Refused, the whole file: "Can't import this file", the reason - for whoever runs deadwax the
/// line itself, or iOS's words, under it - and only Done.
struct EQImportPreview: View {
    let item: EQImportItem

    @Environment(EQModel.self) private var eq
    @Environment(ServerModel.self) private var server
    @Environment(AppNavigation.self) private var navigation
    @State private var chosen: String?

    var body: some View {
        NavigationStack {
            Group {
                switch item.result {
                case .success(let reading): preview(reading)
                case .failure(let refusal): refused(refusal)
                }
            }
            .navigationTitle(EQWords.Import.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        switch item.result {
        case .success(let reading):
            ToolbarItem(placement: .cancellationAction) {
                Button(EQWords.Import.cancel) { navigation.importAnswered(item.id) }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    take(reading)
                } label: {
                    Text(EQWords.Import.importButton).bold()
                }
            }
        case .failure:
            ToolbarItem(placement: .confirmationAction) {
                Button(EQWords.Import.done) { navigation.importAnswered(item.id) }
            }
        }
    }

    /// For's output: the one chosen, else the page's own, else the output now - always one For lists.
    private func key(_ outputs: [EQOutputSetting]) -> String {
        for candidate in [chosen, item.forKey] {
            if let candidate, outputs.contains(where: { $0.key == candidate }) { return candidate }
        }
        return eq.route.key
    }

    private func preview(_ reading: APOReading) -> some View {
        let outputs = EQImportRules.outputs(eq.settings, route: eq.route)
        let key = key(outputs)
        let output = eq.output(key)
        let setting = eq.setting(output)
        let correction = EQImportRules.correction(name: item.name, text: item.text, reading: reading)
        let lines = EQImportRules.preview(name: item.name, reading: reading, for: setting, in: eq.settings,
                                          rate: eq.rate(key))
        return List {
            Section {
                Text(lines.from)
                    .font(.footnote)
                    .foregroundStyle(Palette.quiet)
                Picker(EQWords.Import.forLabel, selection: Binding<String>(get: { key }, set: { (now: String) -> Void in
                    chosen = now
                })) {
                    ForEach(outputs, id: \.key) { (o: EQOutputSetting) in
                        Text(o.shownName).tag(o.key)
                    }
                }
                .pickerStyle(.menu)
            }
            Section {
                EQCurveView(drawing: EQDrawing.profile(correction, for: output, in: eq.settings), name: output.name)
                    .listRowInsets(EdgeInsets())
            }
            Section {
                // by place: two ears converted alike say the same words
                ForEach(Array(lines.summary.enumerated()), id: \.offset) { (_: Int, line: String) in
                    Text(line)
                }
                Text(lines.preamp)
                if let replaces = lines.replaces {
                    Text(replaces)
                        .foregroundStyle(Palette.quiet)
                }
            }
            if !lines.skipped.isEmpty {
                Section {
                    ForEach(Array(lines.skipped.enumerated()), id: \.offset) { (_: Int, note: String) in
                        Text(note)
                            .font(.footnote)
                    }
                } header: {
                    Text(EQWords.Import.skipped)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func refused(_ refusal: APORefusal) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(EQWords.Import.refusedTitle)
                        .font(.headline)
                    Text(refusal.text)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                    if server.access.seesDetail, let detail = detail(refusal) {
                        Text(detail)
                            .font(.footnote.monospaced())
                            .foregroundStyle(Palette.quiet)
                            .textSelection(.enabled)
                    }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }
        }
        .listStyle(.insetGrouped)
    }

    /// For whoever runs deadwax (3.17): iOS's words for a file it couldn't read, else the refused line itself.
    private func detail(_ refusal: APORefusal) -> String? {
        if let detail = item.detail { return detail }
        guard let n = refusal.line, let line = EQImportRules.line(n, of: item.text), !line.isEmpty else { return nil }
        return line
    }

    /// Import: For's correction from now on, the EQ on ("EQ on"), the sheet closed.
    private func take(_ reading: APOReading) {
        let outputs = EQImportRules.outputs(eq.settings, route: eq.route)
        let output = eq.output(key(outputs))
        eq.importCorrection(EQImportRules.correction(name: item.name, text: item.text, reading: reading), for: output)
        navigation.importAnswered(item.id)
    }
}

extension View {
    /// An EQ page's own preview (3.9): over it while its import is the one AppNavigation holds.
    func eqImportPreview(page: UUID) -> some View {
        modifier(EQPageImport(page: page))
    }
}

private struct EQPageImport: ViewModifier {
    let page: UUID
    @Environment(AppNavigation.self) private var navigation

    func body(content: Content) -> some View {
        content.sheet(isPresented: Binding<Bool>(get: {
            navigation.eqImport != nil && navigation.eqImportPage == page
        }, set: { (up: Bool) -> Void in
            if !up { navigation.importAnswered() }
        })) {
            EQImportSheetContent()
        }
    }
}
