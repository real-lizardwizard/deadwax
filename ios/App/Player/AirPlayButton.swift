import AVKit
import DeadwaxCore
import SwiftUI
import UIKit

/// Now Playing's AirPlay button: the system's own route picker (AVRoutePickerView), so the list of speakers, the
/// phone itself and AirPods is iOS's - always there on the phone, where the web's comes and goes with a speaker in
/// reach. Tinted the app's accent while the music goes somewhere other than the phone.
///
/// (R3's review) Now Playing's bottom row lays it under the output's whole column, its own glyph hidden (`glyph`
/// false: clear in both tints) under the glyph and the name the row draws, so all of the column takes the tap - and
/// VoiceOver hears where the music plays as its value (`playsTo`, the output's name as the EQ names it). The Mac's bar
/// and its output keep its glyph, with no value.
struct AirPlayButton: UIViewRepresentable {
    /// Whether it draws AirPlay's own glyph.
    var glyph = true
    /// Where the music plays, said as the button's value.
    var playsTo: String?

    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.prioritizesVideoDevices = false
        dress(picker)
        return picker
    }

    func updateUIView(_ picker: AVRoutePickerView, context: Context) {
        dress(picker)
    }

    private func dress(_ picker: AVRoutePickerView) {
        picker.tintColor = glyph ? UIColor.label : UIColor.clear
        picker.activeTintColor = glyph ? UIColor(Palette.accent) : UIColor.clear
        picker.accessibilityLabel = NowPlayingWords.airPlay
        picker.accessibilityValue = playsTo
    }
}
