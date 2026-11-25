import DeadwaxCore
import SwiftUI
import UIKit

/// Which build this is - the iPhone's, or the Mac's (Mac Catalyst, the Mac idiom): one app built twice from the same
/// files (notes/ios.md "The Mac app, slice 1: it runs and plays"). This file is the only one in the App that asks:
/// everything else reads `Platform.mac`, hands Core `Platform.device` (Core never asks - its words and rules that differ
/// take the device as a value, tested on Linux), or calls one of the few things below that are the Mac's alone.
///
/// The one switch is `targetEnvironment(macCatalyst)`, said once, below. Never `os(macOS)` (false on Catalyst),
/// `canImport(AppKit)` (true there, with AppKit's classes refused) or the Mac idiom (the same thing today, and another
/// if the idiom ever changed) - tests/test_ios_mac.py holds it.
///
/// (Slice 2, notes/ios.md "The Mac app, slice 2: menus, keys, right-click and the window") Every helper below is the
/// iPhone's exactly as before on the iPhone - `self`, or SwiftUI's own - and the Mac's on the Mac: its menus and keys
/// (MacCommands.swift), ⌘R hung on the same pulls, the ••• menus' items on a right-click, Escape on a sheet's Close,
/// Return on a dialog's Cancel, Find's cursor, a sheet's root known to the menus, the window kept open over work, and
/// one window.
///
/// (Slice 5, notes/ios.md "The Mac app, slice 5: sleep, power and downloads") And the Mac's sleep, power and outputs -
/// IOKit's and CoreAudio's, the Mac's alone, so their imports are inside the switch too - and its ProcessInfo
/// activities: the display kept on over a care run, App Nap kept off over work. On the iPhone: the idle timer and
/// UIDevice's battery exactly as before, and nothing else.
///
/// (Slice 6, notes/ios.md "The Mac app, slice 6: EQ files") And the Mac's ways in and out for an EQ file: File > Import
/// EQ File…'s Open panel, a file dropped on the window, Export…'s Save panel - and a file opened with deadwax brought to
/// the one window. On the iPhone none of them: its ways are Import from Files…, Paste, the share sheet, as before.
///
/// (Slice 7, notes/ios.md "The Mac app, slice 7: managing on a big screen") And managing at a window's size: Edit album's
/// sheet sized by the window it is over (presentationSizing, macOS 15 and later), Server settings' pages known to the
/// menus for ⌘S, Tab between a page's fields, and the event log's lines selected as a Mac list's are and copied with
/// Edit > Copy - the system's own item, through the responder chain. On the iPhone each is the view as before.
enum Platform {
    /// The device this build is, for Core.
    static var device: Device { mac ? .mac : .iPhone }

    /// (Slice 5) The work App Nap is kept off for on the Mac (WorkAwake): runs and applies, and downloads.
    enum Work: Hashable {
        case runs
        case downloads
    }
}

#if targetEnvironment(macCatalyst)

import CoreAudio
import IOKit.ps
import IOKit.pwr_mgt
import UniformTypeIdentifiers

extension Platform {
    /// The Mac's build.
    static let mac = true

    /// The window (slice 3, the desktop frame - the Mac app's plan 1.2): as wide and as tall as you like above the
    /// least that holds the sidebar, a page and the player bar (MacFrame's smallest, 880 x 600), opening at 1280 x 820,
    /// where the side panels are a third column. It was phone-shaped until slice 3 (390 x 640 to 600 wide). Its size
    /// and place after that are macOS's to remember.
    enum Window {
        static let smallest = CGSize(width: MacFrame.smallestWidth, height: MacFrame.smallestHeight)
        static let widest = CGFloat.greatestFiniteMagnitude
        static let opening = CGSize(width: MacFrame.openingWidth, height: MacFrame.openingHeight)
    }

    /// (Slice 3) The app's own window scenes - the one RootView is drawn in (MainWindowMarker). Only these are shaped,
    /// never whatever else comes to the front: a sheet held to the main window's least size would be 880 wide. On the
    /// Mac a sheet is drawn in a window of its own (macOS logs a scene for it) - though slice 3's smoke runs saw no
    /// second UIWindowScene join the app's while one was up, and a cover drawn in the main window - so nothing here
    /// counts on either. RootView is drawn in the WindowGroup's scene alone - never inside a presentation, whose page is
    /// the sheet's own view - so a scene RootView's view has moved into is the main one.
    @MainActor private static let mainScenes = NSHashTable<UIWindowScene>.weakObjects()

    /// At launch (the app delegate): the app's window shaped as RootView is drawn in it (`mainScene`), and again each
    /// time it comes to the front (the same values - in case the first was too soon for macOS to take them). A scene
    /// that isn't the app's window - a sheet's, a cover's - is never shaped.
    static func launching() {
        _ = NotificationCenter.default.addObserver(forName: UIScene.didActivateNotification, object: nil,
                                                   queue: .main) { (note: Notification) in
            guard let scene = note.object as? UIWindowScene else { return }
            MainActor.assumeIsolated {
                if mainScenes.contains(scene) { shape(scene) }
            }
        }
        // (slice 2) whether a text field has the cursor: Space, ⌘→ and ⌘← are its own meanwhile (MacMenu); the window's
        // close kept in step with the work it holds (WindowWork)
        MainActor.assumeIsolated {
            TextEditing.shared.start()
            WindowWork.shared.start()
        }
    }

