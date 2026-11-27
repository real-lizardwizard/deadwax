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

    /// The readout goes between the times: `readout` wide and centred on a row `width` wide, it clears the wider of
    /// the two times (`time` wide, at either end of the row) by `clear` on both sides. Else it takes a line of its own
    /// under them.
    public static func fitsBetween(readout: Double, time: Double, width: Double, clear: Double) -> Bool {
        readout + 2 * (time + clear) <= width
    }
}
