import DeadwaxCore
import SwiftUI

/// What a name alert asks for (eq.md 3.2, 3.6): Rename Output, Save as Preset, Rename Preset - its title, the field's
/// placeholder and first text, its two buttons, and what Save does: nil when it was saved, else the problem in words.
/// `done` captures the output or preset it was opened for, so whatever connects while it is up, the name goes there.
struct EQNameAsk: Identifiable {
    var id = UUID()
    var title: String
    var placeholder: String
    var text = ""
    var save: String
    var cancel: String
    var problem: String?
    let done: @MainActor (String) -> String?
}

extension View {
    /// The name alert: a text field, Save and Cancel. Refused, it comes back with the problem under its title - "Give
    /// it a name.", "There's already a preset called "Bass Boost"." - and what was typed. `ask` is nil again once it
    /// has saved or been cancelled, and stays set while a refusal brings it back, so a page can tell it is covered.
    func eqNameAlert(_ ask: Binding<EQNameAsk?>) -> some View {
        modifier(EQNameAlert(ask: ask))
    }
}

private struct EQNameAlert: ViewModifier {
    @Binding var ask: EQNameAsk?
    /// The ask drawn: kept while the alert animates away, so its title doesn't empty as it goes.
    @State private var drawn: EQNameAsk?
    @State private var text = ""
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .alert(drawn?.title ?? "", isPresented: $shown, presenting: drawn) { (asked: EQNameAsk) in
                TextField(asked.placeholder, text: $text)
                Button(asked.save) { save(asked) }
                Button(asked.cancel, role: .cancel) { ask = nil }
            } message: { (asked: EQNameAsk) in
                if let problem = asked.problem { Text(problem) }
            }
            .onChange(of: ask?.id) { _, id in
                guard id != nil, let asked = ask else { return }
                drawn = asked
                text = asked.text
                shown = true
            }
    }

    private func save(_ asked: EQNameAsk) {
        guard let problem = asked.done(text) else {
            ask = nil
            return
        }
        // the alert closes as its button is tapped: it comes back with the problem, and what was typed, once it has
        var again = asked
        again.problem = problem
        again.text = text
        again.id = UUID()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            ask = again
        }
    }
}
