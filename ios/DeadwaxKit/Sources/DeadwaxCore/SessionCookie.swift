import Foundation

/// deadwax's session cookie, kept by the app itself rather than by HTTPCookieStorage.
///
/// A sign-in answers `Set-Cookie: deadwax_session=s.…; HttpOnly; Max-Age=…; Path=/; SameSite=strict`.
/// HttpOnly is about web pages' scripts; URLSession hands the header to the app. The app keeps the
/// value in the Keychain and sends `Cookie: deadwax_session=…` on every request, ignoring Max-Age:
/// the session slides with use on the server, which decides when it ends (a 401).
public enum SessionCookie {
    /// src/auth.py COOKIE - the contract test checks it.
    public static let name = "deadwax_session"

    /// The session's value from a Set-Cookie header, or nil when there is none or it is being
    /// cleared (an empty value, as a sign-out sends). URLSession joins several Set-Cookie headers
    /// into one with commas, so the value ends at a `;` or a `,`; deadwax's values hold neither.
    public static func value(fromSetCookie header: String?) -> String? {
        guard let header else { return nil }
        var rest = Substring(header)
        while let found = rest.range(of: name + "=") {
            let before = rest[rest.startIndex..<found.lowerBound]
            let atStart = before.allSatisfy({ $0 == " " }) || before.last == "," || before.last == " " || before.last == ";"
            let after = rest[found.upperBound...]
            if atStart {
                var value = after.prefix(while: { $0 != ";" && $0 != "," })
                    .trimmingCharacters(in: .whitespaces)
                if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                    value = String(value.dropFirst().dropLast())
                }
                return value.isEmpty ? nil : value
            }
            rest = after
        }
        return nil
    }

    /// The `Cookie:` header that carries a session.
    public static func header(_ value: String) -> String { "\(name)=\(value)" }

    /// The session a request carried, from its `Cookie:` header (the app's own, `header(_:)`'s - and any other cookies
    /// beside it, `; `-separated): nil when it carried none. (Phase 8, slice 10) A background download's 401 is told by
    /// the session it went out under, so one sent under a session Change password has since replaced holds nothing.
    public static func value(fromCookie header: String?) -> String? {
        guard let header else { return nil }
        for part in header.split(separator: ";") {
            let pair = part.trimmingCharacters(in: .whitespaces)
            guard pair.hasPrefix(name + "=") else { continue }
            let value = String(pair.dropFirst(name.count + 1))
            return value.isEmpty ? nil : value
        }
        return nil
    }
}
