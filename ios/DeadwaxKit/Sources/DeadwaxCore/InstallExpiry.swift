import Foundation

/// The provisioning profile Xcode signs the app with, read from the app's own
/// `embedded.mobileprovision`. With a free Apple account it lasts 7 days; after that the app won't
/// open until install.sh puts it on the phone again. The file is a signed (CMS) envelope with an XML
/// plist inside, which is all that is needed: no signature is checked here, only the dates read.
public struct ProvisioningProfile: Sendable, Equatable {
    public let name: String?
    public let teamName: String?
    public let creation: Date?
    public let expiration: Date

    public init(name: String?, teamName: String?, creation: Date?, expiration: Date) {
        self.name = name
        self.teamName = teamName
        self.creation = creation
        self.expiration = expiration
    }

    /// The profile in `data` (the whole embedded.mobileprovision), or nil when it holds none.
    public static func parse(_ data: Data) -> ProvisioningProfile? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.upperBound..<data.endIndex) else {
            return nil
        }
        let plist = data.subdata(in: start.lowerBound..<end.upperBound)
        guard let object = try? PropertyListSerialization.propertyList(from: plist, options: [], format: nil),
              let dictionary = object as? [String: Any],
              let expiration = dictionary["ExpirationDate"] as? Date else {
            return nil
        }
        return ProvisioningProfile(name: dictionary["Name"] as? String,
                                   teamName: dictionary["TeamName"] as? String,
                                   creation: dictionary["CreationDate"] as? Date,
                                   expiration: expiration)
    }
}

/// The line in the corner: "This install runs until Thu 30 Oct, 14:02".
public enum InstallExpiry {
    /// From this long before the end, the line also says what to do.
    public static let warnBefore: TimeInterval = 2 * 24 * 60 * 60

    public static func line(expiration: Date?, now: Date, timeZone: TimeZone = .current) -> String {
        guard let expiration else {
            return "No install date to show: this build wasn't signed for a phone."
        }
        let when = format(expiration, timeZone: timeZone)
        if expiration <= now {
            return "This install ran out on \(when). Run install.sh on the Mac to put it back."
        }
        if expiration.timeIntervalSince(now) <= warnBefore {
            return "This install runs until \(when). Run install.sh on the Mac before then."
        }
        return "This install runs until \(when)"
    }

    /// "Thu 30 Oct, 14:02", in English whatever the phone's language - the app's words are English.
    public static func format(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEE d MMM, HH:mm"
        return formatter.string(from: date)
    }
}
