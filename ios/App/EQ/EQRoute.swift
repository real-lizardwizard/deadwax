import DeadwaxCore
import SwiftUI

/// The EQ's pages (eq.md 3.2, 3.6, 3.7, 3.12): pushed on You's stack as `AppRoute.eq`, and in the sheet over Now
/// Playing on the sheet's own stack - so the pages link through `EQLink`, which pushes the value the stack they are on
/// takes.
enum EQRoute: Hashable {
    /// The EQ page of the output now (You's row, Now Playing's •••): it follows the route.
    case now
    /// One output's EQ page (Other outputs): it stays on that output.
    case output(String)
    /// The presets, for one output: bound to it (8, question 30).
    case presets(String)
    /// The correction picker (3.7), for one output: bound to it.
    case correction(String)
    /// One AutoEq profile's page (3.7), for one output: bound to it - "Use for James's AirPods Pro" does what it says.
    case profile(AutoEqPage)

    /// An EQ page itself, not one pushed from it: where "Use for …" goes back to.
    var isPage: Bool {
        switch self {
        case .now, .output: return true
        case .presets, .correction, .profile: return false
        }
    }
}

extension EnvironmentValues {
    /// Set in the sheet over Now Playing, whose pages are on its own stack (not You's): it closes the sheet, from its
    /// "Done" on every page.
    @Entry var eqDone: DismissAction? = nil
}

/// The sheet's own stack (3.1): the pages pushed over its EQ page - put in the sheet's environment, so a page on it
/// can go back to the EQ page ("Use for …", 3.7). On You's stack, AppNavigation's `backToEQPage()` does it.
@MainActor
@Observable
final class EQSheetStack {
    var path: [EQRoute] = []

    /// Every page over the topmost EQ page popped at once.
    func backToPage() {
        if let page = path.lastIndex(where: { $0.isPage }) {
            path.removeSubrange((page + 1)...)
        } else {
            path.removeAll()
        }
    }
}

/// A link to an EQ page, on whichever stack the page is on.
struct EQLink<Label: View>: View {
    let route: EQRoute
    @ViewBuilder let label: () -> Label

    @Environment(\.eqDone) private var done

    var body: some View {
        if done != nil {
            NavigationLink(value: route, label: label)
        } else {
            NavigationLink(value: AppRoute.eq(route), label: label)
        }
    }
}

/// An EQ route's page.
struct EQDestination: View {
    let route: EQRoute

    var body: some View {
        switch route {
        case .now: EQScreen(opened: .now)
        case .output(let key): EQScreen(opened: .output(key))
        case .presets(let key): EQPresetsScreen(key: key)
        case .correction(let key): EQCorrectionScreen(key: key)
        case .profile(let page): EQProfileScreen(page: page)
        }
    }
}

/// The EQ over Now Playing (3.1): a sheet with its own stack - the EQ page of the output now, its pages pushed on it,
/// "Done" at the top right of each, closing the sheet.
struct EQSheet: View {
    /// The sheet's own (read outside its stack, so it closes the sheet rather than popping a page).
    @Environment(\.dismiss) private var dismiss
    /// The pages pushed over the EQ page.
    @State private var stack = EQSheetStack()

    var body: some View {
        NavigationStack(path: $stack.path) {
            EQScreen(opened: .now)
                .navigationDestination(for: EQRoute.self) { route in
                    EQDestination(route: route)
                }
        }
        .environment(\.eqDone, dismiss)
        .environment(stack)
    }
}

extension View {
    /// "Done" at the top right of an EQ page in the sheet (3.2) - nothing on You's stack.
    func eqDoneButton() -> some View {
        modifier(EQDoneButton())
    }
}

private struct EQDoneButton: ViewModifier {
    @Environment(\.eqDone) private var done

    func body(content: Content) -> some View {
        content.toolbar {
            if let done {
                ToolbarItem(placement: .confirmationAction) {
                    Button(EQWords.Screen.done) { done() }
                }
            }
        }
    }
}
