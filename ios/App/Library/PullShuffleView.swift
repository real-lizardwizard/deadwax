import AVFAudio
import Combine
import DeadwaxCore
import SwiftUI
import UIKit

/// Pull to shuffle (Phase 4, slice 3b - phase4-library.md 2.8, 3.5; James: "if you drag down far enough there can be a
/// cool little shuffle graphic that changes as you pull down, and then once you go far enough, it changes, and starts
/// shuffling when you release"). One per page of the Library's switch: Core's PullShuffle, fed by the page's scroll
/// view (`pullsToShuffle`) and drawn by `PullShuffleGraphic` above the page's first row. Its ticks are the haptic's.
@MainActor
@Observable
final class ShufflePull {
    private(set) var pull = PullShuffle()
    /// One more at each arming: the haptic tick.
    private(set) var ticks = 0
    /// A finger is on the page.
    @ObservationIgnored private var touching = false

    /// The page moved: `pulled` points past its top.
    func moved(_ pulled: Double, ready: Bool) {
        if pull.moved(pulled, touching: touching, ready: ready) == .armed { ticks += 1 }
    }

    /// The scroll's phase: a finger on it, or not. True when the finger lifted with it armed and a release would
    /// shuffle - the caller starts the shuffle in that same call.
    func phase(interacting: Bool, ready: Bool) -> Bool {
        let was = touching
        touching = interacting
        guard was, !interacting else { return false }
        return pull.lifted(ready: ready) == .shuffle
    }

    /// The page no longer the one shown: nothing drawn.
    func reset() {
        touching = false
        pull.reset()
    }

    /// The system took the touch (slice 3b's review) - a call, Siri, Notification Center, the app leaving the front:
    /// the finger's going that follows is no release, and shuffles nothing.
    func interrupted() {
        touching = false
        pull.interrupted()
    }
}

/// What a page's scroll view needs to pull to shuffle: the page's pull, what the Shuffle can do, whether it pulls now (the
/// page shown, on screen), and the shuffle to start.
struct PullShuffling {
    let state: ShufflePull
    let can: ShuffleCan
    let on: Bool
    let start: () -> Void
}

extension View {
    /// A page's scroll view pulled to shuffle (3.5): its pull past the top and the finger on it fed to the page's
    /// ShufflePull, the haptic tick on each arming, and the shuffle started in the lift that releases it - nothing
    /// awaited first. iOS 18's scroll geometry reads the pull: on iOS 17 there is no pull, only the •••'s Shuffle. Nil: a
    /// scroll view that doesn't pull (a pushed list's, which refreshes).
    @ViewBuilder
    func pullsToShuffle(_ pulling: PullShuffling?) -> some View {
        if let pulling {
            if #available(iOS 18.0, *) {
                modifier(PullsToShuffle(pulling: pulling))
            } else {
                self
            }
        } else {
            self
        }
    }
}

@available(iOS 18.0, *)
private struct PullsToShuffle: ViewModifier {
    let pulling: PullShuffling

    @Environment(\.scenePhase) private var scenePhase

    /// The system taking the touch, as iOS says it: the app about to leave the front (said before the scene's phase),
    /// or the audio session interrupted - a call, Siri, an alarm.
    private static let resigning = NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
    private static let audioInterrupted = NotificationCenter.default
        .publisher(for: AVAudioSession.interruptionNotification)
        .filter { (note: Notification) -> Bool in
            (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue
        }
        .receive(on: DispatchQueue.main)

    func body(content: Content) -> some View {
        let state = pulling.state
        content
            .onScrollGeometryChange(for: Double.self) { (geometry: ScrollGeometry) -> Double in
                // how far the content is pulled down past its resting top, the bars' insets counted
                Double(-(geometry.contentOffset.y + geometry.contentInsets.top))
            } action: { (_: Double, pulled: Double) -> Void in
                guard pulling.on else { return }
                state.moved(pulled, ready: pulling.can.starts)
            }
            .onScrollPhaseChange { (_: ScrollPhase, phase: ScrollPhase) -> Void in
                guard pulling.on else { return }
                // the touch ending while the app isn't in front is the system's taking it, not the finger's lift
                if phase != .interacting, UIApplication.shared.applicationState != .active {
                    state.interrupted()
                    return
                }
                if state.phase(interacting: phase == .interacting, ready: pulling.can.starts) { pulling.start() }
            }
            .onChange(of: scenePhase) { (_: ScenePhase, now: ScenePhase) -> Void in
                if now != .active { state.interrupted() }
            }
            .onReceive(Self.resigning) { (_: Notification) -> Void in state.interrupted() }
            .onReceive(Self.audioInterrupted) { (_: Notification) -> Void in state.interrupted() }
            .sensoryFeedback(.impact(weight: .light), trigger: state.ticks)
            .onChange(of: pulling.on) { (_: Bool, on: Bool) -> Void in
                if !on { state.reset() }
            }
    }
}

/// The pull's graphic (3.5): a ring round the shuffle mark, filling as the pull nears the line, the mark growing from 0.6
/// to its full size and turning a half turn by it, its line under it; armed, a solid disc of the primary's purple with
/// the mark white on it; released, the mark going round once. Not ready, the ring and the mark as pulling - never the
/// disc - and why. Reduce Motion: the mark keeps its size and never turns; the ring still fills with the finger, and
/// the states swap at once. VoiceOver doesn't read it: the •••'s Shuffle is the way there. Drawn from its bottom up,
/// so it sits in the room the pull opens above the first row.
struct PullShuffleGraphic: View {
    let state: ShufflePull
    let can: ShuffleCan

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spun = false

    private static let ring: CGFloat = 40
    private static let stroke: CGFloat = 2.5

    var body: some View {
        let phase = state.pull.phase
        let line = PullShuffleWords.line(phase, can: can)
        let progress = state.pull.progress
        let armed = phase == .armed || phase == .released
        VStack(spacing: 6) {
            ZStack {
                if armed {
                    Circle().fill(Palette.primary)
                } else {
                    Circle().stroke(Palette.quiet.opacity(0.35), lineWidth: Self.stroke)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Palette.accent, style: StrokeStyle(lineWidth: Self.stroke, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                Image(systemName: "shuffle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(armed ? Palette.primaryLabel : Palette.accent)
                    .scaleEffect(reduceMotion || armed ? 1 : 0.6 + 0.4 * progress)
                    .rotationEffect(.degrees(reduceMotion ? 0 : (armed ? 180 : 180 * progress) + (spun ? 360 : 0)))
            }
            .frame(width: Self.ring, height: Self.ring)
            Text(line)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Palette.quiet)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .opacity(phase == .idle || line.isEmpty ? 0 : min(1, 0.3 + progress))
        .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: armed)
        .onChange(of: phase == .released) { (_: Bool, released: Bool) -> Void in
            // released: the mark goes round once while the page settles
            guard released, !reduceMotion else {
                spun = false
                return
            }
            withAnimation(.easeInOut(duration: 0.6)) { spun = true }
        }
        .onChange(of: phase == .idle) { (_: Bool, idle: Bool) -> Void in
            if idle { spun = false }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
