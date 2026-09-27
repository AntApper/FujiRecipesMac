import SwiftUI
import AppKit
import FujiRecipesCore

private struct DataRecoveryAlerts: ViewModifier {
    @ObservedObject var library: CustomRecipeLibrary
    @ObservedObject var loadouts: LoadoutStore

    func body(content: Content) -> some View {
        content
            // Waits for the library alert so both launch notices are shown
            // one after the other instead of competing to present.
            .alert(
                "Staged Drafts Couldn’t Be Read",
                isPresented: Binding(
                    get: { library.loadIssue == nil && loadouts.recoveryNotice != nil },
                    set: { if !$0 { loadouts.acknowledgeRecoveryNotice() } }
                ),
                presenting: loadouts.recoveryNotice
            ) { _ in
                Button("OK") { loadouts.acknowledgeRecoveryNotice() }
                    .keyboardShortcut(.defaultAction)
            } message: { notice in
                Text(notice.message)
            }
            .alert(
                "My Recipes Didn’t Load Cleanly",
                isPresented: Binding(
                    get: { library.loadIssue != nil },
                    set: { if !$0 { library.acknowledgeLoadIssue() } }
                ),
                presenting: library.loadIssue
            ) { issue in
                if let backupURL = issue.backupURL {
                    Button("Show Copy in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([backupURL])
                        library.acknowledgeLoadIssue()
                    }
                }
                Button("OK") { library.acknowledgeLoadIssue() }
                    .keyboardShortcut(.defaultAction)
            } message: { issue in
                Text(issue.message)
            }
    }
}

extension View {
    func dataRecoveryAlerts(library: CustomRecipeLibrary, loadouts: LoadoutStore) -> some View {
        modifier(DataRecoveryAlerts(library: library, loadouts: loadouts))
    }
}