    /// (Slice 2) A dialog's Cancel where the iPhone leaves it to the system to draw: drawn on the Mac, so Return presses
    /// it - never the dialog's Remove. The app's own Cancel (the web's word, QueuePickWords').
    @MainActor static func dialogCancel() -> some View {
        Button(QueuePickWords.cancel, role: .cancel) {}
            .returnCancels()
    }

    /// (Slice 3) RootView's view is in this scene's window: the app's own, shaped now and each time it comes to the front.
    @MainActor static func mainScene(_ scene: UIWindowScene) {
        guard !mainScenes.contains(scene) else { return }
        mainScenes.add(scene)
        shape(scene)
    }

    /// The window's limits, and its title bar: one with the toolbar, no title shown (each page has its own) - and (the
    /// Mac redesign, R1) the window named for the page in front, as last asked (`nameWindow`).
    @MainActor private static func shape(_ scene: UIWindowScene) {
        scene.sizeRestrictions?.minimumSize = Window.smallest
        scene.sizeRestrictions?.maximumSize = CGSize(width: Window.widest, height: CGFloat.greatestFiniteMagnitude)
        scene.titlebar?.titleVisibility = .hidden
        scene.titlebar?.toolbarStyle = .unified
        if !windowName.isEmpty { scene.title = windowName }
    }

    /// (The Mac redesign, R1) The window's name as last asked.
    @MainActor private static var windowName = ""

    /// (The Mac redesign, R1) The app's window named for the page in front (DesktopFrame - MacTitle, the title strip's own
    /// words): the Window menu's item and Mission Control's label. The title bar still shows none
    /// (`titleVisibility = .hidden`): the title strip draws it. Kept, so a window shaped after this is named too.
    @MainActor static func nameWindow(_ name: String) {
        windowName = name
        for scene in mainScenes.allObjects {
            scene.title = name
        }
    }
}

// MARK: (slice 5) sleep, power, outputs, the display and App Nap

extension Platform {
    /// The Mac's sleep, followed from the main run loop (IOKit's IORegisterForSystemPower): may-sleep is allowed at once
    /// - deadwax never refuses a sleep; at will-sleep `willSleep` (the player pauses) and only then the sleep allowed;
    /// at the wake `woke`, which starts nothing. Once for the app; called again, the newest handlers are the ones
    /// called. IOKit refusing (the sandbox, say) is said in the engine log, and the music plays on through a sleep.
    @MainActor static func watchSleep(willSleep: @escaping @MainActor () -> Void, woke: @escaping @MainActor () -> Void) {
        MacSleep.watch(willSleep: willSleep, woke: woke)
    }

    /// The Mac's default output, followed (CoreAudio, on a queue of its own, the answer handed to the main actor):
    /// `gone` when the output in use went away (MacPower.outputGone) - never for another output chosen while the old
    /// one is still there. CoreAudio refusing is said in the engine log.
    @MainActor static func watchOutputs(_ gone: @escaping @MainActor () -> Void) {
        MacOutputs.watch(gone)
    }

    /// Only while charging's reading: which source IOKit says powers the Mac (MacPower.power(source:)) - plugged in or
    /// on battery, and anything it doesn't say plugged in.
    @MainActor static func power() -> PowerState {
        MacPowerSource.read()
    }

    /// The power source's changes (IOKit's run loop source on the main run loop): `changed`, which reads it again.
    @MainActor static func watchPower(_ changed: @escaping @MainActor () -> Void) {
        MacPowerSource.watch(changed)
    }

    /// The display kept on (ScreenAwake: a care run or Re-time, its page in front): one activity with idle display
    /// sleep off, user initiated - begun when it's first wanted, ended when nothing wants it.
    @MainActor static func keepDisplayOn(_ on: Bool) {
        if on, MacActivities.display == nil {
            MacActivities.display = ProcessInfo.processInfo.beginActivity(
                options: [.idleDisplaySleepDisabled, .userInitiated],
                reason: "A Library care or Re-time saved lyrics run, its page in front")
        } else if !on, let held = MacActivities.display {
            ProcessInfo.processInfo.endActivity(held)
            MacActivities.display = nil
        }
    }

    /// App Nap kept off while `work` goes (WorkAwake), so a hidden window doesn't slow it: one activity for each kind,
    /// begun when it's first wanted, ended when nothing wants it. Runs and applies are user initiated (short, and asked
    /// for); downloads user initiated with the Mac's idle sleep still allowed - a MacBook downloading a whole library
    /// may sleep as it would, rather than be kept awake on battery for hours.
    @MainActor static func keepWorking(_ work: Work, _ on: Bool) {
        if on, MacActivities.work[work] == nil {
            let options: ProcessInfo.ActivityOptions
            let reason: String
            switch work {
            case .runs:
                options = [.userInitiated]
                reason = "A Library care run, Re-time saved lyrics or an apply under way"
            case .downloads:
                options = [.userInitiatedAllowingIdleSystemSleep]
                reason = "Downloads under way"
            }
            MacActivities.work[work] = ProcessInfo.processInfo.beginActivity(options: options, reason: reason)
        } else if !on, let held = MacActivities.work.removeValue(forKey: work) {
            ProcessInfo.processInfo.endActivity(held)
        }
    }
}

