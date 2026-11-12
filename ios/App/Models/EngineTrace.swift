import DeadwaxAudio
import DeadwaxCore
import os

/// The audio engine's log (PlaybackEngine's `trace`), set on the engine as PlayerModel makes it: each line the engine
/// writes is scrubbed and kept (Core's EngineLog: the last 500 lines in memory, for You > Debug's Engine log) and sent
/// to os_log, subsystem net.lizardlounge.deadwax, category engine - so Console.app on the Mac, with the iPhone
/// chosen, streams it as it happens, the lines Debug has long since let go included. At the info level: about two
/// lines a second while playing are tracing, not something to keep, and iOS holds info messages in memory, writing
/// them to the phone's log store only around a fault - the default level's would all be stored, some 170,000 lines a
/// day of playing. Console shows them with Action > Include Info Messages on.
///
/// The engine calls `trace` on its own queue, for every line; with no `trace` it builds no line at all (note()'s words
/// are an autoclosure). What a line costs once it is set - the line built, the scrub's first look, the lock, os_log -
/// was measured at about 2 µs, at about 2 lines a second while playing (notes/ios.md, "Debug's engine log").
enum EngineTrace {
    static let log = EngineLog()
    private static let logger = Logger(subsystem: "net.lizardlounge.deadwax", category: "engine")

    /// Made outside the main actor, as the engine calls it on its own queue (PlayerModel.lead's reason).
    static func attach(_ engine: PlaybackEngine) {
        engine.trace = { line in
            let kept = log.append(line)
            // scrubbed above, so public: os_log would otherwise show "<private>" once no debugger is attached
            logger.info("\(kept, privacy: .public)")
        }
    }
}
