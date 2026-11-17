import Foundation
import Testing
@testable import DeadwaxCore

// The Mac app, slice 1 (notes/ios.md "The Mac app, slice 1: it runs and plays"): the sign-in kept in a file on the Mac,
// where the Keychain needs a provisioning profile the Mac build doesn't have - its name from the server, made 0600 in a
// folder 0700, read back as written, replaced whole, removed at sign-out. In a temporary folder: FileManager is Linux's
// too. And what the Mac is called to another device (Resume.label(for:)).

/// A fresh folder for one test, deleted after.
private func withFolder(_ body: (URL) throws -> Void) rethrows {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("deadwax-sessions-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: url) }
    try body(url)
}

private func names(_ folder: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
}

private let home = "http://192.168.1.20:8090"
private let away = "https://deadwax.example.org"

@Suite struct SessionFileTests {
    @Test func theNameIsTheServersAndNeverAPath() {
        #expect(SessionFile.name(home) == "http%3A%2F%2F192%2E168%2E1%2E20%3A8090")
        #expect(SessionFile.name(away) == "https%3A%2F%2Fdeadwax%2Eexample%2Eorg")
        #expect(SessionFile.name(home) == KeptAlbumIndex.safeName(home), "named as the kept /me's folder is")
        for server in [home, away, "http://../..", "http://a/b", "%41"] {
            let name = SessionFile.name(server)
            #expect(!name.contains("/") && !name.contains(".") && !name.isEmpty, "\(server)")
        }
        #expect(SessionFile.name("%41") != SessionFile.name("A"), "one server, one name")
    }

    @Test func aLongServerIsStillOneNameAndAShortOne() {
        let long = "http://" + String(repeating: "deadwax-", count: 40) + ".example:8090"
        let other = long.replacingOccurrences(of: ":8090", with: ":8091")
        let name = SessionFile.name(long)
        #expect(name.utf8.count == SessionFile.longestName)
        #expect(name != SessionFile.name(other), "two long servers that differ only at the end")
        #expect(name == SessionFile.name(long), "the same every time")
        #expect(SessionFile.fnv1a("") == "cbf29ce484222325", "FNV-1a's offset basis")
        #expect(SessionFile.fnv1a("a") == "af63dc4c8601ec8c")
    }

    @Test func theAppsFolderIsInApplicationSupport() {
        let support = URL(fileURLWithPath: "/container/Library/Application Support", isDirectory: true)
        let file = SessionFile(applicationSupport: support)
        #expect(file.folder.path == "/container/Library/Application Support/deadwax/sessions")
        #expect(file.url(home).path == "/container/Library/Application Support/deadwax/sessions/" + SessionFile.name(home))
    }

    @Test func savedIsReadBackAndMadeForThisUserAlone() {
        withFolder { root in
            let file = SessionFile(folder: root.appendingPathComponent("deadwax/sessions"))
            #expect(file.read(home) == nil, "nothing kept yet")
            #expect(file.save("cookie-value_1", for: home))
            #expect(file.read(home) == "cookie-value_1")
            #expect(SessionFile.mode(at: file.url(home).path) == 0o600)
            #expect(SessionFile.mode(at: file.folder.path) == 0o700)
            // the cookie's bytes and nothing else
            #expect(FileManager.default.contents(atPath: file.url(home).path) == Data("cookie-value_1".utf8))
            #expect(names(file.folder) == [SessionFile.name(home)], "no temporary file left")
        }
    }

    @Test func aSaveReplacesTheOldWholeAndTightensItsPermissions() throws {
        try withFolder { root in
            let file = SessionFile(folder: root)
            #expect(file.save("first", for: home))
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.url(home).path)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
            #expect(file.save("second, longer than the first", for: home))
            #expect(file.read(home) == "second, longer than the first")
            #expect(SessionFile.mode(at: file.url(home).path) == 0o600)
            #expect(SessionFile.mode(at: root.path) == 0o700)
            #expect(file.save("3", for: home))
            #expect(file.read(home) == "3", "a shorter one leaves nothing of the longer behind")
            #expect(names(root) == [SessionFile.name(home)])
        }
    }

    @Test func eachServerHasItsOwnAndSigningOutRemovesOnlyItsOwn() {
        withFolder { root in
            let file = SessionFile(folder: root)
            #expect(file.save("at home", for: home))
            #expect(file.save("away", for: away))
            #expect(file.read(home) == "at home" && file.read(away) == "away")
            file.delete(home)
            #expect(file.read(home) == nil)
            #expect(!FileManager.default.fileExists(atPath: file.url(home).path), "the file itself is gone")
            #expect(file.read(away) == "away")
            file.delete(home)    // nothing there: nothing happens
            file.delete(away)
            #expect(names(root).isEmpty)
        }
    }

    @Test func aStopMidSaveLeavesNothingTheNextSaveOrSignOutMinds() throws {
        try withFolder { root in
            let file = SessionFile(folder: root)
            let temporary = root.appendingPathComponent("." + SessionFile.name(home) + ".new")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: temporary.path, contents: Data("half".utf8))
            #expect(file.read(home) == nil, "a temporary file is never read as the cookie")
            #expect(file.save("whole", for: home))
            #expect(file.read(home) == "whole")
            FileManager.default.createFile(atPath: temporary.path, contents: Data("half".utf8))
            file.delete(home)
            #expect(names(root).isEmpty, "sign-out takes a leftover temporary file too")
        }
    }

    @Test func aFolderThatCantBeMadeKeepsNothing() throws {
        try withFolder { root in
            // a file where the folder should be
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let blocked = root.appendingPathComponent("sessions")
            FileManager.default.createFile(atPath: blocked.path, contents: Data())
            let file = SessionFile(folder: blocked)
            #expect(!file.save("cookie", for: home))
            #expect(file.read(home) == nil)
        }
    }

    @Test func onlyARegularFileIsRead() throws {
        try withFolder { root in
            let file = SessionFile(folder: root)
            try FileManager.default.createDirectory(at: file.url(home), withIntermediateDirectories: true)
            #expect(file.read(home) == nil, "a folder of the name is no cookie")
        }
    }
}

@Suite struct DeviceTests {
    /// play_queue.py's LABEL_PATTERN, ^[A-Za-z0-9 ]{1,40}$: a label outside it would be refused with the save.
    static func fitsTheServer(_ label: String) -> Bool {
        (1...40).contains(label.count) && label.unicodeScalars.allSatisfy {
            ("A"..."Z").contains($0) || ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == " "
        }
    }

    @Test func eachDeviceIsCalledWhatTheWebCallsIt() {
        #expect(Resume.label(for: .iPhone) == Resume.label, "the phone's own, as before")
        #expect(Resume.label(for: .iPhone) == "iPhone")
        #expect(Resume.label(for: .mac) == "Mac", "resume.ts deviceLabel: Safari on a Mac")
        for device in Device.allCases {
            #expect(Self.fitsTheServer(Resume.label(for: device)), "\(device)")
        }
        #expect(Set(Device.allCases.map { Resume.label(for: $0) }).count == Device.allCases.count, "told apart")
    }
}
