import CoreTransferable
import DeadwaxCore
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// "Export…" (eq.md 3.11): a menu of two - The Whole Curve and The Correction Alone - each a ShareLink of a file made
/// when it is shared, `<output name> EQ.txt`, in Equalizer APO's syntax and AutoEq's shape (Core's APOWriter). The
/// share sheet is Apple's way to hand a file out of an app: Files, AirDrop, Mail. The correction alone needs a
/// correction.
struct EQExportMenu: View {
    let setting: EQOutputSetting
    let settings: EQSettings
    /// the rate the output plays at (48 kHz while it isn't connected), as the curve is drawn
    let rate: Double

    var body: some View {
        let name = EQWords.Export.fileName(setting.shownName)
        Menu {
            ShareLink(item: EQExportFile(setting: setting, settings: settings, whole: true, rate: rate),
                      preview: SharePreview(name)) {
                Text(EQWords.Export.whole)
            }
            ShareLink(item: EQExportFile(setting: setting, settings: settings, whole: false, rate: rate),
                      preview: SharePreview(name)) {
                Text(EQWords.Export.alone)
            }
            .disabled(setting.correction == nil)
        } label: {
            Label(EQWords.Export.menu, systemImage: "square.and.arrow.up")
        }
    }
}

/// One export, written when the share sheet asks for it - so nothing is worked out while the page only draws.
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
