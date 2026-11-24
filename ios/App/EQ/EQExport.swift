import CoreTransferable
import DeadwaxCore
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// "Export…" (eq.md 3.11): a menu of two - The Whole Curve and The Correction Alone - each a ShareLink of a file made
/// when it is shared, `<output name> EQ.txt`, in Equalizer APO's syntax and AutoEq's shape (Core's APOWriter). The
/// share sheet is Apple's way to hand a file out of an app: Files, AirDrop, Mail. The correction alone needs a
/// correction.
///
/// (The Mac app, slice 6 - notes/ios.md "The Mac app, slice 6: EQ files") Its items are Core's, by device
/// (EQWords.Export.items): the iPhone's the two shares, exactly as before; the Mac's the Save panel's two - Save the Whole
/// Curve…, Save the Correction Alone… (Platform's `eqSavePanel`: the same file, written where the person saves it) -
/// then a share of each, for AirDrop and Mail.
struct EQExportMenu: View {
    let setting: EQOutputSetting
    let settings: EQSettings
    /// the rate the output plays at (48 kHz while it isn't connected), as the curve is drawn
    let rate: Double

    /// (The Mac app, slice 6) The file the Save panel is saving, while it's up - set only by the Mac's Save items.
    @State private var saving: EQExportFile?

    var body: some View {
        let name = EQWords.Export.fileName(setting.shownName)
        let sections = EQWords.Export.items(Platform.device)
        Menu {
            ForEach(Array(sections.enumerated()), id: \.offset) { (index: Int, section: [EQWords.Export.Item]) in
                if index > 0 { Divider() }
                ForEach(section, id: \.words) { (item: EQWords.Export.Item) in
                    entry(item, name: name)
                        .disabled(!item.enabled(hasCorrection: setting.correction != nil))
                }
            }
        } label: {
            Label(EQWords.Export.menu, systemImage: "square.and.arrow.up")
        }
        .eqSavePanel($saving)
    }

    /// One item: a share of the file made then, or (the Mac's) the Save panel for it.
    @ViewBuilder private func entry(_ item: EQWords.Export.Item, name: String) -> some View {
        switch item.way {
        case .share:
            ShareLink(item: file(item.whole), preview: SharePreview(name)) {
                Text(item.words)
            }
        case .save:
            Button(item.words) { saving = file(item.whole) }
        }
    }

    private func file(_ whole: Bool) -> EQExportFile {
        EQExportFile(setting: setting, settings: settings, whole: whole, rate: rate)
    }
}

/// One export, written when the share sheet asks for it - so nothing is worked out while the page only draws. (The Mac
/// app, slice 6) And when the Save panel asks: the same file, which the panel then writes where the person saves it.
struct EQExportFile: Transferable, Sendable {
    let setting: EQOutputSetting
    let settings: EQSettings
    let whole: Bool
    let rate: Double

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { (file: EQExportFile) async throws -> SentTransferredFile in
            SentTransferredFile(try file.write())
        }
    }

    /// The file, in a folder of its own in the app's temporary space (so its name is the output's, whatever else is
    /// there): the day it is made in the phone's own time zone.
    func write() throws -> URL {
        let text = APOWriter.export(setting, in: settings, whole: whole, day: Self.day(), rate: rate)
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("EQ export \(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(EQWords.Export.fileName(setting.shownName))
        try Data(text.utf8).write(to: url, options: .atomic)
        return url
    }

    /// "2026-11-12".
    static func day() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