/// keepDisplayOn's and keepWorking's activities, while each is held.
@MainActor
private enum MacActivities {
    static var display: NSObjectProtocol?
    static var work: [Platform.Work: NSObjectProtocol] = [:]
}

/// watchSleep's: one registration for the app, kept for its life.
@MainActor
private enum MacSleep {
    static var root: io_connect_t = 0
    static var port: IONotificationPortRef?
    static var notifier: io_object_t = 0
    static var willSleep: (@MainActor () -> Void)?
    static var woke: (@MainActor () -> Void)?

    static func watch(willSleep: @escaping @MainActor () -> Void, woke: @escaping @MainActor () -> Void) {
        self.willSleep = willSleep
        self.woke = woke
        guard root == 0 else { return }
        var made: IONotificationPortRef?
        var notifier: io_object_t = 0
        let root = IORegisterForSystemPower(nil, &made, { (_: UnsafeMutableRawPointer?, _: io_service_t, message: UInt32,
                                                          argument: UnsafeMutableRawPointer?) -> Void in
            // on the main run loop (its source is added there below)
            MainActor.assumeIsolated { MacSleep.told(message, argument) }
        }, &notifier)
        guard root != 0, let made else {
            EngineTrace.note(MacPower.sleepUnwatched)
            return
        }
        self.root = root
        port = made
        self.notifier = notifier
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(made).takeUnretainedValue(), .commonModes)
    }

    /// A power message: answered as MacPower says - the pause before the sleep is allowed, never a refusal.
    static func told(_ message: UInt32, _ argument: UnsafeMutableRawPointer?) {
        switch MacPower.answer(to: message) {
        case .allowNow:
            IOAllowPowerChange(root, Int(bitPattern: argument))
        case .pauseThenAllow:
            willSleep?()
            IOAllowPowerChange(root, Int(bitPattern: argument))
        case .woke:
            woke?()
        case .nothing:
            break
        }
    }
}

/// watchOutputs': CoreAudio's default output and its devices, read on a queue of its own - the main thread never waits
/// on the audio hardware - and judged on the main actor against the last reading.
@MainActor
private enum MacOutputs {
    struct Reading: Sendable {
        let output: AudioObjectID?
        /// nil when CoreAudio didn't answer: nothing is judged gone from no answer.
        let devices: [AudioObjectID]?
    }

    static var gone: (@MainActor () -> Void)?
    static var watching = false
    /// The default output as last read: what "previous" is at the next change.
    static var current: AudioObjectID?
    nonisolated static let queue = DispatchQueue(label: "net.lizardlounge.deadwax.outputs")

    static func watch(_ gone: @escaping @MainActor () -> Void) {
        self.gone = gone
        guard !watching else { return }
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, listener())
        guard status == noErr else {
            EngineTrace.note(MacPower.outputsUnwatched)
            return
        }
        watching = true
        // the first reading, in order before any change's (one serial queue, then the main queue)
        queue.async { hand(read()) }
    }

    /// The listener, made outside the main actor: CoreAudio calls it on `queue`.
    nonisolated private static func listener() -> AudioObjectPropertyListenerBlock {
        { (_: UInt32, _: UnsafePointer<AudioObjectPropertyAddress>) -> Void in
            hand(read())
        }
    }

    nonisolated private static func hand(_ reading: Reading) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { changed(reading) }
        }
    }

    /// The default output changed (or the first reading): gone if the one in use is no longer a device at all.
    private static func changed(_ now: Reading) {
        let previous = current
        current = now.output
        guard let devices = now.devices else { return }
        if MacPower.outputGone(previous: previous, now: now.output, devices: devices) { gone?() }
    }

    nonisolated private static func read() -> Reading {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let output: AudioObjectID? = AudioObjectGetPropertyData(system, &address, 0, nil, &size, &device) == noErr
            ? device : nil
        address.mSelector = kAudioHardwarePropertyDevices
        var bytes: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &bytes) == noErr else {
            return Reading(output: output, devices: nil)
        }
        var devices = [AudioObjectID](repeating: AudioObjectID(kAudioObjectUnknown),
                                      count: Int(bytes) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &bytes, &devices) == noErr else {
            return Reading(output: output, devices: nil)
        }
        return Reading(output: output, devices: Array(devices.prefix(Int(bytes) / MemoryLayout<AudioObjectID>.size)))
    }
}

/// power()'s and watchPower's: IOKit's power sources.
@MainActor
private enum MacPowerSource {
    static var changed: (@MainActor () -> Void)?
    static var source: CFRunLoopSource?

