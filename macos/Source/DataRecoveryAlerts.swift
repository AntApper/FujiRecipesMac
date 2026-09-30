import SwiftUI
import AppKit
import FujiRecipesCore

private struct DataRecoveryAlerts: ViewModifier {
    @ObservedObject var library: CustomRecipeLibrary
    @ObservedObject var loadouts: LoadoutStore
    @ObservedObject var favorites: FavoritesStore

    func body(content: Content) -> some View {
        content
            // Launch notices appear in order: library, staged drafts, favorites.
            // Each dismissal acknowledges only its own store's notice.
            .alert(
                "Favorites Couldn’t Be Read",
                isPresented: Binding(
                    get: {
                        library.loadIssue == nil && loadouts.recoveryNotice == nil && favorites.recoveryNotice != nil
                    },
                    set: { if !$0 { favorites.acknowledgeRecoveryNotice() } }
                ),
                presenting: favorites.recoveryNotice
            ) { _ in
                Button("OK") { favorites.acknowledgeRecoveryNotice() }
                    .keyboardShortcut(.defaultAction)
            } message: { notice in
                Text(notice.message)
            }
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
    func dataRecoveryAlerts(library: CustomRecipeLibrary, loadouts: LoadoutStore, favorites: FavoritesStore) -> some View {
        modifier(DataRecoveryAlerts(library: library, loadouts: loadouts, favorites: favorites))
    }
}
