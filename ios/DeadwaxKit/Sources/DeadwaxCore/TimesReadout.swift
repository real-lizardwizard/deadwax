// Now Playing's readout between the scrubber's two times (27 Nov - notes/ios.md "Now Playing's readout under the
// scrubber (27 Nov)"; iNowPlaying.dc.html): "0:51", then "3 of 11 · FLAC 16/44.1" (BarDisplay.readout, the Mac bar's
// words), then "-2:50", on one line - or, where the three don't fit the row, the readout on a line of its own under
// the times, centred. It never goes back beside the title. Pure: the app's Layout measures the words as they are
// drawn; whether they fit is decided here, never by a text size.

/// The readout between the scrubber's times: where it goes.
public enum TimesReadout {
    /// The two times' words at their widest for a song `length` seconds long - the time played at its end, the time
    /// left at its start (a clock only loses figures as it counts) - so the readout's place is decided once for the
    /// song, and never moves as a clock loses a figure.
    public static func widest(length: Double) -> [String] {
        [PlayerWords.elapsed(shown: length), PlayerWords.remaining(shown: 0, length: length)]
    }

    /// (after review) The same, at the longer of the song's two lengths: `listed`, Navidrome's whole seconds, and
    /// `playing`, PlayerModel's (the listed one until the engine's first tick swaps in the decoded one). A song whose
    /// two straddle a figure - 600 listed, 599.98 decoded - keeps "10:00" when the decoded one comes, so its widest
    /// times never shrink within the song and the readout never changes line half a second in.
    public static func widest(listed: Double?, playing: Double) -> [String] {
        widest(length: songLength(listed: listed, playing: playing))
    }

    /// The longer of the song's two lengths, neither one read when it isn't a length (none, 0, not finite).
    public static func songLength(listed: Double?, playing: Double) -> Double {
        [listed ?? 0, playing].filter { (length: Double) -> Bool in length.isFinite && length > 0 }.max() ?? 0
    }

    /// The row the three need on one line: the readout `readout` wide, centred, and the wider of the two times
    /// (`time` wide) at either end, `clear` from it on both sides - the readout's own row's width when no width is
    /// proposed (an ideal size asked), and what a row must hold for it to go between.
    public static func oneLine(readout: Double, time: Double, clear: Double) -> Double {
        readout + 2 * (time + clear)
    }

    /// The readout goes between the times: `readout` wide and centred on a row `width` wide, it clears the wider of
    /// the two times (`time` wide, at either end of the row) by `clear` on both sides. Else it takes a line of its own
    /// under them.
    public static func fitsBetween(readout: Double, time: Double, width: Double, clear: Double) -> Bool {
        oneLine(readout: readout, time: time, clear: clear) <= width
    }
}