    static func read() -> PowerState {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return MacPower.power(source: nil) }
        let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue()
        return MacPower.power(source: type.map { $0 as String })
    }

    static func watch(_ changed: @escaping @MainActor () -> Void) {
        self.changed = changed
        guard source == nil else { return }
        let made = IOPSNotificationCreateRunLoopSource({ (_: UnsafeMutableRawPointer?) -> Void in
            // on the main run loop (the source is added there below)
            MainActor.assumeIsolated { MacPowerSource.changed?() }
        }, nil)?.takeRetainedValue()
        guard let made else { return }
        source = made
        CFRunLoopAddSource(CFRunLoopGetMain(), made, .defaultMode)
    }
}

// MARK: (slice 6) EQ files

extension View {
    /// (Slice 6) File > Import EQ File… (⌘O): the Mac's Open panel while `shown`, a plain-text file, one - `chosen` takes
    /// it the way a file opened with deadwax comes (RootView's `shared`: EQImportReading.file, then the preview over
    /// what's up). Cancelled, or refused, nothing.
    func eqOpenPanel(_ shown: Binding<Bool>, chosen: @escaping (URL) -> Void) -> some View {
        fileImporter(isPresented: shown, allowedContentTypes: [.plainText], allowsMultipleSelection: false) {
            (result: Result<[URL], any Error>) -> Void in
            guard case .success(let urls) = result, let url = urls.first else { return }
            chosen(url)
        }
    }

    /// (Slice 6) A plain-text file dropped here - the window, the EQ sheet: read as a file opened with deadwax is
    /// (EQDroppedFile: EQImportReading.file, For the output now), the first of several, then `dropped` (AppNavigation's
    /// `share`). Nothing else is taken: a drop of anything but plain text isn't this one's.
    func eqFileDrop(_ dropped: @escaping (EQImportItem) -> Void) -> some View {
        dropDestination(for: EQDroppedFile.self) { (files: [EQDroppedFile], _: CGPoint) -> Bool in
            guard let file = files.first else { return false }
            dropped(file.item)
            return true
        }
    }

    /// (Slice 6) Export…'s Save items (EQExportMenu): the Mac's Save panel for `file` while it is set - a plain-text
    /// file, named as the share names it (`<output name> EQ.txt`), written where the person saves it. Saved or
    /// cancelled, `file` is let go.
    func eqSavePanel(_ file: Binding<EQExportFile?>) -> some View {
        fileExporter(isPresented: Binding<Bool>(get: { file.wrappedValue != nil }, set: { (up: Bool) -> Void in
            if !up { file.wrappedValue = nil }
        }), item: file.wrappedValue, contentTypes: [.plainText],
        defaultFilename: file.wrappedValue.map { (each: EQExportFile) -> String in
            EQWords.Export.fileName(each.setting.shownName)
        }) { (_: Result<URL, any Error>) -> Void in
            file.wrappedValue = nil
        } onCancellation: {
            file.wrappedValue = nil
        }
    }
}

extension Scene {
    /// The Mac's window: opening at the desktop frame's size (slice 3), and the menus without File > New Window (one
    /// window: never a second copy of the app's pages) or Help (there is no Mac help book) - and (slice 2) deadwax's
    /// own: Settings…, Find, Refresh and Controls (MacCommands). (Slice 6) Every file or link opened with deadwax is this
    /// window's: with it open, RootView's `oneWindow()` takes it there; with it closed (the music playing on), this one
    /// window opens for it - never a second.
    func macWindow(_ menus: MacCommands) -> some Scene {
        defaultSize(width: Platform.Window.opening.width, height: Platform.Window.opening.height)
            .commands {
                CommandGroup(replacing: .newItem) {}
                CommandGroup(replacing: .help) {}
                menus
            }
            .handlesExternalEvents(matching: ["*"])
    }
}

extension View {
    /// Pull to refresh - the iPhone's alone. In the Mac idiom UIKit refuses the refresh control with an exception
    /// ("not supported when running Catalyst apps in the Mac idiom"), so on the Mac there is none: (slice 2) the same
    /// action is the page's View > Refresh (⌘R) while it is the page shown (MacRefresh).
    func pullToRefresh(_ action: @escaping @MainActor @Sendable () async -> Void) -> some View {
        refreshCommand(action)
    }

    /// (Slice 2) ⌘R on a page whose phone pull is the shuffle's (the Library, an album, a playlist): its •••'s own
    /// Refresh, while it is the page shown. Nothing on the iPhone, where the ••• has it.
    func refreshCommand(_ action: @escaping @MainActor @Sendable () async -> Void) -> some View {
        modifier(MacRefreshing(action: action))
    }

    /// (Slice 2) A right-click's menu: `items`, the ••• menu's own (QueueMenuItems). On the iPhone, nothing - no row
    /// there had a long press, and none is added.
    func macContextMenu<Items: View>(@ViewBuilder _ items: () -> Items) -> some View {
        contextMenu(menuItems: items)
    }

    /// (Slice 2) An album's tile or row: its •••'s items on a right-click (MacRightClick.swift).
    func albumRightClick(_ route: AlbumRoute) -> some View {
        modifier(AlbumRightClick(route: route))
    }

