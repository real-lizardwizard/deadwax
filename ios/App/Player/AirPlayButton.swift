import AVKit
import DeadwaxCore
import SwiftUI
import UIKit

/// Now Playing's AirPlay button: the system's own route picker (AVRoutePickerView), so the list of speakers, the
/// phone itself and AirPods is iOS's - always there on the phone, where the web's comes and goes with a speaker in
/// reach. Tinted the app's accent while the music goes somewhere other than the phone.
struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.prioritizesVideoDevices = false
        picker.tintColor = UIColor.label
        picker.activeTintColor = UIColor(Palette.accent)
        picker.accessibilityLabel = NowPlayingWords.airPlay
        return picker
    }

    func updateUIView(_ picker: AVRoutePickerView, context: Context) {
        picker.accessibilityLabel = NowPlayingWords.airPlay
    }
}
