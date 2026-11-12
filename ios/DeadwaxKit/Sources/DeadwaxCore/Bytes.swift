import Foundation

/// Sizes in words (spec 8.6), decimal as iOS's Storage counts: under 1 GB whole MB ("412 MB"; "1 MB" for anything above
/// 0 and under it); from 1 GB to under 100 GB one decimal, a trailing ".0" dropped ("2.1 GB", "20 GB"); 100 GB and over
/// whole ("128 GB"). Each is rounded to the nearest, and one that rounds up to the next unit is said in it (999,999,999
/// bytes is "1 GB", never "1000 MB").
public enum Bytes {
    public static func words(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 MB" }
        let megabytes = (Double(bytes) / 1_000_000).rounded()
        if megabytes < 1000 { return "\(max(Int(megabytes), 1)) MB" }
        let gigabytes = Double(bytes) / 1_000_000_000
        let tenths = (gigabytes * 10).rounded() / 10
        if tenths < 100 {
            return tenths == tenths.rounded() ? "\(Int(tenths)) GB" : String(format: "%.1f GB", tenths)
        }
        return "\(Int(gigabytes.rounded())) GB"
    }
}