    /// (Slice 2) A playlist's row: its page's •••'s items on a right-click (MacRightClick.swift).
    func playlistRightClick(_ route: PlaylistRoute) -> some View {
        modifier(PlaylistRightClick(route: route))
    }

    /// (Slice 2) A sheet's Close, Cancel or Done - or Now Playing's and a cover's: Escape presses it, so Escape does
    /// what it does, asking first where it asks. `on` false: not now - something is typed that this Close would throw
    /// away without asking (Escape then does nothing, and Close is a click away), or a form inside a sheet whose own
    /// Cancel has it. Read only here (an autoclosure): the iPhone never reads it.
    func escapeCloses(_ on: @autoclosure () -> Bool = true) -> some View {
        keyboardShortcut(on() ? .cancelAction : nil)
    }

    /// (Slice 2) A sheet's root: while it is up the page under it is out of the menus' reach - ⌘R, Settings…, Find and
    /// Go to Current Song dimmed, unless a page inside the sheet has a Refresh of its own (MacRefresh, MacSheet).
    func macSheet() -> some View {
        modifier(MacSheet())
    }

    /// (Slice 2) While `on` - work a close would lose (Edit album's changes, a playlist's Edit) - the window can't be
    /// closed: ⌘W and its close button are off until the work is done or discarded (WindowWork).
    func keepsWindowOpen(_ on: @autoclosure () -> Bool) -> some View {
        modifier(WindowKeptOpen(on: on()))
    }

    /// (Slice 2) A dialog's Cancel (Keep editing, Don't delete…): Return presses it, so Return never confirms a delete
    /// or a write.
    func returnCancels() -> some View {
        keyboardShortcut(.defaultAction)
    }

    /// (The Mac redesign, R1) A redesigned dialog's one action, drawn purple (DWButtonStyle's `.pri`): Return presses
    /// it. Never a toolbar's button over a list, whose Return opens the row selected.
    func returnPresses() -> some View {
        keyboardShortcut(.defaultAction)
    }

    /// (The Mac redesign, R1's review) The window named `name` while this is drawn and as it changes - RootView's, for
    /// a launch screen up in place of the app (Sign in, after a sign-out): the desktop frame names it for its page
    /// otherwise, and nil leaves the name to it.
    func namesWindow(_ name: String?) -> some View {
        onChange(of: name, initial: true) { (_: String?, now: String?) -> Void in
            if let now { Platform.nameWindow(now) }
        }
    }

    /// (Slice 2) Search's field takes the cursor at Edit > Find (⌘F, AppNavigation.find) - (slice 3) the sidebar's, its
    /// focus the field's own (`focused`), so the field knows when it has the cursor.
    func findField(_ focused: FocusState<Bool>.Binding) -> some View {
        modifier(FindFocus(focused: focused))
    }

    /// (Slice 3) Search's field: the sidebar's on the Mac (MacSidebarView), so Search's page draws none of its own.
    func searchField(text: Binding<String>, prompt: String) -> some View {
        self
    }

    /// (Slice 3) An album's page, an artist's and the album you don't have: centred at a readable width in the
    /// desktop frame (MacFrame.readableWidth, the web's --app-desk-content-max), the page's room either side of it -
    /// (slice 3's review) as its scroll views' margins, so the page still scrolls under the pointer anywhere across
    /// it and its scroll bar is at the page's edge, rather than the scroll view narrowed to the readable width.
    func readableOnMac() -> some View {
        modifier(ReadableOnMac())
    }

    /// (Slice 3) RootView: the window it is drawn in is the app's own, the one scene shaped (MainWindowMarker).
    func shapesWindow() -> some View {
        background(MainWindowMarker().accessibilityHidden(true))
    }

    /// (Slice 2) The one window: a file opened, or a link, comes to the window that's open rather than a second one -
    /// (slice 6) Finder's Open With, a file dropped on the Dock's icon. Its other half is macWindow's
    /// `handlesExternalEvents(matching:)`, which opens this one window for it when none is open.
    func oneWindow() -> some View {
        handlesExternalEvents(preferring: ["*"], allowing: ["*"])
    }

    /// A presented page on the Mac: given its presenter's models (Presenting.swift - a presentation's own scene starts
    /// it with an empty environment here, and its first `@Environment(PlayerModel.self)` would be a crash).
    func carryingApp(_ carried: AppCarried) -> some View {
        modifier(CarriesApp(carried: carried))
    }

