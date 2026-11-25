import DeadwaxCore
import SwiftUI

/// Settings > Manage (Phase 7 - notes/ios-specs/phase7-managing.md; the web's You.tsx Manage section; since 16 Nov a
/// group of the Settings root): deadwax's managing tools this person may use. Top to bottom, each only with its
/// permission (Core's Managing.tools, the web's `managing` and `albumEdit` by what /me last said): Edit an album (the
/// phone's own row), Needs a look, Library care, People (logins on), Server settings and Event log - the web's five, in
/// its order and words. Drawn only with a row to draw, between Downloads and Account (the web's Manage comes before its
/// Account).
///
/// Phase 8 brings them into the app one at a time (phase8-managing.md 11). Since slice 1 Edit an album is the app's: it
/// pushes Choose the folder (ChooseFolderScreen), whose folder opens Edit album over the tabs - and that page says for
/// itself that it needs deadwax, so the row is never dimmed. Since slice 6 Needs a look is too: it pushes the review
/// queue (NeedsLookScreen), its count at the row's right (QueueCountModel - asked by YouView and MainTabs, never here).
/// Since slice 7 Library care is too: it pushes LibraryCareScreen (Rescan, Get covers, CD art and lyrics, In nobody's
/// library). Since slice 8 Server settings is too: it pushes ServerSettingsScreen (Connections, the organizing verdict,
/// each group of the server's settings a page of its own, one save). Since slice 9 the event log is too: it pushes
/// EventLogScreen (the lines, live, Copy and Clear). Since slice 11 People is too: it pushes PeopleScreen (Unlock
/// People, then Navidrome's accounts - each person's page, Add a person) - so no row opens Safari any more.
///
/// The footer that said which rows opened in Safari, and how Safari signs in apart from the app, went in Phase 8's
/// slice 12 with WebAppRow and the openURL extension that opened them: nothing in the app takes you to the web app
/// (tests/test_ios_no_web_app.py). Nothing is asked of deadwax here - the page each opens asks it itself, says for
/// itself that it needs deadwax, and refuses for itself without its permission.
struct ManageSection: View {
    @Environment(ServerModel.self) private var server
    @Environment(QueueCountModel.self) private var queueCount

    var body: some View {
        let tools = Managing.tools(server.access)
        if !tools.isEmpty {
            Section {
                ForEach(tools, id: \.self) { (tool: Managing.Tool) in
                    if tool == .edit {
                        // (Phase 8, slice 1) the app's own: Choose the folder
                        NavigationLink(value: AppRoute.chooseFolder) {
                            Text(ManagingWords.label(tool))
                        }
                    } else if tool == .queue {
                        // (Phase 8, slice 6) the app's own: the review queue - its count at the right, as a value
                        // (You.tsx's badge; never on a tab), nothing while nobody knows it or it is none
                        NavigationLink(value: AppRoute.needsALook) {
                            LabeledContent(ManagingWords.label(tool)) {
                                Text(queueCount.count.value)
                            }
                            // read once: "Needs a look, 3 albums" (needsLookLabel)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(queueCount.count.spoken)
                        }
                    } else if tool == .care {
                        // (Phase 8, slice 7) the app's own: Rescan, the runs and In nobody's library
                        NavigationLink(value: AppRoute.libraryCare) {
                            Text(ManagingWords.label(tool))
                        }
                    } else if tool == .settings {
                        // (Phase 8, slice 8) the app's own: Connections, the verdict and the server's settings
                        NavigationLink(value: AppRoute.serverSettings) {
                            Text(ManagingWords.label(tool))
                        }
                    } else if tool == .log {
                        // (Phase 8, slice 9) the app's own: the event log, live
                        NavigationLink(value: AppRoute.eventLog) {
                            Text(ManagingWords.label(tool))
                        }
                    } else if tool == .people {
                        // (Phase 8, slice 11) the app's own: People, unlocked with your Navidrome password
                        NavigationLink(value: AppRoute.people) {
                            Text(ManagingWords.label(tool))
                        }
                    }
                }
            } header: {
                Text(ManagingWords.title)
                    .font(Typeface.footnote)
            }
        }
    }
}
