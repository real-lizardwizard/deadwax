import DeadwaxCore
import SwiftUI

/// You > Getting albums (Phase 6, slice 1 - phase6-get-requests.md 2.12, question 5; the web's You.tsx and
/// ConfirmCancelChoice.tsx): "Confirm before cancelling", this phone's own - Requests' ✕ reads it at the tap - kept in
/// UserDefaults under the web's key, on unless turned off. Slice 3 adds When I tap Get, Quality floor and Format above
/// it, kept for the person on deadwax.
struct GettingAlbumsSection: View {
    @AppStorage(ConfirmCancel.storageKey) private var stored: String?

    var body: some View {
        Section {
            Toggle(RequestWords.confirmCancel, isOn: Binding<Bool>(get: { ConfirmCancel.read(stored) },
                                                                  set: { (on: Bool) -> Void in
                                                                      stored = ConfirmCancel.stored(on)
                                                                  }))
        } header: {
            Text(RequestWords.gettingAlbums)
        } footer: {
            Text(RequestWords.confirmCancelNote)
        }
    }
}