    /// (Slice 7) A sheet that holds pages of its own (Edit album): `size`, MacFrame.sheetSize's for the window it is over -
    /// from macOS 15, where SwiftUI sizes a presentation (presentationSizing, iOS 18 on Catalyst). On macOS 14 the
    /// system's own sheet size, as it was.
    @ViewBuilder func sizedSheet(_ size: MacFrame.Size) -> some View {
        if #available(iOS 18.0, *) {
            presentationSizing(WindowSheetSizing(size: size))
        } else {
            self
        }
    }

    /// (Slice 7) A page of Server settings (its frame, ServerSettingsPageFrame): File > Save changes (⌘S) is its Save
    /// changes while it is the page in front, as deep as it is drawn (MacRefresh.settingsInFront, MacSettingsPage).
    func macSettingsPage() -> some View {
        modifier(MacSettingsPage())
    }

    /// (Slice 7) A page's text field: Tab goes to the next of `order`, the page's fields in the order it draws them, and
    /// Shift-Tab back (MacMenu.tab) - at either end, or from a field not in `order`, the key is the system's, as before.
    func tabs<Field: Hashable>(_ focused: FocusState<Field?>.Binding, in order: [Field]) -> some View {
        onKeyPress(keys: [.tab, Platform.backTab]) { (press: KeyPress) -> KeyPress.Result in
            let back = press.key == Platform.backTab || press.modifiers.contains(.shift)
            guard let next = MacMenu.tab(order, from: focused.wrappedValue, back: back) else { return .ignored }
            focused.wrappedValue = next
            return .handled
        }
    }

    /// (The Mac redesign, R1) ← and → on a control the Mac draws for itself while it has the keyboard's focus (a
    /// segmented control, DWSegmented): `move` with -1 or 1, which says whether it took the key.
    func arrowKeys(_ move: @escaping (Int) -> KeyPress.Result) -> some View {
        onKeyPress(keys: [.leftArrow, .rightArrow]) { (press: KeyPress) -> KeyPress.Result in
            move(press.key == .leftArrow ? -1 : 1)
        }
    }

    /// (The redesign, R8's review) ↑ and ↓, Home and End, and Return on a list the Mac draws for itself while it has the
    /// keyboard's focus (Requests' table, MacTable's rules): `press` with the key, which says whether it took it.
    func listKeys(_ press: @escaping (ListKey) -> KeyPress.Result) -> some View {
        onKeyPress(keys: [.upArrow, .downArrow, .home, .end, .return]) { (key: KeyPress) -> KeyPress.Result in
            switch key.key {
            case .upArrow: return press(.up)
            case .downArrow: return press(.down)
            case .home: return press(.home)
            case .end: return press(.end)
            default: return press(.open)
            }
        }
    }

    /// (Slice 7) The rows selected in a SelectingList: Edit > Copy (⌘C) copies them and Select All (⌘A) selects every
    /// row of `ids` - the system's own two items, never a second ⌘C of deadwax's - `text` what Copy puts on the
    /// clipboard for a selection (nil: Copy dimmed - as it is with no selected row still among `ids`). A view drawing
    /// nothing, behind this one, answers them in the responder chain, taking the keyboard's focus as the selection
    /// changes, and again as a text field lets the cursor go with rows selected (SelectionCopier) - but never from a
    /// text field with the cursor, whose own Copy it is.
    func copiesSelection<ID: Hashable>(_ selection: Binding<Set<ID>>, of ids: [ID],
                                       text: @escaping (Set<ID>) -> String?) -> some View {
        modifier(SelectionCopying(selection: selection, ids: ids, text: text))
    }
}

extension Platform {
    /// (Slice 7) Shift-Tab, as a Mac's keyboard may send it: the back-tab character, U+0019.
    static let backTab = KeyEquivalent(Character(Unicode.Scalar(UInt8(0x19))))
}

/// (Slice 7) A list whose rows are selected as a Mac list's are - a click, ⌘-click and ⇧-click, with no Edit button -
/// into `selection`; ForEach's rows are tagged with their own ids, the rest (a page's line, a spinner) can't be. The
/// iPhone's is the List it was.
struct SelectingList<ID: Hashable, Content: View>: View {
    let selection: Binding<Set<ID>>
    @ViewBuilder let content: () -> Content

    var body: some View {
        List(selection: selection, content: content)
    }
}

/// sizedSheet's: the size proposed to the sheet, which its pages fill.
@available(iOS 18.0, *)
private struct WindowSheetSizing: PresentationSizing {
    let size: MacFrame.Size

    func proposedSize(for root: PresentationSizingRoot, context: PresentationSizingContext) -> ProposedViewSize {
        ProposedViewSize(width: CGFloat(size.width), height: CGFloat(size.height))
    }
}

/// copiesSelection's: the copier behind the list, told when to take the keyboard's focus - each time a selection is made,
/// and (slice 7's review) each time a text field lets the cursor go while rows are selected: a click on a row can land
/// while the sidebar's search still has the cursor, and the same row clicked again changes no selection.
private struct SelectionCopying<ID: Hashable>: ViewModifier {
    let selection: Binding<Set<ID>>
    let ids: [ID]
    let text: (Set<ID>) -> String?
    @State private var asked = 0

    func body(content: Content) -> some View {
        let selection = self.selection
        let ids = self.ids
        let text = self.text
        return content
            .background(SelectionCopier(copied: { () -> String? in text(selection.wrappedValue) },
                                        copies: { () -> Bool in !selection.wrappedValue.isDisjoint(with: ids) },
                                        selectAll: ids.isEmpty ? nil : { selection.wrappedValue = Set(ids) },
                                        asked: asked)
                .accessibilityHidden(true))
            .onChange(of: selection.wrappedValue) { (_: Set<ID>, now: Set<ID>) -> Void in
                if !now.isEmpty { asked += 1 }
            }
            .onChange(of: TextEditing.shared.typing) { (_: Bool, typing: Bool) -> Void in
                if !typing, !selection.wrappedValue.isEmpty { asked += 1 }
            }
    }
}

