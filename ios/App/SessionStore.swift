import DeadwaxCore
import Foundation

/// Where this device keeps deadwax's sign-in - the session cookie value, per server; never the password. On the iPhone,
/// the Keychain (SessionKeychain, exactly as before). On the Mac, a file in the app's sandbox container (Core's
/// SessionFile: `Application Support/deadwax/sessions/<server>`, made 0600): a Mac Catalyst app's Keychain is the data
/// protection keychain, which needs a provisioning profile the Mac build doesn't have (notes/ios.md "The Mac app,
/// slice 1: it runs and plays"). The same three calls either way, and nothing about the session is logged.
enum SessionStore {
    static func read(_ server: String) -> String? {
        Platform.mac ? macFile?.read(server) : SessionKeychain.read(server)
    }

    static func save(_ value: String, for server: String) {
        if Platform.mac {
            macFile?.save(value, for: server)
        } else {
            SessionKeychain.save(value, for: server)
        }
    }

    /// Signing out.
    static func delete(_ server: String) {
        if Platform.mac {
            macFile?.delete(server)
        } else {
            SessionKeychain.delete(server)
        }
    }

    /// The Mac's folder, `<Application Support>/deadwax/sessions`.
    private static let macFile: SessionFile? = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        .map { (support: URL) -> SessionFile in SessionFile(applicationSupport: support) }
}