/// A view drawing nothing, behind the list, that answers Edit > Copy and Select All while it has the keyboard's focus:
/// UIKit asks the first responder, then each next one, whether it can (canPerformAction) - so Copy is dimmed with
/// nothing to copy, and every other action goes on up the chain as before. Asking is cheap (`copies`: a selected row
/// still listed); the text is made only for the copy itself.
private struct SelectionCopier: UIViewRepresentable {
    let copied: () -> String?
    let copies: () -> Bool
    let selectAll: (() -> Void)?
    let asked: Int

    func makeUIView(context: Context) -> Copier {
        Copier()
    }

    func updateUIView(_ copier: Copier, context: Context) {
        copier.copied = copied
        copier.copies = copies
        copier.selectingAll = selectAll
        guard copier.asked != asked else { return }
        copier.asked = asked
        // after this update, not inside it; and never from a text field with the cursor (the sidebar's search)
        Task { @MainActor in
            guard copier.window != nil, !copier.isFirstResponder, !TextEditing.shared.typing else { return }
            _ = copier.becomeFirstResponder()
        }
    }

    final class Copier: UIView {
        var copied: () -> String? = { nil }
        var copies: () -> Bool = { false }
        var selectingAll: (() -> Void)?
        var asked = 0

        override var canBecomeFirstResponder: Bool { true }

        override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
            if action == #selector(UIResponderStandardEditActions.copy(_:)) { return copies() }
            if action == #selector(UIResponderStandardEditActions.selectAll(_:)) { return selectingAll != nil }
            return super.canPerformAction(action, withSender: sender)
        }

        override func copy(_ sender: Any?) {
            guard let text = copied() else { return }
            UIPasteboard.general.string = text
        }

        override func selectAll(_ sender: Any?) {
            selectingAll?()
        }
    }
}

/// readableOnMac's: the page's width read, and the room beyond the readable width given to its scroll views as their
/// content's horizontal margins (MacFrame.readableMargin) - none, the scroll view's own, on a page narrower than that.
private struct ReadableOnMac: ViewModifier {
    @State private var margin: Double = 0

    func body(content: Content) -> some View {
        content
            .contentMargins(.horizontal, margin > 0 ? CGFloat(margin) : nil, for: .scrollContent)
            .onGeometryChange(for: Double.self) { (page: GeometryProxy) -> Double in
                MacFrame.readableMargin(width: Double(page.size.width))
            } action: { (now: Double) -> Void in
                margin = now
            }
    }
}

/// (Slice 3) A view of no size behind RootView: as it is put in a window, that window's scene is the app's own
/// (Platform.mainScene) - the one shaped. UIKit says when a view moves into a window; SwiftUI has no such moment.
private struct MainWindowMarker: UIViewRepresentable {
    func makeUIView(context: Context) -> Marker {
        Marker()
    }

    func updateUIView(_ marker: Marker, context: Context) {}

    final class Marker: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            isUserInteractionEnabled = false
            if let scene = window?.windowScene { Platform.mainScene(scene) }
        }
    }
}

#else

extension Platform {
    /// The iPhone's build.
    static let mac = false

    /// Nothing to do on the iPhone.
    static func launching() {}

    /// The iPhone's dialogs as before: the system draws their Cancel.
    @MainActor static func dialogCancel() -> some View {
        EmptyView()
    }

    // (slice 5) sleep, power, outputs, the display and App Nap

    /// The Mac's alone: a phone's lock is no sleep - it plays on.
    @MainActor static func watchSleep(willSleep: @escaping @MainActor () -> Void, woke: @escaping @MainActor () -> Void) {}

    /// The Mac's alone: the audio session's route change is the phone's (AudioSessionController).
    @MainActor static func watchOutputs(_ gone: @escaping @MainActor () -> Void) {}

    /// The phone's battery, exactly as before (UIDevice.batteryState, monitoring on).
    @MainActor static func power() -> PowerState {
        switch UIDevice.current.batteryState {
        case .charging: return .charging
        case .full: return .full
        case .unplugged: return .unplugged
        case .unknown: return .unknown
        @unknown default: return .unknown
        }
    }

    /// The Mac's alone: the phone's changes come as UIDevice's notification (DownloadModel).
    @MainActor static func watchPower(_ changed: @escaping @MainActor () -> Void) {}

    /// The idle timer, exactly as before.
    @MainActor static func keepDisplayOn(_ on: Bool) {
        UIApplication.shared.isIdleTimerDisabled = on
    }

    /// The Mac's alone: beginBackgroundTask stays as it is.
    @MainActor static func keepWorking(_ work: Work, _ on: Bool) {}

    /// The Mac's alone: the iPhone's window has no name to show.
    @MainActor static func nameWindow(_ name: String) {}
}

// (slice 6) EQ files

extension View {
    /// The Mac's alone: the phone has no File menu - its EQ page's Import from Files… is its way in, as before.
    func eqOpenPanel(_ shown: Binding<Bool>, chosen: @escaping (URL) -> Void) -> some View {
        self
    }

    /// The Mac's alone: nothing is dropped on the phone's screen - its ways in are as before.
    func eqFileDrop(_ dropped: @escaping (EQImportItem) -> Void) -> some View {
        self
    }

    /// The Mac's alone: the phone's Export… shares, as before.
    func eqSavePanel(_ file: Binding<EQExportFile?>) -> some View {
        self
    }
}

extension Scene {
    /// The iPhone's window is the screen, and its menus are the •••s.
    func macWindow(_ menus: MacCommands) -> some Scene {
        self
    }
}

extension View {
    /// Pull to refresh: SwiftUI's own, exactly as before.
    func pullToRefresh(_ action: @escaping @MainActor @Sendable () async -> Void) -> some View {
        refreshable(action: action)
    }

    /// The Mac's alone: the ••• has Refresh.
    func refreshCommand(_ action: @escaping @MainActor @Sendable () async -> Void) -> some View {
        self
    }

    /// The Mac's alone: no long press is added to a row.
    func macContextMenu<Items: View>(@ViewBuilder _ items: () -> Items) -> some View {
        self
    }

    /// The Mac's alone.
    func albumRightClick(_ route: AlbumRoute) -> some View {
        self
    }

    /// The Mac's alone.
    func playlistRightClick(_ route: PlaylistRoute) -> some View {
        self
    }

    /// The Mac's alone: no key is added to a button, and `on` is never read.
    func escapeCloses(_ on: @autoclosure () -> Bool = true) -> some View {
        self
    }

    /// The Mac's alone: a sheet as before.
    func macSheet() -> some View {
        self
    }

    /// The Mac's alone: the iPhone has no window to close, and `on` is never read.
    func keepsWindowOpen(_ on: @autoclosure () -> Bool) -> some View {
        self
    }

    /// The Mac's alone: a dialog's buttons as before.
    func returnCancels() -> some View {
        self
    }

    /// The Mac's alone: the iPhone draws no redesigned dialog.
    func returnPresses() -> some View {
        self
    }

    /// The Mac's alone: the iPhone's window has no name to show.
    func namesWindow(_ name: String?) -> some View {
        self
    }

    /// The Mac's alone: Search's field as before.
    func findField(_ focused: FocusState<Bool>.Binding) -> some View {
        self
    }

    /// Search's field in the navigation bar, always drawn - exactly as before.
    func searchField(text: Binding<String>, prompt: String) -> some View {
        searchable(text: text, placement: .navigationBarDrawer(displayMode: .always), prompt: Text(prompt))
    }

    /// The Mac's alone: the iPhone's page is the screen's width.
    func readableOnMac() -> some View {
        self
    }

    /// The Mac's alone: the iPhone's window is the screen.
    func shapesWindow() -> some View {
        self
    }

    /// The iPhone has one scene.
    func oneWindow() -> some View {
        self
    }

    /// A presented page on the iPhone inherits its presenter's environment, as it always has: nothing to hand on.
    func carryingApp(_ carried: AppCarried) -> some View {
        self
    }

    /// The Mac's alone: the iPhone's sheets are the screen's, as before.
    func sizedSheet(_ size: MacFrame.Size) -> some View {
        self
    }

    /// The Mac's alone: the iPhone has no menus - Save changes is the save bar's.
    func macSettingsPage() -> some View {
        self
    }

    /// The Mac's alone: a field's keys as before.
    func tabs<Field: Hashable>(_ focused: FocusState<Field?>.Binding, in order: [Field]) -> some View {
        self
    }

    /// The Mac's alone: the iPhone draws none of the Mac's controls.
    func arrowKeys(_ move: @escaping (Int) -> KeyPress.Result) -> some View {
        self
    }

    /// The Mac's alone: the iPhone draws none of the Mac's lists.
    func listKeys(_ press: @escaping (ListKey) -> KeyPress.Result) -> some View {
        self
    }

    /// The Mac's alone: a line's long press Copy is the iPhone's, as before.
    func copiesSelection<ID: Hashable>(_ selection: Binding<Set<ID>>, of ids: [ID],
                                       text: @escaping (Set<ID>) -> String?) -> some View {
        self
    }
}

/// The iPhone's list exactly as before: no selection, `selection` never read.
struct SelectingList<ID: Hashable, Content: View>: View {
    let selection: Binding<Set<ID>>
    @ViewBuilder let content: () -> Content

    var body: some View {
        List(content: content)
    }
}

#endif

/// (The redesign, R8's review) A key a list the Mac draws takes (Platform's `listKeys`): ↑, ↓, Home and End move the
/// selection, Return opens the row selected. Named apart from MacTable's own keys, which the iPhone's half never names.
enum ListKey: Sendable, Hashable {
    case up, down, home, end, open
}
